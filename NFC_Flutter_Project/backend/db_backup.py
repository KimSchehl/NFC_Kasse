"""
Sicherung und Wiederherstellung der Datenbank.

create_backup() läuft auch während der Dienst läuft: Die SQLite-Backup-API
nimmt die WAL-Datei mit, ein Datei-Kopieren würde Buchungen übersehen.
restore() ersetzt kasse.db und braucht deshalb einen gestoppten Dienst.

main() ist der Befehlszeilen-Einstieg von NfcKasseBackend.exe, den das
Admin-Tool aufruft. Ausgabe ist immer eine einzige JSON-Zeile.
"""

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Callable

SCHEMA_VERSION = 3
SERVICE_NAME = "NfcKasseBackend"
REQUIRED_TABLES = ("event", "customer", "sale")
EXIT_OK = 0
EXIT_ERROR = 1
EXIT_SERVICE_RUNNING = 3


class BackupError(Exception):
    def __init__(self, message: str, exit_code: int = EXIT_ERROR):
        super().__init__(message)
        self.exit_code = exit_code


def _safe_label(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]+", "-", label).strip("-")[:40] or "label"


def _readonly(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)


def _describe(path: Path, kind: str, label: str | None) -> dict:
    conn = _readonly(path)
    try:
        def count(table: str):
            try:
                return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            except sqlite3.OperationalError:
                return None

        try:
            events = [
                {"name": name, "active": bool(active)}
                for name, active in conn.execute("SELECT name, active FROM event ORDER BY id")
            ]
        except sqlite3.OperationalError:
            events = []

        return {
            "kind": kind,
            "label": label,
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "file": path.name,
            "size_bytes": path.stat().st_size,
            "schema_version": conn.execute("PRAGMA user_version").fetchone()[0],
            "customers": count("customer"),
            "sales": count("sale"),
            "events": events,
        }
    finally:
        conn.close()


def create_backup(src_db: Path, dest_dir: Path, prefix: str, label: str | None = None) -> Path:
    if not src_db.exists():
        raise BackupError(f"Datenbank nicht gefunden: {src_db}")
    dest_dir.mkdir(parents=True, exist_ok=True)

    name = f"{prefix}_{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if label:
        name += "_" + _safe_label(label)
    final = dest_dir / f"{name}.db"
    tmp = dest_dir / f"{name}.db.tmp"

    src = sqlite3.connect(src_db)
    dst = sqlite3.connect(tmp)
    try:
        src.backup(dst)
        dst.execute("PRAGMA journal_mode=DELETE")
    finally:
        dst.close()
        src.close()
    os.replace(tmp, final)

    manifest = _describe(final, kind=prefix, label=label)
    final.with_suffix(".json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return final


def prune(backups_dir: Path, prefix: str, keep: int) -> None:
    files = sorted(
        backups_dir.glob(f"{prefix}_*.db"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    for stale in files[keep:]:
        stale.unlink(missing_ok=True)
        stale.with_suffix(".json").unlink(missing_ok=True)


def verify_backup(path: Path) -> dict:
    if not path.exists():
        raise BackupError(f"Datei nicht gefunden: {path}")
    try:
        conn = _readonly(path)
        try:
            integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
            if integrity != "ok":
                raise BackupError(f"Die Datei ist beschädigt: {integrity}")
            tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            missing = [t for t in REQUIRED_TABLES if t not in tables]
            if missing:
                raise BackupError(
                    "Keine NFC-Kasse-Datenbank, fehlende Tabellen: " + ", ".join(missing)
                )
            version = conn.execute("PRAGMA user_version").fetchone()[0]
        finally:
            conn.close()
    except sqlite3.DatabaseError as exc:
        raise BackupError(f"Keine gültige NFC-Kasse-Sicherung: {exc}") from exc

    if version > SCHEMA_VERSION:
        raise BackupError(
            f"Diese Sicherung stammt von einer neueren Programmversion "
            f"(Schema {version}, unterstützt bis {SCHEMA_VERSION})."
        )
    return _describe(path, kind="pruefung", label=None)


def _put(src: Path, db: Path) -> None:
    tmp = db.with_name(db.name + ".restore")
    shutil.copyfile(src, tmp)
    for suffix in ("-wal", "-shm"):
        db.with_name(db.name + suffix).unlink(missing_ok=True)
    os.replace(tmp, db)


def restore(
    backup: Path,
    db: Path,
    backups_dir: Path,
    service_running: Callable[[], bool],
) -> dict:
    if service_running():
        raise BackupError(
            "Der Dienst läuft noch. Bitte zuerst stoppen.", exit_code=EXIT_SERVICE_RUNNING
        )
    info = verify_backup(backup)

    safety = create_backup(db, backups_dir, prefix="vor-wiederherstellung") if db.exists() else None
    try:
        _put(backup, db)
        verify_backup(db)
    except Exception as exc:
        if safety is not None:
            _put(safety, db)
        raise BackupError(
            f"Wiederherstellung fehlgeschlagen, der vorherige Stand wurde zurückgespielt: {exc}"
        ) from exc

    return {
        "restored_from": backup.name,
        "safety_backup": safety.name if safety else None,
        "backup": info,
    }


def _service_running() -> bool:
    try:
        out = subprocess.run(
            ["sc", "query", SERVICE_NAME], capture_output=True, text=True
        ).stdout
    except OSError:
        return False
    return "RUNNING" in out


def _emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def _list(backups_dir: Path) -> list[dict]:
    if not backups_dir.exists():
        return []
    entries = []
    for f in sorted(backups_dir.glob("*.db"), key=lambda p: p.stat().st_mtime, reverse=True):
        sidecar = f.with_suffix(".json")
        manifest = json.loads(sidecar.read_text(encoding="utf-8")) if sidecar.exists() else {}
        manifest["file"] = f.name
        entries.append(manifest)
    return entries


def main(
    argv: list[str],
    data_dir: Path,
    service_running: Callable[[], bool] = _service_running,
) -> int:
    parser = argparse.ArgumentParser(prog="NfcKasseBackend")
    sub = parser.add_subparsers(dest="command", required=True)
    backup_cmd = sub.add_parser("backup")
    backup_cmd.add_argument("--label", default=None)
    restore_cmd = sub.add_parser("restore")
    restore_cmd.add_argument("file")
    verify_cmd = sub.add_parser("verify")
    verify_cmd.add_argument("file")
    sub.add_parser("list")
    args = parser.parse_args(argv)

    db = data_dir / "kasse.db"
    backups_dir = data_dir / "backups"
    try:
        if args.command == "backup":
            path = create_backup(db, backups_dir, prefix="manuell", label=args.label)
            _emit({"ok": True, "file": path.name})
        elif args.command == "verify":
            _emit({"ok": True, "backup": verify_backup(Path(args.file))})
        elif args.command == "restore":
            result = restore(Path(args.file), db, backups_dir, service_running)
            _emit({"ok": True, **result})
        else:
            _emit({"ok": True, "backups": _list(backups_dir)})
    except BackupError as exc:
        _emit({"ok": False, "error": str(exc)})
        return exc.exit_code
    return EXIT_OK
