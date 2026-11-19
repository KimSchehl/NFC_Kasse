import hashlib
import time

import pytest

import database
from tests.conftest import FEST_SQL, TENANT_SQL, add_category, add_product, seeded_id


def _set_active(conn, event_id):
    conn.execute(f"UPDATE event SET active = 0 WHERE tenant_id = {TENANT_SQL}")
    conn.execute("UPDATE event SET active = 1 WHERE id = ?", (event_id,))


def _new_event(conn, name, deposit, is_intern=0):
    return conn.execute(
        f"INSERT INTO event (tenant_id, name, active, chip_deposit, is_intern) VALUES ({TENANT_SQL}, ?, 0, ?, ?) RETURNING id",
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
    with pytest.raises(database.IntegrityError):
        with database.get_db() as conn:
            conn.execute("UPDATE event SET active = 1 WHERE is_intern = 1")


def test_pfand_is_stored_on_the_chip_and_refunded_exactly_at_payout(client, auth_headers, db):
    with database.get_db() as conn:
        conn.execute(f"UPDATE event SET chip_deposit = 3.0 WHERE id = {FEST_SQL}")
        conn.execute(
            f"INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES ({TENANT_SQL}, 'PFAND0001', 10.0, 1)"
        )
        _, bier = _category_with_product(conn, seeded_id(FEST_SQL), "Bier", 2.50)

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
            f"VALUES ({TENANT_SQL}, 'LB000001', 0.0, 0, 'Anna')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000001'").fetchone()[0]
        _, product = _category_with_product(conn, seeded_id(FEST_SQL), "Radler", 2.5, points=2)
        conn.execute(
            f"INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES ({FEST_SQL}, ?, 1)", (cid,)
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
        _set_active(conn, seeded_id(FEST_SQL))
    assert leaderboard._fetch_top10()[0]["points"] == 2


def test_intern_bookings_give_no_points_and_no_leaderboard(client, auth_headers, db):
    from routers import leaderboard

    with database.get_db() as conn:
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, customer_name) "
            f"VALUES ({TENANT_SQL}, 'LB000002', 0.0, 0, 'Ben')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000002'").fetchone()[0]
        conn.execute(
            f"INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES ({FEST_SQL}, ?, 1)", (cid,)
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
            f"VALUES ({TENANT_SQL}, 'LB000003', 0.0, 0, 'Cara')"
        )
        cid = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'LB000003'").fetchone()[0]
        _, product = _category_with_product(conn, seeded_id(FEST_SQL), "Wasser", 1.5, points=4)
        conn.execute(
            f"INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES ({FEST_SQL}, ?, 1)", (cid,)
        )

    booking = client.post(
        "/api/sales/", json={"nfc_uid": "LB000003", "product_ids": [product]}, headers=auth_headers
    )
    assert leaderboard._fetch_top10()[0]["points"] == 4

    cancel = client.post(f"/api/sales/{booking.json()['sale_ids'][0]}/cancel", headers=auth_headers)
    assert cancel.status_code == 200, cancel.text
    assert leaderboard._fetch_top10()[0]["points"] == 0
