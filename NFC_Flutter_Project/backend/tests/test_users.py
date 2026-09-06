def _create_user(client, auth_headers, username, password="password123"):
    resp = client.post(
        "/api/users/",
        json={"username": username, "password": password},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _login(client, username, password="password123"):
    resp = client.post("/api/auth/login", json={"username": username, "password": password})
    assert resp.status_code == 200, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def test_deactivate_then_reactivate_user(client, auth_headers):
    user_id = _create_user(client, auth_headers, "deactivate_me")

    resp = client.patch(f"/api/users/{user_id}/active", json={"active": False}, headers=auth_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["active"] is False

    # A deactivated user's own login must fail immediately.
    login = client.post("/api/auth/login", json={"username": "deactivate_me", "password": "password123"})
    assert login.status_code == 401

    resp = client.patch(f"/api/users/{user_id}/active", json={"active": True}, headers=auth_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["active"] is True

    login = client.post("/api/auth/login", json={"username": "deactivate_me", "password": "password123"})
    assert login.status_code == 200


def test_cannot_deactivate_own_account(client, auth_headers):
    me = client.get("/api/auth/me", headers=auth_headers).json()
    resp = client.patch(f"/api/users/{me['id']}/active", json={"active": False}, headers=auth_headers)
    assert resp.status_code == 400


def test_delete_user_excludes_from_list_and_frees_username(client, auth_headers):
    user_id = _create_user(client, auth_headers, "delete_me")

    resp = client.delete(f"/api/users/{user_id}", headers=auth_headers)
    assert resp.status_code == 204, resp.text

    listed_ids = [u["id"] for u in client.get("/api/users/", headers=auth_headers).json()]
    assert user_id not in listed_ids

    # Deleting renamed the row internally, freeing "delete_me" up again.
    new_id = _create_user(client, auth_headers, "delete_me")
    assert new_id != user_id


def test_cannot_delete_own_account(client, auth_headers):
    me = client.get("/api/auth/me", headers=auth_headers).json()
    resp = client.delete(f"/api/users/{me['id']}", headers=auth_headers)
    assert resp.status_code == 400


def test_cannot_deactivate_last_user_with_manage_permissions(client, auth_headers):
    # admin (auth_headers) already holds users.manage_permissions by default
    # seeding. Create a second user, also grant it users.manage_permissions
    # and users.deactivate, so there are two holders before the real test.
    deputy_id = _create_user(client, auth_headers, "deputy")
    perms_resp = client.get(f"/api/users/{deputy_id}/permissions", headers=auth_headers)
    assert perms_resp.status_code == 200
    put_resp = client.put(
        f"/api/users/{deputy_id}/permissions",
        json={"permission_ids": ["users.manage_permissions", "users.deactivate"]},
        headers=auth_headers,
    )
    assert put_resp.status_code == 204, put_resp.text
    deputy_headers = _login(client, "deputy")

    admin_id = client.get("/api/auth/me", headers=auth_headers).json()["id"]

    # Two holders (admin + deputy) -- deputy deactivating admin must fail
    # because admin is not the deputy's own account, but it WOULD leave
    # deputy as the only remaining holder, which is fine (still >= 1).
    resp = client.patch(f"/api/users/{admin_id}/active", json={"active": False}, headers=deputy_headers)
    assert resp.status_code == 200, resp.text

    # Reactivate admin -- admin's own token is unusable while its account is
    # inactive (get_current_user requires active=1), so deputy must do this,
    # not auth_headers. Only after admin is active again can auth_headers be
    # used to remove the deputy's own manage_permissions grant.
    client.patch(f"/api/users/{admin_id}/active", json={"active": True}, headers=deputy_headers)
    client.put(
        f"/api/users/{deputy_id}/permissions",
        json={"permission_ids": ["users.deactivate"]},
        headers=auth_headers,
    )

    # Now admin is the ONLY holder of users.manage_permissions -- deputy
    # (who still has users.deactivate) must be blocked from deactivating it.
    resp = client.patch(f"/api/users/{admin_id}/active", json={"active": False}, headers=deputy_headers)
    assert resp.status_code == 400
