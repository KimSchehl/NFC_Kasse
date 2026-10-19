"""
Veranstalter (tenant): several fully separate kassen on one server, used one
after another. Managed from the admin tool via admin_cli.py.
"""
import io
import json
from pathlib import Path

import admin_cli
import database


def _cli(capsys, monkeypatch, data_dir, *argv, stdin=""):
    monkeypatch.setattr("sys.stdin", io.StringIO(stdin))
    code = admin_cli.main(list(argv), data_dir, db_path=Path(database.DB_PATH))
    out = capsys.readouterr().out.strip().splitlines()[-1]
    return code, json.loads(out)


def _create_b(capsys, monkeypatch, tmp_path, user="admin"):
    code, out = _cli(
        capsys, monkeypatch, tmp_path, "tenant-create", "--name", "Weingut B", "--admin-user", user,
        stdin="geheim123\n",
    )
    assert code == 0, out
    return out["tenant"]


def _end_fest(capsys, monkeypatch, tmp_path):
    assert _cli(capsys, monkeypatch, tmp_path, "event-end")[0] == 0


def _login(client, user="admin", password="admin"):
    return client.post("/api/auth/login", json={"username": user, "password": password})


def test_a_new_veranstalter_starts_empty_in_intern(db, tmp_path, capsys, monkeypatch):
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    assert tenant["active"] is False and tenant["running"] == "Intern"
    assert tenant["users"] == 1 and tenant["categories"] == 0 and tenant["fests"] == 0
    with database.get_db() as conn:
        assert conn.execute(
            "SELECT COUNT(*) FROM customer WHERE tenant_id = ? AND nfc_uid = 'BAR'", (tenant["id"],)
        ).fetchone()[0] == 1
        perms = {r[0] for r in conn.execute(
            "SELECT permission_id FROM user_permission up JOIN user u ON u.id = up.user_id WHERE u.tenant_id = ?",
            (tenant["id"],),
        )}
    assert "users.manage_permissions" in perms and "kiosk.access" not in perms

    code, out = _cli(capsys, monkeypatch, tmp_path, "tenants")
    assert code == 0
    assert [t["name"] for t in out["tenants"]] == ["Lokal", "Weingut B"]
    assert out["active_tenant_id"] == out["tenants"][0]["id"]


def test_create_checks_name_and_password(db, tmp_path, capsys, monkeypatch):
    code, out = _cli(capsys, monkeypatch, tmp_path, "tenant-create", "--name", "Lokal", "--admin-user", "x",
                     stdin="geheim123\n")
    assert code == 1 and "gibt es schon" in out["error"]
    code, out = _cli(capsys, monkeypatch, tmp_path, "tenant-create", "--name", "Neu", "--admin-user", "x",
                     stdin="kurz\n")
    assert code == 1 and "6 Zeichen" in out["error"]


def test_switching_needs_the_fest_to_be_ended(db, tmp_path, capsys, monkeypatch):
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    code, out = _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(tenant["id"]))
    assert code == 1 and "Fest beenden" in out["error"]


def test_switching_logs_every_device_out_and_separates_the_kassen(client, db, tmp_path, capsys, monkeypatch):
    old = _login(client).json()
    old_headers = {"Authorization": f"Bearer {old['access_token']}"}
    assert client.post("/api/products/categories", json={"name": "Bar A"}, headers=old_headers).status_code == 201

    tenant = _create_b(capsys, monkeypatch, tmp_path)  # its admin is also called "admin"
    _end_fest(capsys, monkeypatch, tmp_path)
    code, out = _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(tenant["id"]))
    assert code == 0, out
    assert out["safety_backup"].startswith("vor-veranstalterwechsel_")

    # Logged out at once: the access token is refused, the refresh token revoked.
    assert client.get("/api/auth/me", headers=old_headers).status_code == 401
    assert client.post("/api/auth/refresh", json={"refresh_token": old["refresh_token"]}).status_code == 401
    # Same username, but only the active Veranstalter's account logs in.
    assert _login(client, "admin", "admin").status_code == 401
    new = _login(client, "admin", "geheim123")
    assert new.status_code == 200, new.text
    headers = {"Authorization": f"Bearer {new.json()['access_token']}"}

    me = client.get("/api/auth/me", headers=headers).json()
    assert me["event_is_intern"] is True and me["categories"] == []
    every = client.get("/api/products/categories?all=true", headers=headers).json()
    assert every == []  # Veranstalter A's "Bar A" is not visible
    assert client.get("/api/users/", headers=headers).json()[0]["username"] == "admin"
    assert len(client.get("/api/users/", headers=headers).json()) == 1


def test_chips_have_separate_balances_per_veranstalter(client, db, tmp_path, capsys, monkeypatch):
    with database.get_db() as conn:
        conn.execute("INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (1, 'CHIP1', 12.0, 0)")
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    _end_fest(capsys, monkeypatch, tmp_path)
    assert _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(tenant["id"]))[0] == 0

    headers = {"Authorization": f"Bearer {_login(client, 'admin', 'geheim123').json()['access_token']}"}
    balance = client.get("/api/sales/balance/CHIP1", headers=headers).json()
    assert balance["balance"] == 0.0 and balance["is_new_customer"] is True


def test_fest_commands_act_on_the_active_veranstalter(db, tmp_path, capsys, monkeypatch):
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    _end_fest(capsys, monkeypatch, tmp_path)
    assert _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(tenant["id"]))[0] == 0
    code, out = _cli(capsys, monkeypatch, tmp_path, "event-start", "--name", "Weinfest B", "--deposit", "2")
    assert code == 0, out
    with database.get_db() as conn:
        assert conn.execute("SELECT tenant_id FROM event WHERE id = ?", (out["event"]["id"],)).fetchone()[0] == tenant["id"]
        # Veranstalter A still runs its own Intern, untouched.
        assert conn.execute("SELECT is_intern FROM event WHERE tenant_id = 1 AND active = 1").fetchone()[0] == 1
    overview = _cli(capsys, monkeypatch, tmp_path, "events")[1]
    assert {e["name"] for e in overview["events"]} == {"Intern", "Weinfest B"}


def test_health_reports_the_active_veranstalters_event(client, db, tmp_path, capsys, monkeypatch):
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    _end_fest(capsys, monkeypatch, tmp_path)
    assert _cli(capsys, monkeypatch, tmp_path, "tenant-activate", str(tenant["id"]))[0] == 0
    with database.get_db() as conn:
        expected = conn.execute("SELECT id FROM event WHERE tenant_id = ? AND active = 1", (tenant["id"],)).fetchone()[0]
    assert client.get("/health").json()["active_events"] == [expected]


def test_rename(db, tmp_path, capsys, monkeypatch):
    tenant = _create_b(capsys, monkeypatch, tmp_path)
    code, out = _cli(capsys, monkeypatch, tmp_path, "tenant-rename", str(tenant["id"]), "--name", "Weingut Bauer")
    assert code == 0 and out["tenant"]["name"] == "Weingut Bauer"
