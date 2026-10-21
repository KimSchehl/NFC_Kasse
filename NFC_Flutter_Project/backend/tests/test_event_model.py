import hashlib
import sqlite3
import time

import pytest

import database
import db_backup
from migrations import migrate_v3, run_migrations
from tests.conftest import add_category, add_product


def _set_active(conn, event_id):
    conn.execute("UPDATE event SET active = 0 WHERE tenant_id = 1")
    conn.execute("UPDATE event SET active = 1 WHERE id = ?", (event_id,))


def _new_event(conn, name, deposit, is_intern=0):
    return conn.execute(
        "INSERT INTO event (tenant_id, name, active, chip_deposit, is_intern) VALUES (1, ?, 0, ?, ?)",
        (name, deposit, is_intern),
    ).lastrowid


def _category_with_product(conn, event_id, name, price, **flags):
    cat_id = add_category(conn, f"{name} Warengruppe", event_id=event_id)
    product_id = add_product(
        conn, cat_id, name, price, event_id=event_id,
        points=flags.get("points", 0), is_payout=flags.get("is_payout", 0),
    )
    return cat_id, product_id


def test_fresh_install_runs_one_fest_and_keeps_intern_inactive(db):
    with database.get_db() as conn:
        rows = conn.execute("SELECT name, active, is_intern FROM event ORDER BY id").fetchall()
    assert [(r["active"], r["is_intern"]) for r in rows] == [(1, 0), (0, 1)]
    assert rows[1]["name"] == "Intern"


def test_only_one_active_event_per_tenant(db):
    with database.get_db() as conn:
        run_migrations(conn, bar_chip_uid="BAR")
    with pytest.raises(sqlite3.IntegrityError):
        with database.get_db() as conn:
            conn.execute("UPDATE event SET active = 1 WHERE is_intern = 1")


def test_pfand_is_stored_on_the_chip_and_refunded_exactly_at_payout(client, auth_headers, db):
    with database.get_db() as conn:
        conn.execute("UPDATE event SET chip_deposit = 3.0 WHERE id = 1")
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (1, 'PFAND0001', 10.0, 1)"
        )
        _, bier = _category_with_product(conn, 1, "Bier", 2.50)

    booking = client.post(
        "/api/sales/", json={"nfc_uid": "PFAND0001", "product_ids": [bier]}, headers=auth_headers
    )
    assert booking.status_code == 201, booking.text
    assert booking.json()["chip_deposit_applied"] == 3.0
    assert booking.json()["new_balance"] == pytest.approx(4.5)

    balance = client.get("/api/sales/balance/PFAND0001", headers=auth_headers).json()
    assert balance["chip_deposit"] == 3.0
    assert balance["is_new_customer"] is False

    with database.get_db() as conn:
        herbst = _new_event(conn, "Herbstfest", 5.0)
        _set_active(conn, herbst)  # rights belong to the user, nothing to copy
        _, payout = _category_with_product(conn, herbst, "Auszahlung", 0.0, is_payout=1)

    time.sleep(2.1)  # the double-booking guard refuses a second booking on the same chip within 2 s
    payout_resp = client.post(
        "/api/sales/", json={"nfc_uid": "PFAND0001", "product_ids": [payout]}, headers=auth_headers
    )
    assert payout_resp.status_code == 201, payout_resp.text
    assert payout_resp.json()["chip_deposit_refunded"] == 3.0
    with database.get_db() as conn:
        paid = conn.execute(
            "SELECT price_at_sale FROM sale WHERE id = ?", (payout_resp.json()["sale_ids"][0],)
        ).fetchone()[0]
    assert paid == pytest.approx(4.5 + 3.0)


def test_leaderboard_points_and_opt_in_belong_to_one_event(client, auth_headers, db):
    from routers import leaderboard

    with database.get_db() as conn:
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, customer_name) "
            "VALUES (1, 'LB000001', 0.0, 0, 'Anna')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000001'").fetchone()[0]
        _, product = _category_with_product(conn, 1, "Radler", 2.5, points=2)
        conn.execute(
            "INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES (1, ?, 1)", (cid,)
        )

    booking = client.post(
        "/api/sales/", json={"nfc_uid": "LB000001", "product_ids": [product]}, headers=auth_headers
    )
    assert booking.status_code == 201, booking.text
    assert leaderboard._fetch_top10() == [
        {"rank": 1, "name": "Anna", "chip_id": hashlib.sha256(b"LB000001").hexdigest()[:12], "points": 2}
    ]

    with database.get_db() as conn:
        _set_active(conn, _new_event(conn, "Herbstfest", 3.0))
    assert leaderboard._fetch_top10() == []

    with database.get_db() as conn:
        _set_active(conn, 1)
    assert leaderboard._fetch_top10()[0]["points"] == 2


def test_intern_bookings_give_no_points_and_no_leaderboard(client, auth_headers, db):
    from routers import leaderboard

    with database.get_db() as conn:
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, customer_name) "
            "VALUES (1, 'LB000002', 0.0, 0, 'Ben')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000002'").fetchone()[0]
        conn.execute(
            "INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES (1, ?, 1)", (cid,)
        )
        intern_id = conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]
        _set_active(conn, intern_id)
        _, product = _category_with_product(conn, intern_id, "Kaffee", 1.0, points=2)

    booking = client.post(
        "/api/sales/", json={"nfc_uid": "LB000002", "product_ids": [product]}, headers=auth_headers
    )
    assert booking.status_code == 201, booking.text
    with database.get_db() as conn:
        points = conn.execute(
            "SELECT points FROM sale WHERE id = ?", (booking.json()["sale_ids"][0],)
        ).fetchone()[0]
    assert points == 0
    assert leaderboard._fetch_top10() == []


def test_cancelled_sale_no_longer_counts_for_the_leaderboard(client, auth_headers, db):
    from routers import leaderboard

    with database.get_db() as conn:
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, customer_name) "
            "VALUES (1, 'LB000003', 0.0, 0, 'Cara')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000003'").fetchone()[0]
        _, product = _category_with_product(conn, 1, "Wasser", 1.5, points=4)
        conn.execute(
            "INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES (1, ?, 1)", (cid,)
        )

    booking = client.post(
        "/api/sales/", json={"nfc_uid": "LB000003", "product_ids": [product]}, headers=auth_headers
    )
    assert leaderboard._fetch_top10()[0]["points"] == 4

    cancel = client.post(f"/api/sales/{booking.json()['sale_ids'][0]}/cancel", headers=auth_headers)
    assert cancel.status_code == 200, cancel.text
    assert leaderboard._fetch_top10()[0]["points"] == 0


def test_migration_from_the_previous_schema_backfills_pfand_points_and_opt_in(legacy_v2_db):
    with database.get_db() as conn:
        conn.execute("DELETE FROM user_permission WHERE event_id = (SELECT id FROM event WHERE is_intern = 1)")
        conn.execute("DELETE FROM event WHERE is_intern = 1")
        for table, column in [
            ("event", "chip_deposit"),
            ("event", "is_intern"),
            ("customer", "deposit_paid"),
            ("sale", "points"),
        ]:
            conn.execute(f"ALTER TABLE {table} DROP COLUMN {column}")
        conn.execute("DROP TABLE leaderboard_entry")
        conn.execute("PRAGMA user_version = 1")

        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (1, 'OLD00001', 5.0, 0)"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'OLD00001'").fetchone()[0]
        cat_id = conn.execute("INSERT INTO category (event_id, name) VALUES (1, 'Bier Warengruppe')").lastrowid
        product = conn.execute(
            "INSERT INTO product (category_id, name, price, points) VALUES (?, 'Bier', 2.5, 3)", (cat_id,)
        ).lastrowid
        conn.execute(
            "INSERT INTO sale (event_id, customer_id, product_id, price_at_sale, booked_by) "
            "VALUES (1, ?, ?, 2.5, 1)",
            (cid, product),
        )
        conn.execute(
            "INSERT INTO leaderboard_score (customer_id, points, opt_in) VALUES (?, 3, 1)", (cid,)
        )

    with database.get_db() as conn:
        run_migrations(conn, bar_chip_uid="BAR")
    migrate_v3(database.DB_PATH)

    with database.get_db() as conn:
        event = conn.execute("SELECT chip_deposit FROM event WHERE active = 1").fetchone()
        assert conn.execute("SELECT COUNT(*) FROM event WHERE is_intern = 1").fetchone()[0] == 1
        assert conn.execute(
            "SELECT deposit_paid FROM customer WHERE nfc_uid = 'OLD00001'"
        ).fetchone()[0] == event["chip_deposit"]
        assert conn.execute("SELECT deposit_paid FROM customer WHERE nfc_uid = 'BAR'").fetchone()[0] == 0
        assert conn.execute("SELECT points FROM sale").fetchone()[0] == 3
        assert conn.execute(
            "SELECT opt_in FROM leaderboard_entry WHERE customer_id = ?", (cid,)
        ).fetchone()[0] == 1
        assert conn.execute("PRAGMA user_version").fetchone()[0] == db_backup.SCHEMA_VERSION
