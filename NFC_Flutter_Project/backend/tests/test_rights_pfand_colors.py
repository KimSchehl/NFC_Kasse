import database
import pytest

from tests.conftest import add_category, add_product


@pytest.fixture
def articles(db):
    with database.get_db() as conn:
        cat_id = add_category(conn, "Getränke")

        def insert(name, price, is_payout=0, is_pfand=0, exclude=0):
            return add_product(
                conn, cat_id, name, price, is_payout=is_payout, is_pfand=is_pfand, exclude_from_stats=exclude,
            )

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
            "DELETE FROM user_permission WHERE user_id=(SELECT id FROM app_user WHERE username = 'admin' ORDER BY id LIMIT 1) AND permission_id=?", (permission_id,)
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
            "VALUES (?, 'admin', 'Fest', 'Bier', 2.5, 'done') RETURNING id",
            (event_id,),
        ).lastrowid
        bad = conn.execute(
            "INSERT INTO print_job (event_id, username, event_name, product_name, price, status, error_msg) "
            "VALUES (?, 'admin', 'Fest', 'Bier', 2.5, 'error', 'Port weg') RETURNING id",
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


def test_category_color_is_normalized_tristate_and_listed(client, auth_headers):
    resp = client.post("/api/products/categories", json={"name": "Farbig", "color": "#ff8800"}, headers=auth_headers)
    assert resp.status_code == 201, resp.text
    cat = resp.json()
    assert cat["color"] == "#FF8800"

    # Omitted color keeps it, explicit null clears it.
    assert client.put(f"/api/products/categories/{cat['id']}", json={"name": "Bunt"}, headers=auth_headers).json()["color"] == "#FF8800"
    listed = {c["id"]: c for c in client.get("/api/products/categories", headers=auth_headers).json()}
    assert listed[cat["id"]]["color"] == "#FF8800"
    admin = {c["id"]: c for c in client.get("/api/products/admin", headers=auth_headers).json()["categories"]}
    assert admin[cat["id"]]["color"] == "#FF8800"

    assert client.put(f"/api/products/categories/{cat['id']}", json={"color": None}, headers=auth_headers).json()["color"] is None
    assert client.put(f"/api/products/categories/{cat['id']}", json={"color": "blau"}, headers=auth_headers).status_code == 422
    assert client.post("/api/products/categories", json={"name": "X", "color": "#12345"}, headers=auth_headers).status_code == 422
