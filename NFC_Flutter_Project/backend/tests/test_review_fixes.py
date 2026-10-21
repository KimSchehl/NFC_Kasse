"""Fixes from the 2026-10-20 code review."""

import json

import database
from tests.conftest import add_category, add_product


def _book(client, headers, product_ids, uid="TESTUID01"):
    return client.post("/api/sales/", json={"nfc_uid": uid, "product_ids": product_ids}, headers=headers)


def test_payout_cannot_be_cancelled(client, auth_headers, customer_with_balance):
    with database.get_db() as conn:
        payout_id = add_product(conn, add_category(conn, "Kasse"), "Auszahlung", 0.0, is_payout=1)
    sale_id = _book(client, auth_headers, [payout_id]).json()["sale_ids"][0]
    resp = client.post(f"/api/sales/{sale_id}/cancel", headers=auth_headers)
    assert resp.status_code == 400
    assert "Auszahlung" in resp.json()["detail"]


def test_option_of_sold_out_base_is_rejected(client, auth_headers, option_product_ids, customer_with_balance):
    _, base_id, option_id = option_product_ids
    with database.get_db() as conn:
        conn.execute("UPDATE product SET active=0 WHERE id=?", (base_id,))
    assert _book(client, auth_headers, [option_id]).status_code == 400


def test_article_of_deleted_category_is_not_bookable(client, auth_headers, product_id, customer_with_balance):
    with database.get_db() as conn:
        conn.execute("UPDATE category SET deleted=1 WHERE id=(SELECT category_id FROM product WHERE id=?)", (product_id,))
    assert _book(client, auth_headers, [product_id]).status_code == 404


def test_pager_order_of_option_keeps_its_sale_ids(client, auth_headers, customer_with_balance):
    with database.get_db() as conn:
        cat_id = add_category(conn, "Küche")
        base_id = add_product(conn, cat_id, "Currywurst", 5.0, requires_pager=1)
        option_id = add_product(conn, cat_id, "Currywurst mit Pommes", 6.0, group_id=base_id)
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [option_id], "pager_number": 3},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    with database.get_db() as conn:
        sale_ids = json.loads(conn.execute("SELECT sale_ids FROM pager_order").fetchone()[0])
    assert sale_ids == resp.json()["sale_ids"]


def test_topup_limits(client, auth_headers):
    def topup(amount):
        return client.post("/api/topup/", json={"nfc_uid": "X1", "amount": amount}, headers=auth_headers)

    assert topup(1000).status_code == 201
    assert topup(1000.01).status_code == 422
    assert topup("NaN").status_code == 422
    assert topup(-5).status_code == 422


def test_last_manager_cannot_drop_own_permission_management(client, auth_headers):
    resp = client.put("/api/users/1/permissions", json={"permission_ids": ["users.view"]}, headers=auth_headers)
    assert resp.status_code == 400


def test_bon_print_needs_can_book(client, auth_headers, other_user_auth_headers, product_id):
    other_id = client.get("/api/users/", headers=auth_headers).json()
    other_id = next(u["id"] for u in other_id if u["username"] == "other_operator")
    client.put(f"/api/users/{other_id}/permissions", json={"permission_ids": ["bon.drucken"]}, headers=auth_headers)
    resp = client.post(
        "/api/print/bon", json={"items": [{"product_id": product_id, "quantity": 1}]}, headers=other_user_auth_headers
    )
    assert resp.status_code == 403
