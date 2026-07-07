"""
NFC-Kasse FastAPI application entry point.

Registers all routers and configures CORS.  The CORS whitelist is read from the
ALLOWED_ORIGINS environment variable so it can be tightened for production
without a code change.  In development (e.g. Android emulator) the default
covers localhost only.
"""

import logging
import logging.handlers
import os
from pathlib import Path

from fastapi import FastAPI


import time as _time
from datetime import datetime as _datetime


class _TopOfHourHandler(logging.handlers.TimedRotatingFileHandler):
    """
    Schreibt in kasse_YYYY-MM-DD_HH.log und rotiert exakt zur vollen Stunde.
    Beim Rotieren wird eine neue Datei für die aktuelle Stunde geöffnet.
    Alte Dateien werden gelöscht, sobald mehr als backupCount vorhanden sind.
    """

    def __init__(self, log_dir: Path, backup_count: int = 168, encoding: str = "utf-8"):
        self._log_dir = log_dir
        super().__init__(
            filename=str(log_dir / self._filename_for_now()),
            when="h",
            interval=1,
            backupCount=backup_count,
            encoding=encoding,
        )
        self.rolloverAt = self._next_full_hour()

    @staticmethod
    def _filename_for_now() -> str:
        return _datetime.now().strftime("kasse_%Y-%m-%d_%H.log")

    @staticmethod
    def _next_full_hour() -> int:
        t = int(_time.time())
        return (t // 3600 + 1) * 3600

    def doRollover(self) -> None:
        if self.stream:
            self.stream.close()
            self.stream = None
        self.baseFilename = str(self._log_dir / self._filename_for_now())
        self.stream = self._open()
        self.rolloverAt = self._next_full_hour()
        self._delete_old_files()

    def _delete_old_files(self) -> None:
        files = sorted(
            self._log_dir.glob("kasse_*.log"),
            key=lambda p: p.stat().st_mtime,
        )
        for old in files[: max(0, len(files) - self.backupCount)]:
            try:
                old.unlink()
            except OSError:
                pass


def _setup_logging() -> None:
    log_dir = Path(__file__).parent / "logs"
    log_dir.mkdir(exist_ok=True)

    file_handler = _TopOfHourHandler(log_dir=log_dir, backup_count=168)
    file_handler.setFormatter(logging.Formatter(
        fmt="%(asctime)s %(levelname)-8s %(name)-24s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))

    # /health wird alle 10 s gepollt — aus dem Log herausfiltern
    class _SuppressHealth(logging.Filter):
        def filter(self, record: logging.LogRecord) -> bool:
            return '"/health"' not in record.getMessage()

    file_handler.addFilter(_SuppressHealth())
    logging.getLogger().addHandler(file_handler)


_setup_logging()

from database import get_db
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from config import BAR_CHIP_UID, EVENT_NAME
from routers import auth, customers, display, download, help, kiosk, preferences, printer, products, sales, stats, topup, update, users


def _migrate() -> None:
    """Creates tables added after initial DB setup (safe to run on every start)."""
    with get_db() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS user_preference_store (
                user_id  INTEGER NOT NULL REFERENCES user(id),
                key      TEXT    NOT NULL,
                profile  TEXT    NOT NULL DEFAULT '*',
                value    TEXT    NOT NULL,
                PRIMARY KEY (user_id, key, profile)
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS help_request (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id     INTEGER NOT NULL REFERENCES event(id),
                requester_id INTEGER NOT NULL REFERENCES user(id),
                status       TEXT    NOT NULL DEFAULT 'active',
                created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS help_response (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id   INTEGER NOT NULL REFERENCES help_request(id),
                responder_id INTEGER NOT NULL REFERENCES user(id),
                response     TEXT    NOT NULL,
                created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
                UNIQUE(request_id, responder_id)
            )
        """)
        # Insert 'help.receive' permission node if not yet seeded
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('help', NULL, 'Notfall', 'group', 5)
        """)
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('help.receive', 'help', 'Notfall-Kontakt', 'w', 1)
        """)
        # Insert 'bon.drucken' permission node if not yet seeded
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('bon', NULL, 'Bon-Druck', 'group', 6)
        """)
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('bon.drucken', 'bon', 'Bon drucken', 'w', 1)
        """)
        # Insert 'kiosk.access' permission node if not yet seeded
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('kiosk', NULL, 'Kundenterminal', 'group', 7)
        """)
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('kiosk.access', 'kiosk', 'Kiosk-Modus', 'w', 1)
        """)
        # Sync event name from config.env on every start
        db.execute(
            "UPDATE event SET name = ? WHERE id = 1",
            (EVENT_NAME,),
        )
        # Create BAR virtual chip for cash sales if not yet present (tenant_id=1 for local installs)
        db.execute("""
            INSERT OR IGNORE INTO customer (tenant_id, nfc_uid, balance, is_available)
            SELECT 1, ?, 0.0, 0
            WHERE EXISTS (SELECT 1 FROM tenant WHERE id = 1)
        """, (BAR_CHIP_UID,))
        # Print job queue table
        db.execute("""
            CREATE TABLE IF NOT EXISTS print_job (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id     INTEGER NOT NULL REFERENCES event(id),
                sale_id      INTEGER REFERENCES sale(id),
                username     TEXT    NOT NULL,
                event_name   TEXT    NOT NULL,
                product_name TEXT    NOT NULL,
                price        REAL    NOT NULL,
                status       TEXT    NOT NULL DEFAULT 'pending',
                error_msg    TEXT,
                created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
                processed_at TEXT
            )
        """)


_migrate()

app = FastAPI(
    title="NFC-Kasse API",
    description="Cashless NFC payment system for events.",
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# CORS
# Restrict to local network in production. Set ALLOWED_ORIGINS env var for
# a comma-separated list, e.g. "http://192.168.1.1:8000,http://localhost:8000"
# ---------------------------------------------------------------------------
_raw_origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:8000,http://127.0.0.1:8000")
allowed_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(auth.router)
app.include_router(display.router)      # /display HTML pages (no /api prefix)
app.include_router(display.api_router)  # /api/display/* API
app.include_router(products.router)
app.include_router(sales.router)
app.include_router(topup.router)
app.include_router(users.router)
app.include_router(stats.router)
app.include_router(customers.router)
app.include_router(kiosk.router)
app.include_router(printer.router)
app.include_router(preferences.router)
app.include_router(help.router)
app.include_router(update.router)
app.include_router(download.router)

# Start the background print-queue worker (daemon thread — stops with the server).
printer.start_worker()


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/health", tags=["system"])
def health():
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Flutter Web App — served from backend/webapp/ if the build exists.
# The route is configurable via WEBAPP_ROUTE in config.env (default /webapp).
# To rebuild after changing the route:
#   flutter build web --release --base-href /your-route/
# ---------------------------------------------------------------------------
_webapp_route = os.environ.get("WEBAPP_ROUTE", "/webapp").strip().rstrip("/")
if not _webapp_route.startswith("/"):
    _webapp_route = "/" + _webapp_route
_webapp_dir = Path(__file__).parent / "webapp"
if _webapp_dir.is_dir():
    app.mount(_webapp_route, StaticFiles(directory=str(_webapp_dir), html=True), name="webapp")
