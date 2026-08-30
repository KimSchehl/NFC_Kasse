def test_book_with_pager_number_creates_open_pager_order(
    client, auth_headers, pager_product_id, customer_with_balance
):
    resp = client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id],
            "pager_number": 3,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    pagers = client.get("/api/pager/", headers=auth_headers)
    assert pagers.status_code == 200
    data = pagers.json()
    assert len(data) == 1
    assert data[0]["item_summary"] == "Pizza Salami"
    assert data[0]["pager_number"] == 3
    assert data[0]["status"] == "open"


def test_book_without_pager_number_creates_no_pager_order(
    client, auth_headers, pager_product_id, customer_with_balance
):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [pager_product_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    pagers = client.get("/api/pager/", headers=auth_headers)
    assert pagers.json() == []


def test_book_multiple_pager_items_creates_single_grouped_entry(
    client, auth_headers, pager_product_id, pager_product_id_2, customer_with_balance
):
    resp = client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id, pager_product_id, pager_product_id_2],
            "pager_number": 7,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    data = client.get("/api/pager/", headers=auth_headers).json()
    assert len(data) == 1
    assert data[0]["item_summary"] == "2× Pizza Salami, Steak"


def test_book_mixed_pager_and_non_pager_items_summary_excludes_non_pager_item(
    client, auth_headers, pager_product_id, product_id, customer_with_balance
):
    resp = client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id, product_id],
            "pager_number": 1,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    data = client.get("/api/pager/", headers=auth_headers).json()
    assert len(data) == 1
    assert data[0]["item_summary"] == "Pizza Salami"


def test_booking_succeeds_with_duplicate_pager_number(
    client, auth_headers, pager_product_id, customer_with_balance
):
    # Two different customers — same-customer rapid rebooking would trip the
    # unrelated 2-second duplicate-submission guard in create_booking().
    for uid in (customer_with_balance, "SECOND_UID"):
        resp = client.post(
            "/api/sales/",
            json={
                "nfc_uid": uid,
                "product_ids": [pager_product_id],
                "pager_number": 5,
            },
            headers=auth_headers,
        )
        assert resp.status_code == 201, resp.text

    data = client.get("/api/pager/", headers=auth_headers).json()
    assert len(data) == 2
    assert all(d["pager_number"] == 5 for d in data)


def test_pager_list_scoped_to_creating_user(
    client, auth_headers, other_user_auth_headers, pager_product_id, customer_with_balance
):
    resp = client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id],
            "pager_number": 9,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    own_list = client.get("/api/pager/", headers=auth_headers).json()
    assert len(own_list) == 1

    other_list = client.get("/api/pager/", headers=other_user_auth_headers).json()
    assert other_list == []


def test_mark_pager_done_changes_status(
    client, auth_headers, pager_product_id, customer_with_balance
):
    client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id],
            "pager_number": 2,
        },
        headers=auth_headers,
    )
    pager_id = client.get("/api/pager/", headers=auth_headers).json()[0]["id"]

    resp = client.post(f"/api/pager/{pager_id}/done", headers=auth_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "done"
    assert resp.json()["done_at"] is not None

    open_list = client.get("/api/pager/", headers=auth_headers).json()
    assert open_list == []
    done_list = client.get("/api/pager/?status=done", headers=auth_headers).json()
    assert len(done_list) == 1


def test_mark_pager_done_twice_returns_400(
    client, auth_headers, pager_product_id, customer_with_balance
):
    client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id],
            "pager_number": 4,
        },
        headers=auth_headers,
    )
    pager_id = client.get("/api/pager/", headers=auth_headers).json()[0]["id"]

    client.post(f"/api/pager/{pager_id}/done", headers=auth_headers)
    resp = client.post(f"/api/pager/{pager_id}/done", headers=auth_headers)
    assert resp.status_code == 400


def test_mark_other_users_pager_done_returns_404(
    client, auth_headers, other_user_auth_headers, pager_product_id, customer_with_balance
):
    client.post(
        "/api/sales/",
        json={
            "nfc_uid": customer_with_balance,
            "product_ids": [pager_product_id],
            "pager_number": 6,
        },
        headers=auth_headers,
    )
    pager_id = client.get("/api/pager/", headers=auth_headers).json()[0]["id"]

    resp = client.post(f"/api/pager/{pager_id}/done", headers=other_user_auth_headers)
    assert resp.status_code == 404
