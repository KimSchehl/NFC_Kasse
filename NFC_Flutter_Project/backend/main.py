"""
NFC-Kasse FastAPI application entry point.

Registers all routers and configures CORS.  The CORS whitelist is read from the
ALLOWED_ORIGINS environment variable so it can be tightened for production
without a code change.  In development (e.g. Android emulator) the default
covers localhost only.
"""

import logging
from pathlib import Path

from fastapi import FastAPI

from logging_config import setup_logging

setup_logging()

import device_registry
import tenants
from database import get_db
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from psycopg.errors import InvalidTextRepresentation
from fastapi.staticfiles import StaticFiles

from config import ALLOWED_ORIGINS, BAR_CHIP_UID, LEADERBOARD_ENABLED, PAGER_ENABLED, WEBAPP_ROUTE
from dependencies import EventChangedError
from event_lifecycle import EventError
from middleware import TraceIdMiddleware
from routers import auth, customers, display, download, help, kiosk, logs as logs_router, preferences, printer, products, sales, stats, topup, update, users
if LEADERBOARD_ENABLED:
    from routers import leaderboard
if PAGER_ENABLED:
    from routers import pager


with get_db() as _db:
    # Virtual BAR chip for cash sales — one per Veranstalter.
    tenants.ensure_bar_chips(_db, BAR_CHIP_UID)

if LEADERBOARD_ENABLED:
    leaderboard.check_and_notify()

app = FastAPI(
    title="NFC-Kasse API",
    description="Cashless NFC payment system for events.",
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# CORS
# Restrict to local network in production. Set ALLOWED_ORIGINS in config.env
# for a comma-separated list, e.g. "http://192.168.1.1:8000,http://localhost:8000"
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
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

@app.exception_handler(EventChangedError)
async def _event_changed(_request, exc: EventChangedError):
    # "detail" is what every client already shows as the error text; "code"
    # lets the app react (reload articles/rights) without parsing that text.
    return JSONResponse(status_code=409, content={"detail": str(exc), "code": "event_changed"})


@app.exception_handler(InvalidTextRepresentation)
async def _malformed_id(request, exc):
    # An id that isn't a UUID (e.g. an old numeric id from a stale client)
    # can't match any row: same answer as an unknown id, not a 500.
    logging.getLogger(__name__).warning("Malformed id in %s %s: %s", request.method, request.url.path, exc)
    return JSONResponse(status_code=404, content={"detail": "Nicht gefunden"})


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
    # Feste are switched from the admin tool (admin_cli.py), not from any
    # device — this is how the devices notice: every client already polls
    # /health every 10s, and reloads its event-scoped data (articles,
    # rights, periods) as soon as this list changes.
    # The active Veranstalter's running event; a Veranstalter switch logs
    # every device out anyway (see tenants.activate_tenant).
    try:
        with get_db() as db:
            event = tenants.active_event(db)
            # Any catalog change (article, category, show/hide, fest name):
            # devices reload their catalog when this number changes.
            catalog_rev = db.execute(
                "SELECT catalog_rev FROM tenant WHERE active = 1"
            ).fetchone()
    except EventError as exc:
        # Empty database (no Veranstalter): the kasse can't work, so report unhealthy.
        return JSONResponse(status_code=503, content={"status": "error", "detail": str(exc)})
    active_events = [event["id"]] if event else []
    return {
        "status": "ok",
        "log_level": log_level,
        "active_events": active_events,
        "catalog_rev": catalog_rev[0] if catalog_rev else 0,
    }


# ---------------------------------------------------------------------------
# Flutter Web App — served from backend/webapp/ if the build exists.
# The route is configurable via WEBAPP_ROUTE in config.env (default /webapp).
# To rebuild after changing the route:
#   flutter build web --release --base-href /your-route/
# ---------------------------------------------------------------------------
class _RevalidatingStaticFiles(StaticFiles):
    # The Flutter build's file names carry no hash, so without this browsers
    # keep serving the old main.dart.js after an update (heuristic caching).
    # no-cache still lets them reuse it after a cheap ETag check.
    def file_response(self, *args, **kwargs):
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "no-cache"
        return response


_webapp_dir = Path(__file__).parent / "webapp"
if _webapp_dir.is_dir():
    app.mount(WEBAPP_ROUTE, _RevalidatingStaticFiles(directory=str(_webapp_dir), html=True), name="webapp")
