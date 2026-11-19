import json

import pytest

import database
import db_backup
import schema
from db_backup import BackupError, create_backup, restore, verify_backup


def _add_customer(uid: str, balance: float) -> None:
    with database.get_db() as conn:
        conn.execute("INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES ((SELECT id FROM tenant ORDER BY id LIMIT 1), ?, ?)", (uid, balance))


def _customer_uids() -> set[str]:
    with database.get_db() as conn:
        return {r[0] for r in conn.execute("SELECT nfc_uid FROM customer")}


def test_backup_writes_dump_and_manifest(tmp_path, db):
    _add_customer("CHIP0001", 12.5)

    backup = create_backup(tmp_path / "backups", prefix="manuell", label="Sommerfest")

    assert backup.suffix == ".dump" and backup.name.startswith("manuell_")
    manifest = json.loads(backup.with_suffix(".json").read_text(encoding="utf-8"))
    assert manifest["label"] == "Sommerfest"
    assert manifest["schema_version"] == schema.head()
    assert manifest["customers"] == 2  # BAR chip + CHIP0001
    assert manifest["events"], "events should be listed in the manifest"


def test_verify_accepts_backup_and_rejects_garbage(tmp_path, db):
    backup = create_backup(tmp_path / "backups", prefix="manuell")
    assert verify_backup(backup)["schema_version"] == schema.head()

    garbage = tmp_path / "garbage.dump"
    garbage.write_bytes(b"this is not a dump" * 200)
    with pytest.raises(BackupError):
        verify_backup(garbage)


def test_restore_replaces_database(tmp_path, db):
    _add_customer("KEEP0001", 3.0)
    backup = create_backup(tmp_path / "backups", prefix="manuell")
    _add_customer("LIVEONLY1", 99.0)

    result = restore(backup, tmp_path / "backups", service_running=lambda: False)

    uids = _customer_uids()
    assert "KEEP0001" in uids and "LIVEONLY1" not in uids
    assert result["safety_backup"].startswith("vor-wiederherstellung_")
    assert (tmp_path / "backups" / result["safety_backup"]).exists()
    with database.get_db() as conn:
        assert schema.current(conn) == schema.head()


def test_restore_refuses_while_service_runs(tmp_path, db):
    backup = create_backup(tmp_path / "backups", prefix="manuell")
    _add_customer("LIVE0001", 1.0)

    with pytest.raises(BackupError) as exc:
        restore(backup, tmp_path / "backups", service_running=lambda: True)

    assert exc.value.exit_code == db_backup.EXIT_SERVICE_RUNNING
    assert "LIVE0001" in _customer_uids()


def test_newer_schema_is_refused(tmp_path, db):
    backup = create_backup(tmp_path / "backups", prefix="manuell")
    sidecar = backup.with_suffix(".json")
    manifest = json.loads(sidecar.read_text(encoding="utf-8"))
    manifest["schema_version"] = "9999_from_the_future"
    sidecar.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(BackupError, match="neueren Programmversion"):
        verify_backup(backup)


def test_invalid_file_leaves_live_database_untouched(tmp_path, db):
    _add_customer("LIVE0001", 1.0)
    bogus = tmp_path / "bogus.dump"
    bogus.write_bytes(b"not a database" * 100)

    with pytest.raises(BackupError):
        restore(bogus, tmp_path / "backups", service_running=lambda: False)

    assert "LIVE0001" in _customer_uids()


def test_cli_backup_list_and_busy_exit_code(tmp_path, db, capsys):
    data_dir = tmp_path / "data"
    data_dir.mkdir()

    assert db_backup.main(["backup", "--label", "Test"], data_dir, service_running=lambda: False) == 0
    created = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert created["ok"] is True
    assert created["file"].startswith("manuell_")

    assert db_backup.main(["list"], data_dir, service_running=lambda: False) == 0
    listed = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert [b["file"] for b in listed["backups"]] == [created["file"]]

    code = db_backup.main(
        ["restore", str(data_dir / "backups" / created["file"])],
        data_dir,
        service_running=lambda: True,
    )
    assert code == db_backup.EXIT_SERVICE_RUNNING
    failed = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert failed["ok"] is False
