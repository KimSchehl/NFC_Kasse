"""
NFC-Kasse FastAPI application entry point.

Registers all routers and configures CORS.  The CORS whitelist is read from the
ALLOWED_ORIGINS environment variable so it can be tightened for production
without a code change.  In development (e.g. Android emulator) the default
covers localhost only.
"""

import os
from pathlib import Path

from fastapi import FastAPI

from logging_config import setup_logging

setup_logging()

import device_registry
from database import get_db
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from config import BAR_CHIP_UID, EVENT_NAME, LEADERBOARD_ENABLED, PAGER_ENABLED
from middleware import TraceIdMiddleware
from routers import auth, customers, display, download, help, kiosk, logs as logs_router, preferences, printer, products, sales, stats, topup, update, users
if LEADERBOARD_ENABLED:
    from routers import leaderboard
if PAGER_ENABLED:
    from routers import pager


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
        # Insert 'logs.*' permission nodes if not yet seeded
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('logs', NULL, 'Protokolle', 'group', 8)
        """)
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('logs.view', 'logs', 'Protokolle einsehen', 'r', 1)
        """)
        db.execute("""
            INSERT OR IGNORE INTO permission_node (id, parent_id, label, node_type, sort_order)
            VALUES ('logs.configure', 'logs', 'Protokoll-Level verwalten', 'w', 2)
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS device_log_level (
                device_id     TEXT PRIMARY KEY,
                label         TEXT,
                platform      TEXT,
                forced_level  TEXT,
                updated_by    INTEGER REFERENCES user(id),
                updated_at    TEXT
            )
        """)
        # customer_name column — added for kiosk self-service naming
        try:
            db.execute("ALTER TABLE customer ADD COLUMN customer_name TEXT")
        except Exception:
            pass  # column already exists
        # points per product — leaderboard scoring (kept even when LEADERBOARD=false,
        # so data is preserved when the feature is toggled on/off)
        try:
            db.execute("ALTER TABLE product ADD COLUMN points INTEGER NOT NULL DEFAULT 0")
        except Exception:
            pass
        # stock tracking + change timestamp (for the /api/products/changed sync
        # endpoint). No DEFAULT possible via ALTER TABLE ADD COLUMN in SQLite —
        # existing rows get NULL, which /changed correctly treats as "never
        # changed" until the next save touches them.
        try:
            db.execute("ALTER TABLE product ADD COLUMN stock INTEGER")
        except Exception:
            pass
        try:
            db.execute("ALTER TABLE product ADD COLUMN updated_at TEXT")
        except Exception:
            pass
        # requires_pager per product — pager add-on (kept even when PAGER=false,
        # same reasoning as the points/leaderboard column above)
        try:
            db.execute("ALTER TABLE product ADD COLUMN requires_pager INTEGER NOT NULL DEFAULT 0")
        except Exception:
            pass
        # leaderboard_score table — full add-on, separate from customer table
        db.execute("""
            CREATE TABLE IF NOT EXISTS leaderboard_score (
                customer_id INTEGER PRIMARY KEY REFERENCES customer(id),
                points      INTEGER NOT NULL DEFAULT 0,
                opt_in      INTEGER NOT NULL DEFAULT 0,
                updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
            )
        """)
        # Migrate legacy columns from customer table (if they existed) into leaderboard_score
        try:
            db.execute("""
                INSERT OR IGNORE INTO leaderboard_score (customer_id, points, opt_in)
                SELECT id,
                       COALESCE((
                           SELECT SUM(CASE WHEN s.cancelled=0 THEN p.points ELSE 0 END)
                           FROM sale s JOIN product p ON s.product_id = p.id
                           WHERE s.customer_id = customer.id
                       ), 0) - COALESCE(points_earned_before_reset, 0),
                       COALESCE(leaderboard_opt_in, 0)
                FROM customer
                WHERE leaderboard_opt_in = 1
            """)
        except Exception:
            pass  # old columns may not exist on fresh installs
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
        # Pager order table — pager add-on, see PAGER_ENABLED
        db.execute("""
            CREATE TABLE IF NOT EXISTS pager_order (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id     INTEGER NOT NULL REFERENCES event(id),
                created_by   INTEGER NOT NULL REFERENCES user(id),
                item_summary TEXT    NOT NULL,
                pager_number INTEGER NOT NULL,
                sale_ids     TEXT,
                status       TEXT    NOT NULL DEFAULT 'open',
                created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
                done_at      TEXT
            )
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_pager_order_operator ON pager_order(created_by, event_id, status)")


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

# Added after CORS so it becomes the outermost layer (Starlette wraps
# middleware in reverse-add order) — sees the full request/response
# lifecycle, including CORS preflight handling, for accurate timing/logging.
app.add_middleware(TraceIdMiddleware)

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
if LEADERBOARD_ENABLED:
    app.include_router(leaderboard.router)      # /leaderboard HTML page (no /api prefix)
    app.include_router(leaderboard.api_router)  # /api/leaderboard/* API
if PAGER_ENABLED:
    app.include_router(pager.router)
app.include_router(printer.router)
app.include_router(preferences.router)
app.include_router(help.router)
app.include_router(update.router)
app.include_router(download.router)
app.include_router(logs_router.router)

# Start the background print-queue worker (daemon thread — stops with the server).
printer.start_worker()

# Restores any admin-forced log levels (incl. the server's own) across restarts.
device_registry.load_from_db()


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/health", tags=["system"])
def health(
    device_id: str | None = None,
    platform: str | None = None,
    label: str | None = None,
):
    log_level = device_registry.touch(device_id, platform, label) if device_id else None
    return {"status": "ok", "log_level": log_level}


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
