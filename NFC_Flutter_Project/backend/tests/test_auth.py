from dependencies import (
    _decode_access_token,
    create_access_token,
    hash_password,
    verify_password,
)


# ---------------------------------------------------------------------------
# Pure unit tests — no DB or HTTP needed
# ---------------------------------------------------------------------------

def test_password_hash_and_verify():
    hashed = hash_password("mysecret")
    assert verify_password("mysecret", hashed)
    assert not verify_password("wrong", hashed)


def test_access_token_round_trip():
    token = create_access_token(user_id=42)
    payload = _decode_access_token(token)
    assert payload["sub"] == "42"
    assert payload["type"] == "access"


# ---------------------------------------------------------------------------
# HTTP tests
# ---------------------------------------------------------------------------

def test_login_success(client):
    resp = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


def test_login_wrong_password(client):
    resp = client.post("/api/auth/login", json={"username": "admin", "password": "wrong"})
    assert resp.status_code == 401


def test_login_unknown_user(client):
    resp = client.post("/api/auth/login", json={"username": "ghost", "password": "pass"})
    assert resp.status_code == 401


def test_me_returns_user_info(client, auth_headers):
    resp = client.get("/api/auth/me", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["username"] == "admin"
    assert "sales.booking.create" in data["permissions"]


def test_me_without_token_returns_401(client):
    resp = client.get("/api/auth/me")
    assert resp.status_code == 401


def test_refresh_token_works(client):
    login = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    refresh_token = login.json()["refresh_token"]

    resp = client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    assert "access_token" in resp.json()


def test_refresh_token_cannot_be_reused(client):
    login = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    refresh_token = login.json()["refresh_token"]

    client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
    resp = client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 401
