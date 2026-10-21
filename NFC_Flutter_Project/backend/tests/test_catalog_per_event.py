"""
Categories and articles belong to the Veranstalter and are switched on per
fest (schema v3): the endpoints the app uses for that.
"""
import database
import pytest

from tests.conftest import add_category, add_product


@pytest.fixture
def catalog(db):
    with database.get_db() as conn:
        intern = conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]
        drinks = add_category(conn, "Getränke")
        bier = add_product(conn, drinks, "Bier", 3.0)
        cola = add_product(conn, drinks, "Cola", 2.0)
        # Exists for the Veranstalter, but only switched on in Intern.
        coffee = add_category(conn, "Kaffeebar", event_id=intern)
        kaffee = add_product(conn, coffee, "Kaffee", 1.5, event_id=intern)
    return {"drinks": drinks, "bier": bier, "cola": cola, "coffee": coffee, "kaffee": kaffee}


def test_pos_lists_only_what_the_fest_shows(client, auth_headers, catalog):
    cats = client.get("/api/products/categories", headers=auth_headers).json()
    assert [c["name"] for c in cats] == ["Getränke"]
    every = client.get("/api/products/categories?all=true", headers=auth_headers).json()
    assert {c["name"]: c["active_in_event"] for c in every} == {"Getränke": True, "Kaffeebar": False}
    me = client.get("/api/auth/me", headers=auth_headers).json()
    assert [c["category_name"] for c in me["categories"]] == ["Getränke"]


def test_all_categories_need_manager_or_rights_admin(client, other_user_auth_headers, catalog):
    resp = client.get("/api/products/categories?all=true", headers=other_user_auth_headers)
    assert resp.status_code == 403


def test_switching_a_category_on_brings_its_articles(client, auth_headers, catalog):
    resp = client.patch(f"/api/products/categories/{catalog['coffee']}/active", json={"active": True}, headers=auth_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["active_in_event"] is True
    products = client.get(f"/api/products/?category_id={catalog['coffee']}", headers=auth_headers).json()
    assert [p["name"] for p in products] == ["Kaffee"]

    client.patch(f"/api/products/categories/{catalog['coffee']}/active", json={"active": False}, headers=auth_headers)
    resp = client.get(f"/api/products/?category_id={catalog['coffee']}", headers=auth_headers)
    assert resp.status_code == 404


def test_switching_a_category_needs_the_deactivate_right(client, auth_headers, catalog):
    with database.get_db() as conn:
        conn.execute("DELETE FROM user_permission WHERE user_id = 1 AND permission_id = 'categories.deactivate'")
    resp = client.patch(f"/api/products/categories/{catalog['coffee']}/active", json={"active": True}, headers=auth_headers)
    assert resp.status_code == 403


def test_switching_an_article_off_hides_it_and_blocks_booking(client, auth_headers, catalog, customer_with_balance):
    resp = client.patch(f"/api/products/{catalog['cola']}/event-active", json={"active": False}, headers=auth_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["in_event"] is False

    names = [p["name"] for p in client.get(f"/api/products/?category_id={catalog['drinks']}", headers=auth_headers).json()]
    assert names == ["Bier"]
    admin = client.get("/api/products/admin", headers=auth_headers).json()
    drinks = next(c for c in admin["categories"] if c["id"] == catalog["drinks"])
    assert {p["name"]: p["in_event"] for p in drinks["products"]} == {"Bier": True, "Cola": False}

    booking = client.post("/api/sales/", json={"nfc_uid": customer_with_balance, "product_ids": [catalog["cola"]]}, headers=auth_headers)
    assert booking.status_code == 409
    assert booking.json()["code"] == "event_changed"


def test_switched_off_article_counts_as_removed_for_the_sync_poll(client, auth_headers, catalog):
    since = "2000-01-01T00:00:00+00:00"
    client.patch(f"/api/products/{catalog['cola']}/event-active", json={"active": False}, headers=auth_headers)
    changes = client.get(
        "/api/products/changed", params={"category_id": catalog["drinks"], "since": since}, headers=auth_headers
    ).json()
    assert catalog["cola"] in changes["removed_ids"]


def test_new_category_and_article_are_switched_on_in_the_running_fest(client, auth_headers, db):
    cat = client.post("/api/products/categories", json={"name": "Essen"}, headers=auth_headers).json()
    assert cat["active_in_event"] is True
    product = client.post(
        "/api/products/", json={"name": "Wurst", "price": 4.0, "category_id": cat["id"]}, headers=auth_headers
    ).json()
    assert product["in_event"] is True
    assert [p["name"] for p in client.get(f"/api/products/?category_id={cat['id']}", headers=auth_headers).json()] == ["Wurst"]


def test_category_rights_can_be_given_for_categories_not_in_the_fest(client, auth_headers, other_user_auth_headers, catalog):
    users = client.get("/api/users/", headers=auth_headers).json()
    other = next(u for u in users if u["username"] == "other_operator")
    resp = client.put(
        f"/api/users/{other['id']}/categories",
        json={"categories": [{"category_id": catalog["coffee"], "can_book": True}]},
        headers=auth_headers,
    )
    assert resp.status_code == 204, resp.text
    perms = client.get(f"/api/users/{other['id']}/permissions", headers=auth_headers).json()
    assert [c["category_id"] for c in perms["categories"]] == [catalog["coffee"]]
    # Not switched on in the running fest, so not on the other user's till.
    assert client.get("/api/auth/me", headers=other_user_auth_headers).json()["categories"] == []


def test_revenue_keeps_a_category_that_was_sold_and_then_switched_off(client, auth_headers, catalog, customer_with_balance):
    booking = client.post("/api/sales/", json={"nfc_uid": customer_with_balance, "product_ids": [catalog["bier"]]}, headers=auth_headers)
    assert booking.status_code == 201, booking.text
    client.patch(f"/api/products/categories/{catalog['drinks']}/active", json={"active": False}, headers=auth_headers)
    revenue = client.get("/api/stats/revenue", headers=auth_headers).json()
    assert {c["category_name"]: c["revenue"] for c in revenue["by_category"]} == {"Getränke": 3.0}


def test_other_veranstalter_cannot_touch_the_catalog(client, auth_headers, catalog):
    with database.get_db() as conn:
        conn.execute("INSERT INTO tenant (id, name) VALUES (2, 'Anderer Veranstalter')")
        foreign = conn.execute("INSERT INTO category (tenant_id, name) VALUES (2, 'Fremd')").lastrowid
    resp = client.patch(f"/api/products/categories/{foreign}/active", json={"active": True}, headers=auth_headers)
    assert resp.status_code == 404
    resp = client.post("/api/products/", json={"name": "X", "price": 1.0, "category_id": foreign}, headers=auth_headers)
    assert resp.status_code == 404


def test_catalog_writes_bump_the_revision_other_devices_poll(client, auth_headers, catalog):
    def rev():
        return client.get("/health").json()["catalog_rev"]

    start = rev()
    resp = client.post(
        "/api/products/", json={"category_id": catalog["drinks"], "name": "Wasser", "price": 1.0},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    assert rev() == start + 1
    assert client.patch(
        f"/api/products/{catalog['bier']}/event-active", json={"active": False}, headers=auth_headers,
    ).status_code == 200
    assert client.patch(
        f"/api/products/categories/{catalog['coffee']}/active", json={"active": True}, headers=auth_headers,
    ).status_code == 200
    assert rev() == start + 3
    # Reads leave it alone.
    client.get(f"/api/products/?category_id={catalog['drinks']}", headers=auth_headers)
    assert rev() == start + 3
