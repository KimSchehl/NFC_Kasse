"""
Befehle für den Bereich „Feste“ im Admin-Tool — gleiches Muster wie die
Sicherungs-Befehle in db_backup.py: NfcKasseBackend.exe <befehl>, Ausgabe ist
immer eine einzige JSON-Zeile mit "ok": true/false.

    events
    event-start --name NAME [--date JJJJ-MM-TT] [--deposit BETRAG]
                [--reset-stock | --keep-stock] [--categories ID,ID,...]
                [--source-event ID | --preset DATEI [--no-articles]
                 [--bon-layout] [--printer] [--bon-text]]
    event-update [--name NAME] [--deposit BETRAG]   (laufendes Fest, sofort wirksam)
    tenants
    tenant-create --name NAME --admin-user BENUTZER   (Passwort als eine Zeile auf stdin)
    tenant-activate ID
    tenant-rename ID --name NAME
    license-check [--kasse KEY] [--pager KEY] [--leaderboard KEY]   (ohne Angabe: Werte aus config.env)

Alle Fest-Befehle wirken auf den aktiven Veranstalter (tenants.py).
    event-end
    preset-export EVENT_ID DATEI
    csv-export EVENT_ID DATEI [--period ID]

Läuft auch bei laufendem Dienst: Schreibzugriffe gehen über
get_db(exclusive=True), und der Dienst liest das aktive Event bei jeder
Anfrage neu (dependencies.get_active_event) — ein Festwechsel gilt also ab
der nächsten Buchung. Kein Login: Wer das Admin-Tool auf dem Server bedienen
kann, steuert ohnehin schon Dienst, config.env und alle Sicherungen.
"""

import argparse
import sys
import sqlite3
from pathlib import Path

import database
import db_backup
import event_lifecycle
import tenants
from event_lifecycle import EventError
from schemas import EventPreset

COMMANDS = (
    "events", "event-start", "event-update", "event-end", "preset-export", "csv-export",
    "tenants", "tenant-create", "tenant-activate", "tenant-rename",
    "license-check",
)

# feature -> config.env key of its licence
LICENSE_KEYS = {"kasse": "LICENSE_KEY", "pager": "PAGER_LICENSE_KEY", "leaderboard": "LEADERBOARD_LICENSE_KEY"}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="NfcKasseBackend")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("events")

    start = sub.add_parser("event-start")
    start.add_argument("--name", required=True)
    start.add_argument("--date", default=None)
    start.add_argument("--deposit", type=float, required=True)
    # Bestand gehört dem Artikel. Ohne Angabe wird er zurückgesetzt — so hat
    # sich event-start vor v3 verhalten (Admin-Tool ohne --reset-stock).
    stock_opt = start.add_mutually_exclusive_group()
    stock_opt.add_argument("--reset-stock", action="store_true")
    stock_opt.add_argument("--keep-stock", action="store_true")
    start.add_argument("--categories", default=None, help="Kommagetrennte Kategorie-IDs")
    source = start.add_mutually_exclusive_group()
    source.add_argument("--source-event", type=int, default=None)
    source.add_argument("--preset", default=None)
    start.add_argument("--no-articles", action="store_true")
    start.add_argument("--bon-layout", action="store_true")
    start.add_argument("--printer", action="store_true")
    start.add_argument("--bon-text", action="store_true")

    update = sub.add_parser("event-update")
    update.add_argument("--name", default=None)
    update.add_argument("--deposit", type=float, default=None)

    sub.add_parser("event-end")

    lic = sub.add_parser("license-check")
    for feature in LICENSE_KEYS:
        lic.add_argument(f"--{feature}", default=None)

    sub.add_parser("tenants")
    create = sub.add_parser("tenant-create")
    create.add_argument("--name", required=True)
    create.add_argument("--admin-user", required=True)
    activate = sub.add_parser("tenant-activate")
    activate.add_argument("tenant_id", type=int)
    rename = sub.add_parser("tenant-rename")
    rename.add_argument("tenant_id", type=int)
    rename.add_argument("--name", required=True)

    export = sub.add_parser("preset-export")
    export.add_argument("event_id", type=int)
    export.add_argument("file")

    csv_cmd = sub.add_parser("csv-export")
    csv_cmd.add_argument("event_id", type=int)
    csv_cmd.add_argument("file")
    csv_cmd.add_argument("--period", type=int, default=None)
    return parser


def _load_preset(path: Path) -> EventPreset:
    try:
        return EventPreset.model_validate_json(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise EventError(f"Datei nicht gefunden: {path}")
    except ValueError as exc:
        raise EventError(f"Die Datei ist keine gültige Festvorlage: {exc}")


def _category_ids(value: str | None) -> list[int] | None:
    if value is None:
        return None
    try:
        return [int(v) for v in value.split(",") if v.strip()]
    except ValueError:
        raise EventError(f"Ungültige Kategorie-Liste: {value}")


def _check_schema(db_path: Path) -> None:
    """Der Dienst bringt die Datenbank beim Start auf den aktuellen Stand.
    Läuft dieser Befehl gegen eine ältere Datenbank (Update installiert,
    Dienst seitdem nie gestartet), fehlen Spalten — dann lieber abbrechen.
    Fehlt die Datei ganz, ebenfalls: sqlite3.connect() würde sonst eine
    leere kasse.db anlegen, und der Dienst hielte die Einrichtung danach
    für erledigt."""
    if not db_path.exists():
        raise EventError(f"Datenbank nicht gefunden: {db_path}. Bitte den Dienst einmal starten.")
    with database.get_db() as db:
        version = db.execute("PRAGMA user_version").fetchone()[0]
    if version < db_backup.SCHEMA_VERSION:
        raise EventError(
            "Die Datenbank ist noch nicht auf dem aktuellen Stand. "
            "Bitte den Dienst einmal starten und es dann erneut versuchen."
        )


def _safety_backup(data_dir: Path, db_path: Path, action: str, prefix: str = "vor-festwechsel") -> str:
    try:
        backup = db_backup.create_backup(db_path, data_dir / "backups", prefix=prefix)
    except db_backup.BackupError as exc:
        raise EventError(f"Sicherung fehlgeschlagen, {action} wurde nicht ausgeführt: {exc}")
    return backup.name


def _license_check(args, data_dir: Path) -> dict:
    """Status of each licence — keys given as arguments (fields not saved
    yet), the rest from config.env. Needs no database."""
    import licensing
    from dotenv import dotenv_values

    env_path = data_dir / "config.env"
    env = dotenv_values(env_path) if env_path.exists() else {}
    installation_id = env.get("INSTALLATION_ID") or ""
    licenses = {}
    for feature, env_key in LICENSE_KEYS.items():
        key = getattr(args, feature)
        licenses[feature] = licensing.check(feature, installation_id, key if key is not None else env.get(env_key) or "")
    return {"installation_id": installation_id, "licenses": licenses}


def _run(args, data_dir: Path, db_path: Path) -> dict:
    if args.command == "license-check":
        return _license_check(args, data_dir)
    _check_schema(db_path)

    if args.command == "events":
        with database.get_db() as db:
            return event_lifecycle.overview(db, tenants.active_tenant_id(db))

    if args.command == "event-start":
        preset = _load_preset(Path(args.preset)) if args.preset else None
        with database.get_db() as db:
            tenant_id = tenants.active_tenant_id(db)
            event_lifecycle.check_can_start(db, tenant_id)
        backup = _safety_backup(data_dir, db_path, "Festbeginn")
        with database.get_db(exclusive=True) as db:
            event = event_lifecycle.start_event(
                db,
                tenant_id=tenant_id,
                name=args.name,
                date=args.date,
                chip_deposit=args.deposit,
                reset_stock=not args.keep_stock,
                source_event_id=args.source_event,
                preset=preset,
                include_articles=not args.no_articles,
                category_ids=_category_ids(args.categories),
            )
        # Erst nach dem erfolgreichen Festwechsel — scheitert der, bleiben
        # bon.yaml und config.env unangetastet.
        needs_restart = preset is not None and event_lifecycle.apply_preset_settings(
            preset,
            data_dir,
            bon_layout=args.bon_layout,
            printer=args.printer,
            bon_text=args.bon_text,
        )
        return {"event": event, "needs_restart": needs_restart, "safety_backup": backup}

    if args.command == "event-update":
        with database.get_db(exclusive=True) as db:
            event = event_lifecycle.update_active_event(
                db,
                tenant_id=tenants.active_tenant_id(db),
                name=args.name,
                chip_deposit=args.deposit,
            )
        return {"event": event}

    if args.command == "tenants":
        with database.get_db() as db:
            return {"tenants": tenants.list_tenants(db), "active_tenant_id": tenants.active_tenant_id(db)}

    if args.command == "tenant-create":
        # Das Passwort kommt über stdin, nicht als Argument — Befehlszeilen
        # sind für andere Prozesse sichtbar und landen in Protokollen.
        password = sys.stdin.readline().rstrip("\r\n")
        with database.get_db(exclusive=True) as db:
            tenant = tenants.create_tenant(
                db, name=args.name, admin_username=args.admin_user, admin_password=password,
                bar_chip_uid=event_lifecycle.bar_chip_uid(data_dir),
            )
        return {"tenant": tenant}

    if args.command == "tenant-activate":
        with database.get_db() as db:
            tenants.check_can_activate(db, args.tenant_id)
        backup = _safety_backup(data_dir, db_path, "Veranstalterwechsel", prefix="vor-veranstalterwechsel")
        with database.get_db(exclusive=True) as db:
            tenant = tenants.activate_tenant(db, args.tenant_id)
        return {"tenant": tenant, "safety_backup": backup}

    if args.command == "tenant-rename":
        with database.get_db(exclusive=True) as db:
            return {"tenant": tenants.rename_tenant(db, args.tenant_id, args.name)}

    if args.command == "event-end":
        with database.get_db() as db:
            tenant_id = tenants.active_tenant_id(db)
            event_lifecycle.check_can_end(db, tenant_id)
        backup = _safety_backup(data_dir, db_path, "Festende")
        with database.get_db(exclusive=True) as db:
            event = event_lifecycle.end_event(db, tenant_id=tenant_id)
        return {"event": event, "safety_backup": backup}

    if args.command == "preset-export":
        with database.get_db() as db:
            preset = event_lifecycle.build_preset(
                db,
                tenant_id=tenants.active_tenant_id(db),
                event_id=args.event_id,
                data_dir=data_dir,
            )
        Path(args.file).write_text(preset.model_dump_json(indent=2), encoding="utf-8")
        return {"file": args.file, "categories": len(preset.categories), "products": len(preset.products)}

    # csv-export
    with database.get_db() as db:
        text, rows = event_lifecycle.export_csv(
            db,
            tenant_id=tenants.active_tenant_id(db),
            event_id=args.event_id,
            period_id=args.period,
            bar_chip_uid=event_lifecycle.bar_chip_uid(data_dir),
        )
    # utf-8-sig: mit BOM, damit Excel Umlaute in Artikelnamen richtig anzeigt.
    # newline="": die Zeilenenden (\r\n) setzt schon der csv-Writer.
    Path(args.file).write_text(text, encoding="utf-8-sig", newline="")
    return {"file": args.file, "rows": rows}


def main(argv: list[str], data_dir: Path, db_path: Path | None = None) -> int:
    args = _parser().parse_args(argv)
    db_path = db_path or data_dir / "kasse.db"
    database.DB_PATH = str(db_path)
    try:
        result = _run(args, data_dir, db_path)
    except EventError as exc:
        db_backup._emit({"ok": False, "error": str(exc)})
        return db_backup.EXIT_ERROR
    except sqlite3.Error as exc:
        db_backup._emit({"ok": False, "error": f"Datenbankfehler: {exc}"})
        return db_backup.EXIT_ERROR
    except OSError as exc:
        db_backup._emit({"ok": False, "error": f"Datei konnte nicht geschrieben werden: {exc}"})
        return db_backup.EXIT_ERROR
    db_backup._emit({"ok": True, **result})
    return db_backup.EXIT_OK
