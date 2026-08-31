def _grant_edit_article(client, auth_headers, user_id, category_id):
    """Grants can_edit_article on category_id to user_id via the users API."""
    resp = client.put(
        f"/api/users/{user_id}/categories",
        json={"categories": [{"category_id": category_id, "can_edit_article": True}]},
        headers=auth_headers,
    )
    assert resp.status_code == 204, resp.text


def _create_user(client, auth_headers, username):
    resp = client.post(
        "/api/users/",
        json={"username": username, "password": "password123"},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    user_id = resp.json()["id"]

    login = client.post("/api/auth/login", json={"username": username, "password": "password123"})
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return user_id, {"Authorization": f"Bearer {token}"}


def test_create_option_rejects_cross_category_group_id(client, auth_headers, option_product_ids):
    cat_id, base_id, _ = option_product_ids
    other_cat = client.post(
        "/api/products/categories", json={"name": "Andere Kategorie"}, headers=auth_headers
    ).json()

    resp = client.post(
        "/api/products/",
        json={"name": "mit Brötchen", "price": 4.5, "category_id": other_cat["id"], "group_id": base_id},
        headers=auth_headers,
    )
    assert resp.status_code == 400


def test_create_option_rejects_nested_group(client, auth_headers, option_product_ids):
    cat_id, base_id, option_id = option_product_ids

    resp = client.post(
        "/api/products/",
        json={"name": "Extra Portion", "price": 1.0, "category_id": cat_id, "group_id": option_id},
        headers=auth_headers,
    )
    assert resp.status_code == 400


def test_create_option_rejects_nonexistent_group_id(client, auth_headers, option_product_ids):
    cat_id, _, _ = option_product_ids
    resp = client.post(
        "/api/products/",
        json={"name": "mit Brötchen", "price": 4.5, "category_id": cat_id, "group_id": 999999},
        headers=auth_headers,
    )
    assert resp.status_code == 404


def test_update_product_rejects_self_group_id(client, auth_headers, option_product_ids):
    _, base_id, _ = option_product_ids
    resp = client.put(f"/api/products/{base_id}", json={"group_id": base_id}, headers=auth_headers)
    assert resp.status_code == 400


def test_update_product_option_cannot_become_a_base_with_children(client, auth_headers, option_product_ids):
    cat_id, base_id, option_id = option_product_ids
    other_base = client.post(
        "/api/products/",
        json={"name": "Steak", "price": 12.0, "category_id": cat_id},
        headers=auth_headers,
    ).json()

    # base_id already has a child (option_id) — it can't itself become an option.
    resp = client.put(
        f"/api/products/{base_id}", json={"group_id": other_base["id"]}, headers=auth_headers
    )
    assert resp.status_code == 400


def test_delete_base_cascades_soft_delete_to_options(client, auth_headers, option_product_ids):
    _, base_id, option_id = option_product_ids

    resp = client.delete(f"/api/products/{base_id}", headers=auth_headers)
    assert resp.status_code == 204

    # The option must no longer appear in the normal listing (soft-deleted).
    admin = client.get("/api/products/admin", headers=auth_headers).json()
    all_ids = {p["id"] for cat in admin["categories"] for p in cat["products"]}
    assert base_id not in all_ids
    assert option_id not in all_ids


def test_update_product_category_id_requires_dest_permission(client, auth_headers, option_product_ids, product_id):
    source_cat_id, base_id, _ = option_product_ids
    # product_id's fixture creates its own separate category — use it as the destination.
    dest_category_id = _category_of(client, auth_headers, product_id)
    user_id, restricted_headers = _create_user(client, auth_headers, "restricted_mover")

    # Rights on the SOURCE category only — specifically isolates the
    # destination-side check, not just "no rights anywhere".
    _grant_edit_article(client, auth_headers, user_id, source_cat_id)
    resp = client.put(
        f"/api/products/{base_id}", json={"category_id": dest_category_id}, headers=restricted_headers
    )
    assert resp.status_code == 403

    # As admin (manager, always allowed): move succeeds and the response
    # reflects the *new* category_id — regression test for the previously
    # hardcoded-old-value response bug.
    resp = client.put(
        f"/api/products/{base_id}", json={"category_id": dest_category_id}, headers=auth_headers
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["category_id"] == dest_category_id


def test_update_product_category_id_cascades_to_options(client, auth_headers, option_product_ids, product_id):
    _, base_id, option_id = option_product_ids
    dest_category_id = _category_of(client, auth_headers, product_id)

    resp = client.put(
        f"/api/products/{base_id}", json={"category_id": dest_category_id}, headers=auth_headers
    )
    assert resp.status_code == 200, resp.text

    admin = client.get("/api/products/admin", headers=auth_headers).json()
    option_row = next(
        p for cat in admin["categories"] for p in cat["products"] if p["id"] == option_id
    )
    assert option_row["category_id"] == dest_category_id


def test_update_product_option_cannot_move_directly(client, auth_headers, option_product_ids, product_id):
    _, _, option_id = option_product_ids
    dest_category_id = _category_of(client, auth_headers, product_id)

    resp = client.put(
        f"/api/products/{option_id}", json={"category_id": dest_category_id}, headers=auth_headers
    )
    assert resp.status_code == 400


def test_admin_endpoint_includes_inactive_for_edit_only_user(client, auth_headers, product_id):
    cat_id = _category_of(client, auth_headers, product_id)

    # Deactivate the article as admin first.
    resp = client.patch(f"/api/products/{product_id}/active", json={"active": False}, headers=auth_headers)
    assert resp.status_code == 200

    user_id, edit_only_headers = _create_user(client, auth_headers, "edit_only_user")
    _grant_edit_article(client, auth_headers, user_id, cat_id)

    # Regular per-category listing hides it (show_inactive is keyed to
    # can_deactivate_article, which this user deliberately doesn't have).
    listing = client.get(
        "/api/products/", params={"category_id": cat_id}, headers=edit_only_headers
    ).json()
    assert product_id not in {p["id"] for p in listing}

    # /admin fixes that gap: any article-management right means full visibility.
    admin = client.get("/api/products/admin", headers=edit_only_headers).json()
    all_ids = {p["id"] for cat in admin["categories"] for p in cat["products"]}
    assert product_id in all_ids


def test_admin_endpoint_scoped_to_manageable_categories(client, auth_headers, option_product_ids):
    cat_id, base_id, _ = option_product_ids
    user_id, restricted_headers = _create_user(client, auth_headers, "no_article_rights")
    # Grant only can_book — no article-management flag at all.
    resp = client.put(
        f"/api/users/{user_id}/categories",
        json={"categories": [{"category_id": cat_id, "can_book": True}]},
        headers=auth_headers,
    )
    assert resp.status_code == 204

    admin = client.get("/api/products/admin", headers=restricted_headers).json()
    assert admin["categories"] == []


def _category_of(client, auth_headers, product_id):
    admin = client.get("/api/products/admin", headers=auth_headers).json()
    row = next(p for cat in admin["categories"] for p in cat["products"] if p["id"] == product_id)
    return row["category_id"]
