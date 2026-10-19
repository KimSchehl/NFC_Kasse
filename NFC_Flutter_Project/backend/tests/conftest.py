import base64
import json
import os

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from starlette.testclient import TestClient

import licensing

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

# PAGER_ENABLED/LEADERBOARD_ENABLED now also require a valid signed license
# key for this installation (see licensing.py) — the plain *_LICENSE flag
# above is no longer sufficient by itself. Generate a disposable test
# keypair and sign valid keys for both features, entirely independent of
# the real production key in license_tool/. Swapping licensing.PUBLIC_KEY_B64
# is a plain module-attribute assignment, not a monkeypatch fixture — that's
# deliberate, since this has to happen at bare module scope (same ordering
# constraint as PAGER/LEADERBOARD above), where no test function (and
# therefore no fixture) is active yet.
_TEST_INSTALLATION_ID = "test-installation-id"
os.environ.setdefault("INSTALLATION_ID", _TEST_INSTALLATION_ID)

_test_private_key = Ed25519PrivateKey.generate()
_test_public_bytes = _test_private_key.public_key().public_bytes(
    encoding=serialization.Encoding.Raw, format=serialization.PublicFormat.Raw
)
licensing.PUBLIC_KEY_B64 = base64.urlsafe_b64encode(_test_public_bytes).rstrip(b"=").decode("ascii")


def _sign_test_license(feature: str) -> str:
    def b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

    payload = json.dumps(
        {"v": 1, "installation_id": _TEST_INSTALLATION_ID, "feature": feature},
        separators=(",", ":"),
    ).encode("utf-8")
    signature = _test_private_key.sign(payload)
    return f"{b64(payload)}.{b64(signature)}"


os.environ.setdefault("PAGER_LICENSE_KEY", _sign_test_license("pager"))
os.environ.setdefault("LEADERBOARD_LICENSE_KEY", _sign_test_license("leaderboard"))


def add_category(conn, name: str, event_id: int | None = None) -> int:
    """A category of tenant 1, switched on in `event_id` (default: the
    active event). Categories belong to the tenant since schema v3."""
    if event_id is None:
        event_id = conn.execute("SELECT id FROM event WHERE active = 1").fetchone()[0]
    cat_id = conn.execute("INSERT INTO category (tenant_id, name) VALUES (1, ?)", (name,)).lastrowid
    conn.execute("INSERT INTO event_category (event_id, category_id) VALUES (?, ?)", (event_id, cat_id))
    return cat_id


def add_product(conn, cat_id: int, name: str, price: float, event_id: int | None = None, **cols) -> int:
    """An article in `cat_id`; a base article is switched on in `event_id`
    (default: the active event), an option (group_id=...) follows its base."""
    names = ["category_id", "name", "price", *cols]
    p_id = conn.execute(
        f"INSERT INTO product ({', '.join(names)}) VALUES ({', '.join('?' * len(names))})",
        (cat_id, name, price, *cols.values()),
    ).lastrowid
    if cols.get("group_id") is None:
        if event_id is None:
            event_id = conn.execute("SELECT id FROM event WHERE active = 1").fetchone()[0]
        conn.execute("INSERT INTO event_product (event_id, product_id) VALUES (?, ?)", (event_id, p_id))
    return p_id


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
def legacy_v2_db(tmp_path, monkeypatch):
    """An isolated database in the frozen v2 schema (before Veranstalter
    owned categories and rights) — for the migration tests."""
    db_file = str(tmp_path / "legacy.db")

    import database
    from tests import legacy_init_db_v2 as legacy

    monkeypatch.setattr(database, "DB_PATH", db_file)
    monkeypatch.setattr(legacy, "DB_PATH", db_file)

    conn = legacy.init_db()
    legacy.seed_permissions(conn)
    legacy.seed_default_data(conn)
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
        cat_id = add_category(conn, "Test Kategorie")
        p_id = add_product(conn, cat_id, "Bier", 2.50)
    return p_id


@pytest.fixture
def pager_product_id(db):
    """Inserts a test category + requires_pager product, returns the product ID."""
    import database
    with database.get_db() as conn:
        cat_id = add_category(conn, "Test Kategorie")
        p_id = add_product(conn, cat_id, "Pizza Salami", 8.00, requires_pager=1)
    return p_id


@pytest.fixture
def pager_product_id_2(db, pager_product_id):
    """A second requires_pager product, in the same category as pager_product_id."""
    import database
    with database.get_db() as conn:
        cat_id = conn.execute(
            "SELECT category_id FROM product WHERE id=?", (pager_product_id,)
        ).fetchone()["category_id"]
        p_id = add_product(conn, cat_id, "Steak", 12.00, requires_pager=1)
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
        cat_id = add_category(conn, "Test Kategorie")
        base_id = add_product(conn, cat_id, "Currywurst", 5.00, stock=10, points=5)
        option_id = add_product(conn, cat_id, "Currywurst mit Pommes", 6.00, group_id=base_id)
    return cat_id, base_id, option_id


@pytest.fixture
def customer_with_balance(db):
    """Inserts a customer with 20.00 balance and returns their NFC UID."""
    import database
    uid = "TESTUID01"
    with database.get_db() as conn:
        tenant_id = conn.execute("SELECT id FROM tenant LIMIT 1").fetchone()["id"]
        conn.execute(
            # is_available=0: the chip is issued (with a balance), not a free one.
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (?, ?, ?, 0)",
            (tenant_id, uid, 20.00),
        )
    return uid
