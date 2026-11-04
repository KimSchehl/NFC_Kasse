"""
delete_tool/purge.py: deleting a whole Veranstalter or a single ended Fest.
Data is created through the real API and admin CLI so every table a
running kasse fills is covered by the foreign key check at the end.
"""
import io
import json
import sys
from pathlib import Path

import pytest

import admin_cli
import database

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "delete_tool"))
import purge  # noqa: E402

from tests.conftest import add_category, add_product  # noqa: E402


def _cli(capsys, monkeypatch, data_dir, *argv, stdin=""):
    monkeypatch.setattr("sys.stdin", io.StringIO(stdin))
    code = admin_cli.main(list(argv), data_dir, db_path=Path(database.DB_PATH))
    out = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert code == 0, out
    return out


def _run(action):
    db = purge.connect(database.DB_PATH)
    try:
        db.execute("BEGIN EXCLUSIVE")
        try:
            action(db)
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
    finally:
        db.close()


def _count(sql, *args):
    with database.get_db() as conn:
        return conn.execute(sql, args).fetchone()[0]


@pytest.fixture
def kasse(client, auth_headers, db, tmp_path, capsys, monkeypatch):
    """Tenant "Lokal" with a fest full of activity (top-up, sales, a cancel,
    a Tagesabschluss), ended; plus an empty second Veranstalter "B"."""
    with database.get_db() as conn:
        cat = add_category(conn, "Getränke")
        beer = add_product(conn, cat, "Bier", 3.5)
        add_product(conn, cat, "Bier groß", 5.0, group_id=beer)
    fest_id = _count("SELECT id FROM event WHERE active = 1")
    assert client.post("/api/topup/", json={"nfc_uid": "CHIP1", "amount": 20}, headers=auth_headers).status_code == 201
    sale = client.post("/api/sales/", json={"nfc_uid": "CHIP1", "product_ids": [beer, beer]}, headers=auth_headers)
    assert sale.status_code in (200, 201), sale.text
    first = _count("SELECT MIN(id) FROM sale")
    assert client.post(f"/api/sales/{first}/cancel", headers=auth_headers).status_code == 200
    assert client.post("/api/stats/periods/close", json={"label": "Tag 2"}, headers=auth_headers).status_code == 201
    with database.get_db() as conn:
        sale_id = _count("SELECT MAX(id) FROM sale")
        customer = conn.execute("SELECT id FROM customer WHERE nfc_uid = 'CHIP1'").fetchone()[0]
        conn.execute("INSERT INTO pager_order (event_id, created_by, item_summary, pager_number) "
                     "VALUES (?, 1, 'Bier', 3)", (fest_id,))
        conn.execute("INSERT INTO print_job (event_id, sale_id, username, event_name, product_name, price) "
                     "VALUES (?, ?, 'admin', 'Fest', 'Bier', 3.5)", (fest_id, sale_id))
        conn.execute("INSERT INTO leaderboard_entry (event_id, customer_id, opt_in) VALUES (?, ?, 1)",
                     (fest_id, customer))
        request = conn.execute("INSERT INTO help_request (event_id, requester_id) VALUES (?, 1)",
                               (fest_id,)).lastrowid
        conn.execute("INSERT INTO help_response (request_id, responder_id, response) VALUES (?, 1, 'on_way')",
                     (request,))
        conn.execute("INSERT INTO user_setting (user_id, event_id, key, value) VALUES (1, ?, 'x', '1')",
                     (fest_id,))
        conn.execute("INSERT INTO user_preference_store (user_id, key, value) VALUES (1, 'layout.cat_1', '[]')")
    _cli(capsys, monkeypatch, tmp_path, "event-end")
    b = _cli(capsys, monkeypatch, tmp_path, "tenant-create", "--name", "B", "--admin-user", "chef",
             stdin="geheim123\n")["tenant"]
    return {"fest_id": fest_id, "tenant_a": 1, "tenant_b": b["id"]}


def test_deleting_a_fest_keeps_balances_and_master_data(kasse):
    balance = _count("SELECT balance FROM customer WHERE nfc_uid = 'CHIP1'")
    users, products = _count("SELECT COUNT(*) FROM user"), _count("SELECT COUNT(*) FROM product")
    assert _count("SELECT COUNT(*) FROM sale WHERE event_id = ?", kasse["fest_id"]) == 2

    _run(lambda db: purge.delete_fest(db, kasse["fest_id"]))

    assert _count("SELECT COUNT(*) FROM event WHERE id = ?", kasse["fest_id"]) == 0
    assert _count("SELECT COUNT(*) FROM sale") == 0
    assert _count("SELECT COUNT(*) FROM topup") == 0
    for table in ("pager_order", "print_job", "leaderboard_entry", "help_request", "help_response"):
        assert _count(f"SELECT COUNT(*) FROM {table}") == 0, table
    assert _count("SELECT balance FROM customer WHERE nfc_uid = 'CHIP1'") == balance
    assert _count("SELECT COUNT(*) FROM user") == users
    assert _count("SELECT COUNT(*) FROM product") == products


def test_running_fest_and_intern_are_protected(kasse, tmp_path, capsys, monkeypatch):
    intern = _count("SELECT id FROM event WHERE tenant_id = 1 AND is_intern = 1")
    with pytest.raises(purge.PurgeError, match="Intern"):
        _run(lambda db: purge.delete_fest(db, intern))
    _cli(capsys, monkeypatch, tmp_path, "event-start", "--name", "Neues Fest", "--deposit", "2")
    running = _count("SELECT id FROM event WHERE active = 1 AND tenant_id = 1")
    with pytest.raises(purge.PurgeError, match="läuft gerade"):
        _run(lambda db: purge.delete_fest(db, running))


def test_deleting_a_veranstalter_removes_everything_of_it(kasse, tmp_path, capsys, monkeypatch):
    _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(kasse["tenant_b"]))

    _run(lambda db: purge.delete_tenant(db, kasse["tenant_a"]))

    assert _count("SELECT COUNT(*) FROM tenant") == 1
    for table in ("event", "user", "category", "customer", "role_template"):
        assert _count(f"SELECT COUNT(*) FROM {table} WHERE tenant_id = 1") == 0, table
    for table in ("sale", "topup", "product", "user_permission", "user_category_access", "stats_period",
                  "refresh_token"):
        remaining = _count(f"SELECT COUNT(*) FROM {table}")
        if table in ("user_permission", "stats_period"):
            assert remaining > 0  # B's admin rights and Intern period stay
        else:
            assert remaining == 0, table
    assert _count("SELECT COUNT(*) FROM user WHERE tenant_id = ?", kasse["tenant_b"]) == 1


def test_active_and_last_veranstalter_are_protected(kasse):
    with pytest.raises(purge.PurgeError, match="aktive Veranstalter"):
        _run(lambda db: purge.delete_tenant(db, kasse["tenant_a"]))
    _run(lambda db: purge.delete_tenant(db, kasse["tenant_b"]))
    with database.get_db(exclusive=True) as conn:
        conn.execute("UPDATE tenant SET active = 0")
    with pytest.raises(purge.PurgeError, match="letzte"):
        _run(lambda db: purge.delete_tenant(db, kasse["tenant_a"]))


def test_summaries_show_open_balance(kasse):
    db = purge.connect(database.DB_PATH)
    try:
        a = purge.tenant_summary(db, kasse["tenant_a"])
        assert a["active"] and a["fests"] == 1 and a["open_balance_chips"] == 1
        assert a["open_balance"] == _count("SELECT balance FROM customer WHERE nfc_uid = 'CHIP1'")
        [fest] = purge.list_fests(db, kasse["tenant_a"])
        assert fest["sales"] == 2 and fest["topups"] == 1 and not fest["active"]
    finally:
        db.close()
