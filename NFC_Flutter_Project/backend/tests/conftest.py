import os

# main.py registers the pager router conditionally at import time based on
# config.PAGER_ENABLED, which itself reads this env var at config.py's
# *first* import — so it must be set before any test triggers that import
# (via the `client` fixture below) for the pager router to exist in this
# test session at all. Setting it here, at conftest module load (which
# pytest always does before running any test), is the only place early
# enough. Harmless for non-pager tests: PAGER_ENABLED only adds a route and
# gates an `if` branch that's otherwise skipped when pager_number is omitted.
os.environ.setdefault("PAGER", "true")
# Same reasoning as PAGER above — points-resolution tests (booking through
# an article option) need LEADERBOARD_ENABLED=True, which is likewise frozen
# at config.py's first import.
os.environ.setdefault("LEADERBOARD", "true")

import pytest
from starlette.testclient import TestClient


@pytest.fixture
def db(tmp_path, monkeypatch):
    """Fresh isolated SQLite database for each test."""
    db_file = str(tmp_path / "test.db")

    import database
    import init_db as idb

    monkeypatch.setattr(database, "DB_PATH", db_file)
    monkeypatch.setattr(idb, "DB_PATH", db_file)

    conn = idb.init_db()
    idb.seed_permissions(conn)
    idb.seed_default_data(conn)
    conn.close()

    return db_file


@pytest.fixture
def client(db):
    from main import app
    return TestClient(app)


@pytest.fixture
def auth_headers(client):
    resp = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    assert resp.status_code == 200, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def product_id(db):
    """Inserts a test category + product into the DB and returns the product ID."""
    import database
    with database.get_db() as conn:
        event_id = conn.execute("SELECT id FROM event LIMIT 1").fetchone()["id"]
        cat_id = conn.execute(
            "INSERT INTO category (event_id, name) VALUES (?, ?)",
            (event_id, "Test Kategorie"),
        ).lastrowid
        p_id = conn.execute(
            "INSERT INTO product (category_id, name, price) VALUES (?, ?, ?)",
            (cat_id, "Bier", 2.50),
        ).lastrowid
    return p_id


@pytest.fixture
def pager_product_id(db):
    """Inserts a test category + requires_pager product, returns the product ID."""
    import database
    with database.get_db() as conn:
        event_id = conn.execute("SELECT id FROM event LIMIT 1").fetchone()["id"]
        cat_id = conn.execute(
            "INSERT INTO category (event_id, name) VALUES (?, ?)",
            (event_id, "Test Kategorie"),
        ).lastrowid
        p_id = conn.execute(
            "INSERT INTO product (category_id, name, price, requires_pager) VALUES (?, ?, ?, 1)",
            (cat_id, "Pizza Salami", 8.00),
        ).lastrowid
    return p_id


@pytest.fixture
def pager_product_id_2(db, pager_product_id):
    """A second requires_pager product, in the same category as pager_product_id."""
    import database
    with database.get_db() as conn:
        cat_id = conn.execute(
            "SELECT category_id FROM product WHERE id=?", (pager_product_id,)
        ).fetchone()["category_id"]
        p_id = conn.execute(
            "INSERT INTO product (category_id, name, price, requires_pager) VALUES (?, ?, ?, 1)",
            (cat_id, "Steak", 12.00),
        ).lastrowid
    return p_id


@pytest.fixture
def other_user_auth_headers(client, auth_headers):
    """Creates a second user (no special permissions) and logs them in."""
    resp = client.post(
        "/api/users/",
        json={"username": "other_operator", "password": "password123"},
        headers=auth_headers,
    )
    assert resp.status_code == 201, resp.text

    login = client.post("/api/auth/login", json={"username": "other_operator", "password": "password123"})
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def option_product_ids(db):
    """
    Base article "Currywurst" (stock=10, points=5) + one option
    "Currywurst mit Pommes" (group_id -> base, own price=6.00, no stock/
    points of its own) in the same category. Returns (cat_id, base_id, option_id).
    """
    import database
    with database.get_db() as conn:
        event_id = conn.execute("SELECT id FROM event LIMIT 1").fetchone()["id"]
        cat_id = conn.execute(
            "INSERT INTO category (event_id, name) VALUES (?, ?)",
            (event_id, "Test Kategorie"),
        ).lastrowid
        base_id = conn.execute(
            "INSERT INTO product (category_id, name, price, stock, points) VALUES (?, ?, ?, ?, ?)",
            (cat_id, "Currywurst", 5.00, 10, 5),
        ).lastrowid
        option_id = conn.execute(
            "INSERT INTO product (category_id, name, price, group_id) VALUES (?, ?, ?, ?)",
            (cat_id, "Currywurst mit Pommes", 6.00, base_id),
        ).lastrowid
    return cat_id, base_id, option_id


@pytest.fixture
def customer_with_balance(db):
    """Inserts a customer with 20.00 balance and returns their NFC UID."""
    import database
    uid = "TESTUID01"
    with database.get_db() as conn:
        tenant_id = conn.execute("SELECT id FROM tenant LIMIT 1").fetchone()["id"]
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (?, ?, ?)",
            (tenant_id, uid, 20.00),
        )
    return uid
