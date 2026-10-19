"""
Schema v2 -> v3: categories, articles and rights move from the fest to the
Veranstalter (tenant). Built on a real v2 database (tests/legacy_init_db_v2.py).
"""
import json
from pathlib import Path

import pytest
from starlette.testclient import TestClient

import database
from migrations import migrate_v3, run_migrations


def _ids(conn, sql, *params):
    return {r[0] for r in conn.execute(sql, params)}


def _cat(conn, event_id, name):
    return conn.execute("INSERT INTO category (event_id, name) VALUES (?, ?)", (event_id, name)).lastrowid


def _prod(conn, cat_id, name, price, group_id=None):
    return conn.execute(
        "INSERT INTO product (category_id, name, price, group_id) VALUES (?, ?, ?, ?)", (cat_id, name, price, group_id)
    ).lastrowid


def _user(conn, name):
    return conn.execute(
        "INSERT INTO user (tenant_id, username, password_hash) VALUES (1, ?, 'x')", (name,)
    ).lastrowid


def _migrate():
    with database.get_db() as conn:
        run_migrations(conn, bar_chip_uid="BAR")
    migrate_v3(database.DB_PATH)


@pytest.fixture
def v2_data(legacy_v2_db):
    """
    Fest 1 (running): Getränke{Bier 3.0 + Option 0,5l}, Essen{Wurst}
    Intern (2):       Getränke{Kaffee}
    Altfest (3):      Getränke{Bier 2.0 + Option 0,5l}, ended
    """
    with database.get_db() as conn:
        fest, intern = 1, conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]
        old = conn.execute(
            "INSERT INTO event (tenant_id, name, active, ended_at) VALUES (1, 'Altfest', 0, datetime('now'))"
        ).lastrowid

        old_drinks = _cat(conn, old, "Getränke")
        old_bier = _prod(conn, old_drinks, "Bier", 2.0)
        old_opt = _prod(conn, old_drinks, "0,5l", 2.5, group_id=old_bier)
        drinks = _cat(conn, fest, "Getränke")
        bier = _prod(conn, drinks, "Bier", 3.0)
        opt = _prod(conn, drinks, "0,5l", 3.5, group_id=bier)
        food = _cat(conn, fest, "Essen")
        wurst = _prod(conn, food, "Wurst", 4.0)
        intern_drinks = _cat(conn, intern, "Getränke ")  # trailing blank: still the same category
        kaffee = _prod(conn, intern_drinks, "Kaffee", 1.0)

        cust = conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (1, 'C1', 10, 0)"
        ).lastrowid
        for event_id, product, price in [(old, old_bier, 2.0), (old, old_opt, 2.5), (fest, bier, 3.0)]:
            conn.execute(
                "INSERT INTO sale (event_id, customer_id, product_id, price_at_sale, booked_by) VALUES (?, ?, ?, ?, 1)",
                (event_id, cust, product, price),
            )

        bea = _user(conn, "bea")    # rights only in Intern
        carl = _user(conn, "carl")  # rights only in the old fest
        conn.execute("INSERT INTO user_permission (user_id, event_id, permission_id) VALUES (?, ?, 'guthaben.topup')", (bea, intern))
        conn.execute("INSERT INTO user_permission (user_id, event_id, permission_id) VALUES (?, ?, 'statistics.revenue')", (carl, old))
        conn.execute(
            "INSERT INTO user_category_access (user_id, event_id, category_id, can_book) VALUES (?, ?, ?, 1)",
            (bea, old, old_drinks),
        )
        conn.execute(
            "INSERT INTO user_category_access (user_id, event_id, category_id, can_storno_5min) VALUES (?, ?, ?, 1)",
            (bea, fest, drinks),
        )

        conn.execute(
            "INSERT INTO user_preference_store (user_id, key, profile, value) VALUES (1, ?, 'P', ?)",
            (f"layout.cat_{old_drinks}", json.dumps([old_bier, None])),
        )
        conn.execute(
            "INSERT INTO user_preference_store (user_id, key, profile, value) VALUES (1, ?, '*', '\"#FF0000\"')",
            (f"product.color.{old_bier}",),
        )
        revenue = {r[0]: r[1] for r in conn.execute("SELECT event_id, SUM(price_at_sale) FROM sale GROUP BY event_id")}

    return {
        "fest": fest, "intern": intern, "old": old, "drinks": drinks, "food": food, "bier": bier, "opt": opt,
        "wurst": wurst, "kaffee": kaffee, "old_drinks": old_drinks, "old_bier": old_bier, "old_opt": old_opt,
        "bea": bea, "carl": carl, "revenue": revenue,
    }


def test_same_named_categories_and_articles_become_one(v2_data):
    d = v2_data
    _migrate()
    with database.get_db() as conn:
        assert conn.execute("PRAGMA user_version").fetchone()[0] == 3
        cols = {r[1] for r in conn.execute("PRAGMA table_info(category)")}
        assert "event_id" not in cols and "tenant_id" in cols

        cats = {r["name"].strip(): r["id"] for r in conn.execute("SELECT id, name FROM category")}
        assert cats == {"Getränke": d["drinks"], "Essen": d["food"]}  # the running fest's rows survive
        assert _ids(conn, "SELECT name FROM product WHERE deleted = 0") == {"Bier", "0,5l", "Wurst", "Kaffee"}
        assert conn.execute("SELECT COUNT(*) FROM product").fetchone()[0] == 4
        assert conn.execute("SELECT price FROM product WHERE id = ?", (d["bier"],)).fetchone()[0] == 3.0
        assert conn.execute("SELECT group_id FROM product WHERE id = ?", (d["opt"],)).fetchone()[0] == d["bier"]
        assert conn.execute("SELECT category_id FROM product WHERE id = ?", (d["kaffee"],)).fetchone()[0] == d["drinks"]


def test_each_fest_keeps_showing_what_it_had(v2_data):
    d = v2_data
    _migrate()
    with database.get_db() as conn:
        shown = lambda e: _ids(conn, "SELECT category_id FROM event_category WHERE event_id = ?", e)
        articles = lambda e: _ids(conn, "SELECT product_id FROM event_product WHERE event_id = ?", e)
        assert shown(d["fest"]) == {d["drinks"], d["food"]}
        assert shown(d["old"]) == {d["drinks"]}
        assert shown(d["intern"]) == {d["drinks"]}
        assert articles(d["fest"]) == {d["bier"], d["wurst"]}  # options follow their base
        assert articles(d["old"]) == {d["bier"]}
        assert articles(d["intern"]) == {d["kaffee"]}


def test_history_and_revenue_per_fest_are_unchanged(v2_data):
    d = v2_data
    _migrate()
    with database.get_db() as conn:
        revenue = {r[0]: r[1] for r in conn.execute("SELECT event_id, SUM(price_at_sale) FROM sale GROUP BY event_id")}
        assert revenue == d["revenue"]
        assert _ids(conn, "SELECT product_id FROM sale WHERE event_id = ?", d["old"]) == {d["bier"], d["opt"]}
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_rights_belong_to_the_user_afterwards(v2_data):
    d = v2_data
    _migrate()
    with database.get_db() as conn:
        perms = lambda u: _ids(conn, "SELECT permission_id FROM user_permission WHERE user_id = ?", u)
        assert "users.manage_permissions" in perms(1)  # the running fest's rights
        assert perms(d["bea"]) == {"guthaben.topup"}  # nothing in the fest: Intern's
        assert perms(d["carl"]) == {"statistics.revenue"}  # nothing else: his last fest's
        access = conn.execute(
            "SELECT category_id, can_book, can_storno_5min FROM user_category_access WHERE user_id = ?", (d["bea"],)
        ).fetchall()
        assert [tuple(r) for r in access] == [(d["drinks"], 1, 1)]  # both fests' ticks combined


def test_layouts_and_colours_follow_the_merged_ids(v2_data):
    d = v2_data
    _migrate()
    with database.get_db() as conn:
        prefs = {r["key"]: json.loads(r["value"]) for r in conn.execute("SELECT key, value FROM user_preference_store")}
        assert prefs == {f"layout.cat_{d['drinks']}": [d["bier"], None], f"product.color.{d['bier']}": "#FF0000"}


def test_takes_a_backup_first_and_runs_only_once(v2_data):
    _migrate()
    backups = list((Path(database.DB_PATH).parent / "backups").glob("vor-update_*.db"))
    assert len(backups) == 1
    migrate_v3(database.DB_PATH)
    assert len(list((Path(database.DB_PATH).parent / "backups").glob("vor-update_*.db"))) == 1


def test_two_same_named_articles_of_one_fest_stay_separate(legacy_v2_db):
    with database.get_db() as conn:
        old = conn.execute("INSERT INTO event (tenant_id, name, active) VALUES (1, 'Alt', 0)").lastrowid
        drinks = _cat(conn, 1, "Getränke")
        first, second = _prod(conn, drinks, "Bier", 3.0), _prod(conn, drinks, "Bier", 5.0)
        _prod(conn, _cat(conn, old, "Getränke"), "Bier", 2.0)
    _migrate()
    with database.get_db() as conn:
        assert _ids(conn, "SELECT id FROM product") == {first, second}
        assert _ids(conn, "SELECT product_id FROM event_product WHERE event_id = 1") == {first, second}


def test_the_migrated_kasse_works(v2_data, monkeypatch):
    d = v2_data
    _migrate()
    with database.get_db() as conn:  # past the 2-second double-booking guard
        conn.execute("UPDATE sale SET booked_at = datetime(booked_at, '-1 minute')")
    from main import app

    client = TestClient(app)
    token = client.post("/api/auth/login", json={"username": "admin", "password": "admin"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    me = client.get("/api/auth/me", headers=headers).json()
    assert {c["category_name"].strip() for c in me["categories"]} == {"Getränke", "Essen"}
    booking = client.post("/api/sales/", json={"nfc_uid": "C1", "product_ids": [d["bier"]]}, headers=headers)
    assert booking.status_code == 201, booking.text
