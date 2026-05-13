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
