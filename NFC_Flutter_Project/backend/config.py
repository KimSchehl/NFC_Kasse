import logging
import os

import licensing

logger = logging.getLogger(__name__)


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("true", "1", "yes")


# Stable per-installation identifier, generated once at config.env creation
# time (start_backend.bat / service_main.py) and never changed afterward —
# every license key is signed for one specific INSTALLATION_ID, so changing
# it invalidates every license already issued for this install.
INSTALLATION_ID: str = os.getenv("INSTALLATION_ID", "")

# Chip deposit in EUR (e.g. 3.0 for 3 Euro).
# Configured via CHIP_DEPOSIT in config.env.
# Applied automatically on first chip issuance; refunded automatically on payout.
# Set to 0 to disable deposit logic entirely.
CHIP_DEPOSIT: float = float(os.getenv("CHIP_DEPOSIT", "0"))

# Name of the event shown in the UI and on bon slips.
# Configured via EVENT_NAME in config.env.
EVENT_NAME: str = os.getenv("EVENT_NAME", "Hauptveranstaltung")

# Virtual chip UID used for cash (bar) sales without a physical NFC chip.
# Bookings appear in category statistics but the chip is hidden from the Chips tab.
# Balance is allowed to go negative (it accumulates bar sales as a debt counter).
BAR_CHIP_UID: str = os.getenv("BAR_CHIP_UID", "BAR")

# ---------------------------------------------------------------------------
# Auth (moved here from dependencies.py so every setting the app reads has
# exactly one home — dependencies.py now imports these instead of calling
# os.environ itself).
# ---------------------------------------------------------------------------

SECRET_KEY: str = os.environ.get("SECRET_KEY", "CHANGE-THIS-BEFORE-PRODUCTION")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 1440  # 24 hours — suitable for all-day POS use
REFRESH_TOKEN_EXPIRE_DAYS = 30

if SECRET_KEY == "CHANGE-THIS-BEFORE-PRODUCTION":
    logger.warning("Using default SECRET_KEY. Set the SECRET_KEY environment variable in production.")

# ---------------------------------------------------------------------------
# Web / network access (moved here from main.py, same reasoning as above)
# ---------------------------------------------------------------------------

# Comma-separated list of allowed CORS origins.
# Configured via ALLOWED_ORIGINS in config.env, e.g.
# "http://192.168.1.1:8000,http://localhost:8000".
_raw_origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:8000,http://127.0.0.1:8000")
ALLOWED_ORIGINS: list[str] = [o.strip() for o in _raw_origins.split(",") if o.strip()]

# URL path the bundled Flutter web build is served under.
# Configured via WEBAPP_ROUTE in config.env.
_webapp_route = os.environ.get("WEBAPP_ROUTE", "/webapp").strip().rstrip("/")
if not _webapp_route.startswith("/"):
    _webapp_route = "/" + _webapp_route
WEBAPP_ROUTE: str = _webapp_route

# ---------------------------------------------------------------------------
# Thermal printer (ESC/POS)
# ---------------------------------------------------------------------------
# PRINTER_TYPE: 'serial' — USB→RS232 adapter (e.g. Epson TM-T88II)
#               'network' — TCP/IP, LAN or Bluetooth-to-Serial bridge
#
# Serial:  PRINTER_PORT    = COM port, e.g. COM3
#          PRINTER_BAUDRATE = baud rate (TM-T88II default: 9600)
#
# Network: PRINTER_HOST    = IP address of the printer
#          PRINTER_PORT    = TCP port (standard ESC/POS: 9100)
#
# PRINTER_LINE_WIDTH: characters per line at normal font (80 mm paper = 42)

PRINTER_TYPE: str = os.getenv("PRINTER_TYPE", "serial")
PRINTER_PORT: str = os.getenv("PRINTER_PORT", "COM4")
PRINTER_BAUDRATE: int = int(os.getenv("PRINTER_BAUDRATE", "9600"))
PRINTER_HOST: str = os.getenv("PRINTER_HOST", "192.168.1.100")
PRINTER_LINE_WIDTH: int = int(os.getenv("PRINTER_LINE_WIDTH", "42"))
# Hardware capability of the connected printer/cutter, not receipt content —
# grouped with the other PRINTER_* settings rather than the BON_* ones below.
PRINTER_AUTO_CUT: bool = _bool_env("PRINTER_AUTO_CUT", True)

# ---------------------------------------------------------------------------
# Bon content (visibility/text switches only — the actual layout, e.g.
# separators/bold/uppercase/line-wrapping/paper-feed, still lives in
# bon.yaml until a proper visual designer replaces it — see bon_template.yaml
# for the full reference of what's possible there).
# ---------------------------------------------------------------------------

BON_SHOW_EVENT_NAME: bool = _bool_env("BON_SHOW_EVENT_NAME", True)
BON_SHOW_DATETIME: bool = _bool_env("BON_SHOW_DATETIME", True)
BON_SHOW_PRICE: bool = _bool_env("BON_SHOW_PRICE", True)
BON_FOOTER_TEXT: str = os.getenv("BON_FOOTER_TEXT", "")
BON_SHOW_CASHIER: bool = _bool_env("BON_SHOW_CASHIER", True)
BON_CASHIER_LABEL: str = os.getenv("BON_CASHIER_LABEL", "Kassierer")

# Leaderboard add-on (paid feature).
# LEADERBOARD=true in config.env says the operator wants it on; it only
# actually activates if LEADERBOARD_LICENSE_KEY is also a valid license for
# this INSTALLATION_ID (see licensing.py). When inactive, all leaderboard
# routes are inactive and no points are tracked.
_leaderboard_requested = _bool_env("LEADERBOARD", False)
LEADERBOARD_ENABLED: bool = _leaderboard_requested and licensing.verify_feature(
    "leaderboard", INSTALLATION_ID, os.getenv("LEADERBOARD_LICENSE_KEY", "")
)
if _leaderboard_requested and not LEADERBOARD_ENABLED:
    logger.warning("LEADERBOARD=true but no valid LEADERBOARD_LICENSE_KEY — feature stays disabled")

# Pager add-on (paid feature). Same licensing gate as above.
# When inactive, the pager route/column is inactive and no pager data is tracked.
_pager_requested = _bool_env("PAGER", False)
PAGER_ENABLED: bool = _pager_requested and licensing.verify_feature(
    "pager", INSTALLATION_ID, os.getenv("PAGER_LICENSE_KEY", "")
)
if _pager_requested and not PAGER_ENABLED:
    logger.warning("PAGER=true but no valid PAGER_LICENSE_KEY — feature stays disabled")

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Startup default for the server's own log verbosity (TRACE|DEBUG|INFO|WARNING|ERROR|FATAL).
# Can be changed at runtime without a restart via PUT /api/logs/devices/__server__/level.
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()
