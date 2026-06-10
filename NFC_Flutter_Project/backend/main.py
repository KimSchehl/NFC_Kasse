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
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from routers import auth, customers, download, products, sales, stats, topup, update, users

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
app.include_router(products.router)
app.include_router(sales.router)
app.include_router(topup.router)
app.include_router(users.router)
app.include_router(stats.router)
app.include_router(customers.router)
app.include_router(update.router)
app.include_router(download.router)


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
