"""
Sicherung und Wiederherstellung der Datenbank (PostgreSQL, pg_dump/pg_restore).

Eine Sicherung ist eine pg_dump-Datei (*.dump, Custom-Format) plus eine
gleichnamige *.json mit Zählern für die Anzeige im Admin-Tool.
create_backup() läuft auch während der Dienst läuft (pg_dump liest einen
konsistenten Stand). restore() ersetzt den kompletten Inhalt und braucht
deshalb einen gestoppten Dienst; danach wird das Schema auf den neuesten
Stand gebracht, ältere Sicherungen lassen sich also einspielen.

main() ist der Befehlszeilen-Einstieg von NfcKasseBackend.exe, den das
Admin-Tool aufruft. Ausgabe ist immer eine einzige JSON-Zeile.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Callable

import database
import schema

SERVICE_NAME = "NfcKasseBackend"
SUFFIX = ".dump"
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


def _pg_tool(name: str) -> str:
    """pg_dump/pg_restore: PG_BIN (set by the installer), PATH, or a standard install."""
    exe = name + (".exe" if os.name == "nt" else "")
    candidates = []
    if os.environ.get("PG_BIN"):
        candidates.append(Path(os.environ["PG_BIN"]) / exe)
    found = shutil.which(name)
    if found:
        candidates.append(Path(found))
    candidates += [Path(p) for p in sorted(glob.glob(rf"C:\Program Files\PostgreSQL\*\bin\{exe}"), reverse=True)]
    for c in candidates:
        if c.exists():
            return str(c)
    raise BackupError(f"{name} nicht gefunden (PostgreSQL-Programme fehlen, PG_BIN prüfen).")


def _run(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise BackupError(result.stderr.strip() or f"{Path(args[0]).name} fehlgeschlagen")
    return result.stdout


def _describe(kind: str, label: str | None, path: Path) -> dict:
    with database.get_db() as db:
        def count(table: str) -> int:
            return db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]

        events = [
            {"name": r["name"], "active": bool(r["active"])}
            for r in db.execute("SELECT name, active FROM event ORDER BY id")
        ]
        return {
            "kind": kind,
            "label": label,
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "file": path.name,
            "size_bytes": path.stat().st_size,
            "schema_version": schema.current(db),
            "customers": count("customer"),
            "sales": count("sale"),
            "events": events,
        }


def create_backup(dest_dir: Path, prefix: str, label: str | None = None) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    name = f"{prefix}_{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if label:
        name += "_" + _safe_label(label)
    final = dest_dir / f"{name}{SUFFIX}"
    tmp = dest_dir / f"{name}{SUFFIX}.tmp"
    try:
        _run([_pg_tool("pg_dump"), "--format=custom", "--no-owner", f"--file={tmp}", f"--dbname={database.DATABASE_URL}"])
        os.replace(tmp, final)
    finally:
        tmp.unlink(missing_ok=True)

    manifest = _describe(prefix, label, final)
    final.with_suffix(".json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return final


def prune(backups_dir: Path, prefix: str, keep: int) -> None:
    files = sorted(backups_dir.glob(f"{prefix}_*{SUFFIX}"), key=lambda p: p.stat().st_mtime, reverse=True)
    for stale in files[keep:]:
        stale.unlink(missing_ok=True)
        stale.with_suffix(".json").unlink(missing_ok=True)


def verify_backup(path: Path) -> dict:
    if not path.exists():
        raise BackupError(f"Datei nicht gefunden: {path}")
    try:
        listing = _run([_pg_tool("pg_restore"), "--list", str(path)])
    except BackupError as exc:
        raise BackupError(f"Keine gültige NFC-Kasse-Sicherung: {exc}") from exc
    missing = [t for t in REQUIRED_TABLES if not re.search(rf"TABLE public {t} ", listing)]
    if missing:
        raise BackupError("Keine NFC-Kasse-Datenbank, fehlende Tabellen: " + ", ".join(missing))

    sidecar = path.with_suffix(".json")
    info = json.loads(sidecar.read_text(encoding="utf-8")) if sidecar.exists() else {}
    revision = info.get("schema_version")
    if revision and not schema.known(revision):
        raise BackupError(
            f"Diese Sicherung stammt von einer neueren Programmversion (Schema {revision})."
        )
    info.update(kind="pruefung", file=path.name, size_bytes=path.stat().st_size)
    return info


def _put(backup: Path) -> None:
    """Replaces the whole database content with the backup."""
    with database.get_db() as db:
        db.execute("DROP SCHEMA public CASCADE")
        db.execute("CREATE SCHEMA public")
    _run([_pg_tool("pg_restore"), "--no-owner", "--single-transaction", f"--dbname={database.DATABASE_URL}", str(backup)])


def restore(backup: Path, backups_dir: Path, service_running: Callable[[], bool]) -> dict:
    if service_running():
        raise BackupError("Der Dienst läuft noch. Bitte zuerst stoppen.", exit_code=EXIT_SERVICE_RUNNING)
    info = verify_backup(backup)

    safety = create_backup(backups_dir, prefix="vor-wiederherstellung")
    try:
        _put(backup)
        schema.upgrade()
    except Exception as exc:
        _put(safety)
        raise BackupError(
            f"Wiederherstellung fehlgeschlagen, der vorherige Stand wurde zurückgespielt: {exc}"
        ) from exc
    finally:
        database.close_pool()

    return {"restored_from": backup.name, "safety_backup": safety.name, "backup": info}


def _service_running() -> bool:
    try:
        out = subprocess.run(["sc", "query", SERVICE_NAME], capture_output=True, text=True).stdout
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
    for f in sorted(backups_dir.glob(f"*{SUFFIX}"), key=lambda p: p.stat().st_mtime, reverse=True):
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

    database.use_config(data_dir)
    backups_dir = data_dir / "backups"
    try:
        if args.command == "backup":
            path = create_backup(backups_dir, prefix="manuell", label=args.label)
            _emit({"ok": True, "file": path.name})
        elif args.command == "verify":
            _emit({"ok": True, "backup": verify_backup(Path(args.file))})
        elif args.command == "restore":
            result = restore(Path(args.file), backups_dir, service_running)
            _emit({"ok": True, **result})
        else:
            _emit({"ok": True, "backups": _list(backups_dir)})
    except BackupError as exc:
        _emit({"ok": False, "error": str(exc)})
        return exc.exit_code
    except database.Error as exc:
        _emit({"ok": False, "error": f"Datenbankfehler: {exc}"})
        return EXIT_ERROR
    return EXIT_OK
