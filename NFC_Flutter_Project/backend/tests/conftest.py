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
