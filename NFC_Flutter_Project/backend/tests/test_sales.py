import pytest


def test_balance_new_customer(client, auth_headers):
    resp = client.get("/api/sales/balance/UNKNOWN_UID", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["nfc_uid"] == "UNKNOWN_UID"
    assert data["balance"] == 0.0
    assert data["is_new_customer"] is True


def test_balance_existing_customer(client, auth_headers, customer_with_balance):
    resp = client.get(f"/api/sales/balance/{customer_with_balance}", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["balance"] == 20.0
    assert data["is_new_customer"] is False


def test_balance_requires_auth(client):
    resp = client.get("/api/sales/balance/UID")
    assert resp.status_code == 401


def test_book_single_product(client, auth_headers, product_id, customer_with_balance):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["success"] is True
    assert data["new_balance"] == pytest.approx(17.50)
    assert len(data["sale_ids"]) == 1


def test_book_same_product_twice_counts_as_quantity_two(client, auth_headers, product_id, customer_with_balance):
    """Duplicate product_ids must deduct the price twice — regression for the IN-dedup bug."""
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id, product_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["new_balance"] == pytest.approx(15.00)  # 20.00 - 2 * 2.50
    assert len(data["sale_ids"]) == 2


def test_book_nonexistent_product_returns_404(client, auth_headers, customer_with_balance):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [999999]},
        headers=auth_headers,
    )
    assert resp.status_code == 404


def test_book_empty_product_ids_rejected_with_422(client, auth_headers, customer_with_balance):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": []},
        headers=auth_headers,
    )
    assert resp.status_code == 422


def test_book_creates_new_customer_and_allows_negative_balance(client, auth_headers, product_id):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": "BRAND_NEW_UID", "product_ids": [product_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    assert resp.json()["new_balance"] == pytest.approx(-2.50)


def test_book_requires_auth(client, product_id):
    resp = client.post("/api/sales/", json={"nfc_uid": "UID", "product_ids": [product_id]})
    assert resp.status_code == 401


def test_cancel_restores_balance(client, auth_headers, product_id, customer_with_balance):
    book = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    assert book.status_code == 201
    sale_id = book.json()["sale_ids"][0]

    cancel = client.post(f"/api/sales/{sale_id}/cancel", headers=auth_headers)
    assert cancel.status_code == 200
    assert cancel.json()["refunded_amount"] == pytest.approx(2.50)

    balance = client.get(f"/api/sales/balance/{customer_with_balance}", headers=auth_headers)
    assert balance.json()["balance"] == pytest.approx(20.00)


def test_cancel_same_sale_twice_returns_400(client, auth_headers, product_id, customer_with_balance):
    book = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    sale_id = book.json()["sale_ids"][0]

    client.post(f"/api/sales/{sale_id}/cancel", headers=auth_headers)
    resp = client.post(f"/api/sales/{sale_id}/cancel", headers=auth_headers)
    assert resp.status_code == 400


def test_cancel_nonexistent_sale_returns_404(client, auth_headers):
    resp = client.post("/api/sales/999999/cancel", headers=auth_headers)
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Article options ("Currywurst mit Pommes") — stock/points resolve to the
# base article, never the option itself, which never carries its own.
# ---------------------------------------------------------------------------

def _customer_id(nfc_uid):
    import database
    with database.get_db() as conn:
        return conn.execute("SELECT id FROM customer WHERE nfc_uid=?", (nfc_uid,)).fetchone()["id"]


def _base_stock(base_id):
    import database
    with database.get_db() as conn:
        return conn.execute("SELECT stock FROM product WHERE id=?", (base_id,)).fetchone()["stock"]


def _leaderboard_points(customer_id):
    import database
    with database.get_db() as conn:
        row = conn.execute(
            "SELECT points FROM leaderboard_score WHERE customer_id=?", (customer_id,)
        ).fetchone()
        return row["points"] if row else 0


def test_book_option_charges_option_price_and_decrements_base_stock(
    client, auth_headers, option_product_ids, customer_with_balance
):
    _, base_id, option_id = option_product_ids
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [option_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["new_balance"] == pytest.approx(14.00)  # 20.00 - 6.00 (option price)
    assert _base_stock(base_id) == 9  # base's stock, not the option's own (always None)


def test_book_base_directly_when_it_has_options_still_works(
    client, auth_headers, option_product_ids, customer_with_balance
):
    """The base article stays a normal, independently bookable product even
    though it has options — the picker is a client-side UX choice, not a
    server-enforced restriction."""
    _, base_id, _ = option_product_ids
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [base_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["new_balance"] == pytest.approx(15.00)  # 20.00 - 5.00 (base price)


def test_book_option_out_of_stock_uses_base_stock(client, auth_headers, option_product_ids, customer_with_balance):
    import database
    _, base_id, option_id = option_product_ids
    with database.get_db() as conn:
        conn.execute("UPDATE product SET stock=0 WHERE id=?", (base_id,))

    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [option_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 400
    # Error names the base article — correct, since that's the actual
    # stock-tracked resource the option shares, not a bug to "fix".
    assert "Currywurst" in resp.json()["detail"]


def test_cancel_option_booking_restores_base_not_option(
    client, auth_headers, option_product_ids, customer_with_balance
):
    _, base_id, option_id = option_product_ids
    customer_id = _customer_id(customer_with_balance)
    assert _leaderboard_points(customer_id) == 0

    book = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [option_id]},
        headers=auth_headers,
    )
    assert book.status_code == 201, book.text
    sale_id = book.json()["sale_ids"][0]

    assert _base_stock(base_id) == 9
    assert _leaderboard_points(customer_id) == 5  # base's points, option carries none of its own

    cancel = client.post(f"/api/sales/{sale_id}/cancel", headers=auth_headers)
    assert cancel.status_code == 200, cancel.text
    assert cancel.json()["refunded_amount"] == pytest.approx(6.00)  # the option's own price

    # The critical assertions: cancelling an option-booked sale must restore
    # the BASE's stock/points, not silently no-op against the option's own
    # (always None/unset) stock/points.
    assert _base_stock(base_id) == 10
    assert _leaderboard_points(customer_id) == 0

    import database
    with database.get_db() as conn:
        option_row = conn.execute("SELECT stock, points FROM product WHERE id=?", (option_id,)).fetchone()
    assert option_row["stock"] is None
    assert option_row["points"] == 0
