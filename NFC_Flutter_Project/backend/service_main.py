"""
NFC-Kasse — Windows service entrypoint.

Distinct from main.py (the FastAPI app module, used unchanged by both
start_backend.bat/.sh for local development and this script for production).
This module's only job is to get the process environment and the
C:\\ProgramData\\NFC-Kasse filesystem into the state main.py already assumes
before main.py (or anything it imports — logging_config, config, database,
dependencies, every router) is imported for the first time. Those modules
read os.environ at *module import time*, not lazily, so ordering here is
load-bearing: nothing that transitively imports `main` may appear above the
config-loading block in main() below.

This is the module PyInstaller's Analysis() targets to build the frozen
NfcKasseBackend.exe (see packaging/pyinstaller/nfc_kasse_backend.spec).
"""

import os
import secrets
import shutil
import sys
import threading
import uuid
from pathlib import Path

import db_backup

DATA_DIR = Path(os.environ.get("NFC_KASSE_DATA_DIR", r"C:\ProgramData\NFC-Kasse"))
CONFIG_PATH = DATA_DIR / "config.env"
LOGS_DIR = DATA_DIR / "logs"
BACKUPS_DIR = DATA_DIR / "backups"

# Single canonical template, shared with start_backend.bat's dev-mode config
# generation (both substitute the same {secret_key}/{installation_id}
# placeholders) so the two entrypoints can never drift out of sync again.
_CONFIG_TEMPLATE_PATH = Path(__file__).parent / "config.env.template"

BON_YAML_PATH = DATA_DIR / "bon.yaml"
_BON_YAML_DEFAULT_PATH = Path(__file__).parent / "bon.yaml.default"


def _ensure_config() -> None:
    """Creates config.env with a real random SECRET_KEY and a fresh
    INSTALLATION_ID on first run. Never touches an existing file —
    regenerating the secret would invalidate every logged-in session, and
    regenerating the installation ID would invalidate every license key
    already issued for this install."""
    if CONFIG_PATH.exists():
        return
    secret = secrets.token_urlsafe(32)
    installation_id = str(uuid.uuid4())
    template = _CONFIG_TEMPLATE_PATH.read_text(encoding="utf-8")
    CONFIG_PATH.write_text(
        template.format(secret_key=secret, installation_id=installation_id),
        encoding="utf-8",
    )


def _ensure_bon_yaml() -> None:
    """Seeds bon.yaml from the bundled default on first run. Never touches
    an existing file — same non-destructive reasoning as _ensure_config():
    this is the customer's own persisted receipt-layout customization."""
    if BON_YAML_PATH.exists():
        return
    BON_YAML_PATH.write_text(
        _BON_YAML_DEFAULT_PATH.read_text(encoding="utf-8"), encoding="utf-8"
    )


def _wait_for_database(seconds: int = 120) -> None:
    """At boot the PostgreSQL service may still be starting."""
    import time

    import database

    deadline = time.monotonic() + seconds
    while True:
        try:
            database.connect().close()
            return
        except database.OperationalError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(2)


def _rotate_backup() -> None:
    """One automatic safety copy per (re)start, the 5 newest kept."""
    db_backup.create_backup(BACKUPS_DIR, prefix="kasse")
    db_backup.prune(BACKUPS_DIR, prefix="kasse", keep=5)


def _ipv4_addresses() -> list[str]:
    import ifaddr  # zeroconf's own dependency

    return sorted(
        ip.ip
        for adapter in ifaddr.get_adapters()
        for ip in adapter.ips
        if ip.is_IPv4 and not ip.ip.startswith(("127.", "169.254."))
    )


def _advertise(port: int, stop: threading.Event) -> None:
    """Announces the backend as `_nfc-kasse._tcp` via mDNS/DNS-SD so the
    Android app's login screen finds it without typing an address
    (nfc_kasse_app/lib/services/server_discovery_service.dart). Runs in its
    own thread until [stop] is set and re-announces whenever this PC's IPv4
    addresses change: the service starts at boot, but the Wi-Fi or a Windows
    mobile hotspot (192.168.137.1) usually only comes up later, and Zeroconf
    only listens on the interfaces that existed when it was created.
    Best-effort: on failure the service still runs, only auto-discovery is
    missing (the app also probes its own subnet)."""
    import logging
    import socket

    log = logging.getLogger(__name__)
    zc = None
    announced = None
    while True:
        try:
            # shortcut: announces every IPv4 of this PC (VPN/second NIC included),
            # the app lists them all; pin one via config.env if that confuses users.
            addresses = _ipv4_addresses()
            if addresses != announced:
                announced = addresses
                if zc is not None:
                    zc.close()
                    zc = None
                if addresses:
                    from zeroconf import IPVersion, ServiceInfo, Zeroconf

                    host = socket.gethostname()
                    info = ServiceInfo(
                        "_nfc-kasse._tcp.local.",
                        f"NFC-Kasse {host}._nfc-kasse._tcp.local.",
                        port=port,
                        parsed_addresses=addresses,
                        server=f"{host}.local.",
                    )
                    zc = Zeroconf(ip_version=IPVersion.V4Only)
                    zc.register_service(info, allow_name_change=True)
                    log.info("mDNS-Ankündigung aktiv: %s:%s", addresses, port)
        except Exception:
            # Logged once per address set; retried on the next change.
            log.warning("mDNS-Ankündigung fehlgeschlagen", exc_info=True)
        if stop.wait(10):
            break
    if zc is not None:
        zc.close()  # sends the mDNS goodbye so apps drop the entry


def _require_main_license() -> None:
    """The service only runs with a valid main licence (LICENSE_KEY for the
    feature "kasse", bound to INSTALLATION_ID). Without one it exits with a
    German message in logs\\winsw\\ — the admin tool's Lizenzen page shows
    the same status before that happens."""
    import licensing

    result = licensing.check("kasse", os.environ.get("INSTALLATION_ID", ""), os.environ.get("LICENSE_KEY", ""))
    if result["status"] != licensing.VALID:
        print(
            f"NFC-Kasse startet nicht: keine gültige Lizenz (LICENSE_KEY, Status: {result['status']}). "
            "Bitte im Verwaltungstool unter Lizenzen den Lizenzschlüssel eintragen.",
            file=sys.stderr,
        )
        sys.exit(2)


def main() -> None:
    if len(sys.argv) > 1:
        # admin_cli and db_backup read DATABASE_URL from DATA_DIR's config.env
        # themselves (database.use_config) — config.env isn't loaded here.
        import admin_cli

        if sys.argv[1] == "db-setup":
            # Installer: config.env must exist (SECRET_KEY, ...) before
            # DATABASE_URL is added to it.
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            _ensure_config()
            import pg_setup

            sys.exit(pg_setup.main(sys.argv[2:], DATA_DIR))
        if sys.argv[1] in admin_cli.COMMANDS:
            sys.exit(admin_cli.main(sys.argv[1:], DATA_DIR))
        sys.exit(db_backup.main(sys.argv[1:], DATA_DIR))

    # 1. Filesystem + config.env must exist before ANYTHING below imports
    #    main/config/logging_config/database/dependencies.
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)
    _ensure_config()
    _ensure_bon_yaml()

    from dotenv import load_dotenv

    load_dotenv(dotenv_path=CONFIG_PATH, override=False)
    os.environ.setdefault("NFC_KASSE_LOG_DIR", str(LOGS_DIR))
    # routers/printer.py reads this directly (bon.yaml lives in DATA_DIR, not
    # next to the program files) — must be set even when NFC_KASSE_DATA_DIR
    # wasn't already in the environment, since DATA_DIR may be the hardcoded
    # default in that case.
    os.environ.setdefault("NFC_KASSE_DATA_DIR", str(DATA_DIR))

    assert os.environ.get("SECRET_KEY") not in (None, "", "CHANGE-THIS-BEFORE-PRODUCTION"), (
        "SECRET_KEY was not loaded from config.env before main.py's import — "
        "check the import order above this assertion."
    )
    _require_main_license()

    # 2. Backup of an existing database, then bring the schema up to date
    #    (first run: create and seed it). The PostgreSQL database itself is
    #    created by the installer; DATABASE_URL comes from config.env.
    import database
    import init_db
    import schema

    database.use_config(DATA_DIR)  # db_backup imported database before config.env was loaded
    if not os.environ.get("DATABASE_URL"):
        print(
            "NFC-Kasse startet nicht: keine Datenbank eingerichtet (DATABASE_URL fehlt in config.env). "
            "Bitte das Setup erneut ausführen.",
            file=sys.stderr,
        )
        sys.exit(2)
    _wait_for_database()
    with database.get_db() as db:
        existing = schema.current(db) is not None
    if existing:
        _rotate_backup()
    init_db.setup()

    # 3. Only now is it safe to import main (and therefore config,
    #    logging_config, database, dependencies, every router).
    import uvicorn
    from main import app

    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    # workers is deliberately NOT set — printer.start_worker()'s worker
    # guard, device_registry's in-memory dict, and help.py's _HelpManager are
    # all per-process singletons. Multiple uvicorn workers would each run an
    # independent print queue and duplicate every receipt.
    stop_advertising = threading.Event()
    advertiser = threading.Thread(target=_advertise, args=(port, stop_advertising), daemon=True)
    advertiser.start()
    try:
        # timeout_graceful_shutdown: without it uvicorn waits on shutdown until
        # every SSE stream (customer display, leaderboard) is closed by its
        # client -- the connected display phone never does, so a service stop
        # hung until WinSW killed the process and an update install found
        # NfcKasseBackend.exe still locked.
        uvicorn.run(app, host=host, port=port, reload=False, timeout_graceful_shutdown=5)
    finally:
        stop_advertising.set()
        advertiser.join(timeout=5)


if __name__ == "__main__":
    main()
