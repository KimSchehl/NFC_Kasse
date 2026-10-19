import json
import shutil
import sqlite3
from pathlib import Path

import pytest

import db_backup
from db_backup import BackupError, create_backup, restore, verify_backup


def _add_customer(path: Path, uid: str, balance: float) -> None:
    conn = sqlite3.connect(path)
    tenant_id = conn.execute("SELECT id FROM tenant LIMIT 1").fetchone()[0]
    conn.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (?, ?, ?)",
        (tenant_id, uid, balance),
    )
    conn.commit()
    conn.close()


def _customer_uids(path: Path) -> set[str]:
    conn = sqlite3.connect(path)
    try:
        return {r[0] for r in conn.execute("SELECT nfc_uid FROM customer")}
    finally:
        conn.close()


def test_backup_keeps_uncheckpointed_wal_writes(tmp_path, db):
    source = Path(db)
    open_conn = sqlite3.connect(source)
    tenant_id = open_conn.execute("SELECT id FROM tenant LIMIT 1").fetchone()[0]
    open_conn.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (?, 'WALONLY01', 12.5)",
        (tenant_id,),
    )
    open_conn.commit()

    backup = create_backup(source, tmp_path / "backups", prefix="manuell", label="Sommerfest")
    open_conn.close()

    assert "WALONLY01" in _customer_uids(backup)
    manifest = json.loads(backup.with_suffix(".json").read_text(encoding="utf-8"))
    assert manifest["label"] == "Sommerfest"
    assert manifest["schema_version"] == db_backup.SCHEMA_VERSION
    assert manifest["events"], "events should be listed in the manifest"


def test_verify_accepts_backup_and_rejects_garbage(tmp_path, db):
    backup = create_backup(Path(db), tmp_path / "backups", prefix="manuell")
    assert verify_backup(backup)["schema_version"] == db_backup.SCHEMA_VERSION

    garbage = tmp_path / "garbage.db"
    garbage.write_bytes(b"this is not sqlite" * 200)
    with pytest.raises(BackupError):
        verify_backup(garbage)


def test_restore_replaces_database_and_drops_stale_wal(tmp_path, db):
    source = Path(db)
    _add_customer(source, "KEEP0001", 3.0)
    backup = create_backup(source, tmp_path / "backups", prefix="manuell")

    live = tmp_path / "live" / "kasse.db"
    live.parent.mkdir()
    shutil.copyfile(source, live)
    _add_customer(live, "LIVEONLY1", 99.0)
    stale_wal = live.with_name(live.name + "-wal")
    stale_wal.write_bytes(b"stale wal junk")

    result = restore(backup, live, tmp_path / "backups", service_running=lambda: False)

    assert _customer_uids(live) == _customer_uids(backup)
    assert "LIVEONLY1" not in _customer_uids(live)
    assert not stale_wal.exists()
    assert result["safety_backup"].startswith("vor-wiederherstellung_")
    assert (tmp_path / "backups" / result["safety_backup"]).exists()


def test_restore_refuses_while_service_runs(tmp_path, db):
    backup = create_backup(Path(db), tmp_path / "backups", prefix="manuell")
    live = tmp_path / "kasse.db"
    shutil.copyfile(db, live)
    before = live.read_bytes()

    with pytest.raises(BackupError) as exc:
        restore(backup, live, tmp_path / "backups", service_running=lambda: True)

    assert exc.value.exit_code == db_backup.EXIT_SERVICE_RUNNING
    assert live.read_bytes() == before


def test_newer_schema_is_refused(tmp_path, db):
    backup = create_backup(Path(db), tmp_path / "backups", prefix="manuell")
    conn = sqlite3.connect(backup)
    conn.execute(f"PRAGMA user_version = {db_backup.SCHEMA_VERSION + 1}")
    conn.commit()
    conn.close()

    with pytest.raises(BackupError, match="neueren Programmversion"):
        verify_backup(backup)


def test_invalid_file_leaves_live_database_untouched(tmp_path, db):
    bogus = tmp_path / "bogus.db"
    bogus.write_bytes(b"not a database" * 100)
    live = tmp_path / "kasse.db"
    shutil.copyfile(db, live)
    before = live.read_bytes()

    with pytest.raises(BackupError):
        restore(bogus, live, tmp_path / "backups", service_running=lambda: False)

    assert live.read_bytes() == before


def test_cli_backup_list_and_busy_exit_code(tmp_path, db, capsys):
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    shutil.copyfile(db, data_dir / "kasse.db")

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
