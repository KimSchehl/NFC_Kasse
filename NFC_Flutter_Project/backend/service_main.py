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
import sqlite3
import uuid
from datetime import datetime
from pathlib import Path

DATA_DIR = Path(os.environ.get("NFC_KASSE_DATA_DIR", r"C:\ProgramData\NFC-Kasse"))
CONFIG_PATH = DATA_DIR / "config.env"
DB_PATH = DATA_DIR / "kasse.db"
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


def _rotate_backup() -> None:
    """Mirrors start_backend.bat's existing behavior: one timestamped backup
    per (re)start, pruned to the 5 newest. Uses sqlite3's own .backup() API
    (WAL-safe) rather than a plain file copy, since kasse.db runs in WAL
    mode (init_db.py) and a raw copy could miss un-checkpointed writes."""
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M")
    src = sqlite3.connect(DB_PATH)
    dest = sqlite3.connect(BACKUPS_DIR / f"kasse_{ts}.db")
    try:
        src.backup(dest)
    finally:
        dest.close()
        src.close()
    backups = sorted(
        BACKUPS_DIR.glob("kasse_*.db"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    for stale in backups[5:]:
        stale.unlink(missing_ok=True)


def main() -> None:
    # 1. Filesystem + config.env must exist before ANYTHING below imports
    #    main/config/logging_config/database/dependencies.
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)
    _ensure_config()
    _ensure_bon_yaml()

    from dotenv import load_dotenv

    load_dotenv(dotenv_path=CONFIG_PATH, override=False)
    os.environ.setdefault("DB_PATH", str(DB_PATH))
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

    # 2. First-run DB init OR startup backup rotation — the same branching
    #    start_backend.bat's step 5 does, now against ProgramData.
    if not DB_PATH.exists():
        import init_db as idb

        conn = idb.init_db()
        idb.seed_permissions(conn)
        idb.seed_default_data(conn)
        conn.close()
    else:
        _rotate_backup()

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
    uvicorn.run(app, host=host, port=port, reload=False)


if __name__ == "__main__":
    main()
