import logging
import os

import licensing

logger = logging.getLogger(__name__)

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

# Leaderboard add-on (paid feature).
# LEADERBOARD=true in config.env says the operator wants it on; it only
# actually activates if LEADERBOARD_LICENSE_KEY is also a valid license for
# this INSTALLATION_ID (see licensing.py). When inactive, all leaderboard
# routes are inactive and no points are tracked.
_leaderboard_requested = os.getenv("LEADERBOARD", "false").lower() in ("true", "1", "yes")
LEADERBOARD_ENABLED: bool = _leaderboard_requested and licensing.verify_feature(
    "leaderboard", INSTALLATION_ID, os.getenv("LEADERBOARD_LICENSE_KEY", "")
)
if _leaderboard_requested and not LEADERBOARD_ENABLED:
    logger.warning("LEADERBOARD=true but no valid LEADERBOARD_LICENSE_KEY — feature stays disabled")

# Pager add-on (paid feature). Same licensing gate as above.
# When inactive, the pager route/column is inactive and no pager data is tracked.
_pager_requested = os.getenv("PAGER", "false").lower() in ("true", "1", "yes")
PAGER_ENABLED: bool = _pager_requested and licensing.verify_feature(
    "pager", INSTALLATION_ID, os.getenv("PAGER_LICENSE_KEY", "")
)
if _pager_requested and not PAGER_ENABLED:
    logger.warning("PAGER=true but no valid PAGER_LICENSE_KEY — feature stays disabled")

PRINTER_TYPE: str = os.getenv("PRINTER_TYPE", "serial")
PRINTER_PORT: str = os.getenv("PRINTER_PORT", "COM4")
PRINTER_BAUDRATE: int = int(os.getenv("PRINTER_BAUDRATE", "9600"))
PRINTER_HOST: str = os.getenv("PRINTER_HOST", "192.168.1.100")
PRINTER_LINE_WIDTH: int = int(os.getenv("PRINTER_LINE_WIDTH", "42"))

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Startup default for the server's own log verbosity (TRACE|DEBUG|INFO|WARNING|ERROR|FATAL).
# Can be changed at runtime without a restart via PUT /api/logs/devices/__server__/level.
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()
