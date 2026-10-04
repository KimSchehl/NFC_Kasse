import database
import pytest


@pytest.fixture
def articles(db):
    with database.get_db() as conn:
        event_id = conn.execute("SELECT id FROM event LIMIT 1").fetchone()["id"]
        cat_id = conn.execute(
            "INSERT INTO category (event_id, name) VALUES (?, ?)", (event_id, "Getränke")
        ).lastrowid

        def insert(name, price, is_payout=0, is_pfand=0, exclude=0):
            return conn.execute(
                "INSERT INTO product (category_id, name, price, is_payout, is_pfand, exclude_from_stats) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (cat_id, name, price, is_payout, is_pfand, exclude),
            ).lastrowid

        return {
            "category_id": cat_id,
            "bier": insert("Bier", 2.50),
            "aufladen": insert("Aufladen 10", -10.00, exclude=1),
            "pfand_plus": insert("Pfand +", 2.00, is_pfand=1, exclude=1),
            "pfand_minus": insert("Pfand -", -2.00, is_pfand=1, exclude=1),
            "payout": insert("Auszahlung", 0.00, is_payout=1),
        }


def _revoke(permission_id: str) -> None:
    with database.get_db() as conn:
        conn.execute(
            "DELETE FROM user_permission WHERE user_id=1 AND permission_id=?", (permission_id,)
        )


def _book(client, headers, product_id: int):
    return client.post(
        "/api/sales/",
        json={"nfc_uid": "TESTUID01", "product_ids": [product_id]},
        headers=headers,
    )


def test_aufladen_needs_guthaben_topup(client, auth_headers, customer_with_balance, articles):
    _revoke("guthaben.topup")
    resp = _book(client, auth_headers, articles["aufladen"])
    assert resp.status_code == 403
    assert "Aufladen" in resp.json()["detail"]


def test_aufladen_allowed_with_guthaben_topup(client, auth_headers, customer_with_balance, articles):
    resp = _book(client, auth_headers, articles["aufladen"])
    assert resp.status_code == 201


def test_pfand_minus_needs_no_guthaben_topup(client, auth_headers, customer_with_balance, articles):
    _revoke("guthaben.topup")
    resp = _book(client, auth_headers, articles["pfand_minus"])
    assert resp.status_code == 201


def test_payout_needs_guthaben_payout(client, auth_headers, customer_with_balance, articles):
    _revoke("guthaben.payout")
    resp = _book(client, auth_headers, articles["payout"])
    assert resp.status_code == 403


def test_bon_print_respects_guthaben_topup(client, auth_headers, db, articles):
    _revoke("guthaben.topup")
    resp = client.post(
        "/api/print/bon",
        json={"items": [{"product_id": articles["aufladen"], "quantity": 1}]},
        headers=auth_headers,
    )
    assert resp.status_code == 403


def test_pfand_flag_forces_exclude_from_stats(client, auth_headers, articles):
    resp = client.post(
        "/api/products/",
        json={
            "name": "Glas Pfand",
            "price": 2.0,
            "category_id": articles["category_id"],
            "is_pfand": True,
            "exclude_from_stats": False,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201
    assert resp.json()["is_pfand"] is True
    assert resp.json()["exclude_from_stats"] is True


def test_default_color_is_normalized_and_tristate(client, auth_headers, articles):
    pid = articles["bier"]

    resp = client.put(f"/api/products/{pid}", json={"color": "#a5d6a7"}, headers=auth_headers)
    assert resp.json()["color"] == "#A5D6A7"

    resp = client.put(f"/api/products/{pid}", json={"name": "Bier hell"}, headers=auth_headers)
    assert resp.json()["color"] == "#A5D6A7"

    resp = client.put(f"/api/products/{pid}", json={"color": None}, headers=auth_headers)
    assert resp.json()["color"] is None

    assert client.put(f"/api/products/{pid}", json={"color": "rot"}, headers=auth_headers).status_code == 422


def test_color_is_listed_for_the_pos_grid(client, auth_headers, articles):
    client.put(f"/api/products/{articles['bier']}", json={"color": "#80DEEA"}, headers=auth_headers)
    resp = client.get("/api/products/", params={"category_id": articles["category_id"]}, headers=auth_headers)
    bier = next(p for p in resp.json() if p["id"] == articles["bier"])
    assert bier["color"] == "#80DEEA"


def test_print_job_status_reports_done_and_error(client, auth_headers, db):
    with database.get_db() as conn:
        event_id = conn.execute("SELECT id FROM event LIMIT 1").fetchone()["id"]
        ok = conn.execute(
            "INSERT INTO print_job (event_id, username, event_name, product_name, price, status) "
            "VALUES (?, 'admin', 'Fest', 'Bier', 2.5, 'done')",
            (event_id,),
        ).lastrowid
        bad = conn.execute(
            "INSERT INTO print_job (event_id, username, event_name, product_name, price, status, error_msg) "
            "VALUES (?, 'admin', 'Fest', 'Bier', 2.5, 'error', 'Port weg')",
            (event_id,),
        ).lastrowid

    resp = client.get("/api/print/jobs", params={"ids": f"{ok},{bad}"}, headers=auth_headers)
    assert resp.status_code == 200
    by_id = {j["id"]: j for j in resp.json()["jobs"]}
    assert by_id[ok]["status"] == "done"
    assert by_id[bad]["status"] == "error"
    assert by_id[bad]["error_msg"] == "Port weg"


def test_print_job_status_rejects_bad_ids(client, auth_headers, db):
    resp = client.get("/api/print/jobs", params={"ids": "abc"}, headers=auth_headers)
    assert resp.status_code == 400
