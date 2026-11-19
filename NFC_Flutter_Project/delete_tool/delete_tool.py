"""
Interactive tool to delete a whole Veranstalter or a single ended Fest.

Started via loeschen.bat (installs its own venv + questionary). Runs on the
server: stops the NfcKasseBackend service while deleting and starts it
again afterwards. Always writes a backup "vor-loeschen_*" next to the
regular backups first, so a mistake can be undone in the admin tool
(Sicherungen → Wiederherstellen).

    python delete_tool.py [--data-dir PFAD] [--no-service]
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import questionary

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))
import database  # noqa: E402
import db_backup  # noqa: E402

import purge  # noqa: E402

# questionary replaces a Choice value of None by its title, so "back" needs its own value.
BACK = "__back__"
DEFAULT_DATA_DIR = Path(os.environ.get("NFC_KASSE_DATA_DIR", r"C:\ProgramData\NFC-Kasse"))


def euro(value) -> str:
    return f"{value or 0:.2f} €".replace(".", ",")


def say(text: str = "") -> None:
    print(text, flush=True)


# ---------------------------------------------------------------- service

def _sc(*args) -> str:
    try:
        return subprocess.run(["sc", *args], capture_output=True, text=True, errors="replace").stdout
    except OSError:
        return ""


def service_state() -> str | None:
    out = _sc("query", db_backup.SERVICE_NAME)
    for state in ("RUNNING", "STOPPED", "START_PENDING", "STOP_PENDING"):
        if state in out:
            return state
    return None  # not installed / not on Windows


def wait_for(state: str, seconds: int = 30) -> bool:
    for _ in range(seconds * 2):
        if service_state() == state:
            return True
        time.sleep(0.5)
    return False


def stop_service() -> bool:
    say("Dienst wird gestoppt ...")
    _sc("stop", db_backup.SERVICE_NAME)
    if not wait_for("STOPPED"):
        say("Der Dienst ließ sich nicht stoppen. Bitte im Admin-Tool stoppen und das Tool neu starten.")
        return False
    say("Dienst gestoppt.")
    return True


def start_service() -> None:
    say("Dienst wird wieder gestartet ...")
    _sc("start", db_backup.SERVICE_NAME)
    say("Dienst läuft wieder." if wait_for("RUNNING") else
        "Der Dienst startet nicht von selbst. Bitte im Admin-Tool starten.")


# ---------------------------------------------------------------- dialogs

def pick_tenant(db, deletable_only: bool):
    tenants = purge.list_tenants(db)
    choices = []
    for t in tenants:
        title = (f"{t['name']}  ({t['fests']} Feste, {t['users']} Benutzer, {t['chips']} Chips, "
                 f"Restguthaben {euro(t['open_balance'])})")
        disabled = None
        if deletable_only:
            if t["active"]:
                disabled = "aktiv, erst im Admin-Tool umschalten"
            elif len(tenants) <= 1:
                disabled = "letzter Veranstalter"
        elif t["active"]:
            title += "  [aktiv]"
        choices.append(questionary.Choice(title, value=t["id"], disabled=disabled))
    choices.append(questionary.Choice("Zurück", value=BACK))
    answer = questionary.select("Welcher Veranstalter?", choices=choices).ask()
    return None if answer == BACK else answer


def confirm_by_name(kind: str, name: str) -> bool:
    typed = questionary.text(f"Zum Bestätigen den Namen {kind} genau eintippen:").ask()
    if typed is None or typed.strip() != name:
        say("Name stimmt nicht. Abgebrochen, nichts gelöscht.")
        return False
    if not questionary.confirm("Wirklich endgültig löschen?", default=False).ask():
        say("Abgebrochen, nichts gelöscht.")
        return False
    return True


def run_delete(db, data_dir: Path, label: str, action) -> None:
    backup = db_backup.create_backup(data_dir / "backups", prefix="vor-loeschen", label=label)
    say(f"Backup angelegt: {backup}")
    try:
        action(db)
        db.commit()
    except Exception:
        db.rollback()
        raise
    say("Gelöscht.")


def delete_tenant_flow(db, data_dir: Path) -> None:
    tenant_id = pick_tenant(db, deletable_only=True)
    if tenant_id is None:
        return
    t = purge.tenant_summary(db, tenant_id)
    say()
    say(f"Veranstalter „{t['name']}“ wird KOMPLETT gelöscht:")
    say(f"  {t['fests']} Feste mit {t['sales']} Verkäufen, Intern, alle Tagesabschlüsse und Bons")
    say(f"  {t['users']} Benutzer mit allen Rechten")
    say(f"  {t['categories']} Kategorien mit {t['products']} Artikeln")
    say(f"  {t['chips']} ausgegebene Chips")
    if t["open_balance"] > 0 or t["open_deposit"] > 0:
        say()
        say(f"  ACHTUNG: Auf {t['open_balance_chips']} Chips liegen noch {euro(t['open_balance'])} Guthaben,")
        say(f"  dazu {euro(t['open_deposit'])} Pfand. Dieses Geld ist danach nicht mehr nachvollziehbar.")
    say()
    if confirm_by_name("des Veranstalters", t["name"]):
        run_delete(db, data_dir, t["name"], lambda conn: purge.delete_tenant(conn, tenant_id))


def delete_fest_flow(db, data_dir: Path) -> None:
    tenants = purge.list_tenants(db)
    tenant_id = tenants[0]["id"] if len(tenants) == 1 else pick_tenant(db, deletable_only=False)
    if tenant_id is None:
        return
    fests = purge.list_fests(db, tenant_id)
    if not fests:
        say("Dieser Veranstalter hat keine Feste.")
        return
    choices = []
    for f in fests:
        when = (f["started_at"] or f["date"] or "")[:10]
        title = f"{f['name']}  ({when + ', ' if when else ''}{f['sales']} Verkäufe, {f['topups']} Aufladungen)"
        choices.append(questionary.Choice(title, value=f["id"], disabled="läuft gerade" if f["active"] else None))
    choices.append(questionary.Choice("Zurück", value=BACK))
    event_id = questionary.select("Welches Fest?", choices=choices).ask()
    if event_id in (None, BACK):
        return
    f = purge.fest_summary(db, event_id)
    say()
    say(f"Fest „{f['name']}“ wird gelöscht:")
    say(f"  {f['sales']} Verkäufe, {f['topups']} Aufladungen/Auszahlungen, {f['periods']} Tagesabschluss-Zeiträume,")
    say(f"  {f['pagers']} Pager, {f['print_jobs']} Bons und die Bestenliste dieses Fests.")
    say("  Guthaben und Pfand auf den Chips bleiben unverändert. Benutzer, Kategorien und")
    say("  Artikel gehören dem Veranstalter und bleiben ebenfalls.")
    say()
    if confirm_by_name("des Fests", f["name"]):
        run_delete(db, data_dir, f["name"], lambda conn: purge.delete_fest(conn, event_id))


# ---------------------------------------------------------------- main

def main() -> int:
    parser = argparse.ArgumentParser(description="Veranstalter oder Feste aus der NFC-Kasse löschen")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR,
                        help=f"Datenordner mit config.env (Standard: {DEFAULT_DATA_DIR})")
    parser.add_argument("--no-service", action="store_true", help="Windows-Dienst nicht anfassen")
    args = parser.parse_args()
    data_dir: Path = args.data_dir
    database.use_config(data_dir)

    say("NFC-Kasse: Veranstalter und Feste löschen")
    say(f"Datenordner: {data_dir}")
    say()

    restart = False
    if not args.no_service and service_state() in ("RUNNING", "START_PENDING"):
        say("Der Kassen-Dienst läuft. Während des Löschens muss er gestoppt sein,")
        say("alle Geräte sind solange offline.")
        if not questionary.confirm("Dienst jetzt stoppen?", default=True).ask():
            say("Abgebrochen, nichts gelöscht.")
            return 0
        if not stop_service():
            return 1
        restart = True

    try:
        while True:
            say()
            choice = questionary.select(
                "Was soll gelöscht werden?",
                choices=[
                    questionary.Choice("Einzelnes Fest", value="fest"),
                    questionary.Choice("Veranstalter komplett (Feste, Benutzer, Artikel, Chips, ...)", value="tenant"),
                    questionary.Choice("Beenden", value=BACK),
                ],
            ).ask()
            if choice in (None, BACK):
                break
            db = database.connect()
            try:
                (delete_fest_flow if choice == "fest" else delete_tenant_flow)(db, data_dir)
            except (purge.PurgeError, db_backup.BackupError) as e:
                say(f"Nicht möglich: {e}")
            except database.Error as e:
                say(f"Datenbankfehler, nichts gelöscht: {e}")
            finally:
                db.close()
    finally:
        if restart:
            start_service()
    return 0


if __name__ == "__main__":
    sys.exit(main())
