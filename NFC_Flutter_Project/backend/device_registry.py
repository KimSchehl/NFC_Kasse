"""
Device registry — tracks which client devices exist, when they were last
seen, and whether an admin has forced a specific log level on them.

Hybrid in-memory + persisted, mirroring routers/help.py's _HelpManager
in-memory-dict pattern but without its overwrite problem (this only tracks
per-device metadata, not live connections). /health is polled every 10s per
device — writing to SQLite on every poll would be unnecessary load (exactly
the kind of contention the JSON-lines-over-SQLite decision for logs itself
was already avoiding), so only actual level changes and first-time
registration touch the DB; last_seen lives purely in memory and is
naturally rebuilt as devices keep polling.

The reserved device_id "__server__" represents the backend process itself —
setting its forced_level also live-updates the running root logger.
"""

import logging
import threading
from datetime import datetime, timezone

from database import get_db
from logging_config import LEVEL_NAME_TO_INT

logger = logging.getLogger(__name__)

SERVER_DEVICE_ID = "__server__"

_lock = threading.Lock()
_last_seen: dict[str, dict] = {}       # device_id -> {last_seen_at, platform, label}
_forced_levels: dict[str, str] = {}    # device_id -> level name (incl. SERVER_DEVICE_ID)
_known_labels: dict[str, dict] = {}    # device_id -> {label, platform} from device_log_level table


def load_from_db() -> None:
    """Called once at startup to restore forced levels across restarts."""
    with get_db() as db:
        rows = db.execute(
            "SELECT device_id, label, platform, forced_level FROM device_log_level"
        ).fetchall()
    with _lock:
        for r in rows:
            _known_labels[r["device_id"]] = {"label": r["label"], "platform": r["platform"]}
            if r["forced_level"]:
                _forced_levels[r["device_id"]] = r["forced_level"]
    server_level = _forced_levels.get(SERVER_DEVICE_ID)
    if server_level:
        logging.getLogger().setLevel(LEVEL_NAME_TO_INT.get(server_level, logging.INFO))


def touch(device_id: str, platform: str | None, label: str | None) -> str | None:
    """Called on every /health poll for a known device_id. Returns the
    forced level name for that device, or None if no override is active."""
    with _lock:
        is_new = device_id not in _last_seen and device_id not in _known_labels
        _last_seen[device_id] = {
            "last_seen_at": datetime.now(timezone.utc).isoformat(),
            "platform": platform,
            "label": label,
        }
        forced = _forced_levels.get(device_id)
    if is_new:
        _persist_registration(device_id, platform, label)
    return forced


def _persist_registration(device_id: str, platform: str | None, label: str | None) -> None:
    with get_db() as db:
        db.execute(
            """INSERT OR IGNORE INTO device_log_level (device_id, label, platform, forced_level)
               VALUES (?, ?, ?, NULL)""",
            (device_id, label, platform),
        )
    with _lock:
        _known_labels[device_id] = {"label": label, "platform": platform}


def set_forced_level(device_id: str, level: str | None, admin_user_id: int) -> None:
    with _lock:
        if level is None:
            _forced_levels.pop(device_id, None)
        else:
            _forced_levels[device_id] = level
    with get_db() as db:
        db.execute(
            """INSERT INTO device_log_level (device_id, forced_level, updated_by, updated_at)
               VALUES (?, ?, ?, datetime('now'))
               ON CONFLICT(device_id) DO UPDATE SET
                   forced_level = excluded.forced_level,
                   updated_by   = excluded.updated_by,
                   updated_at   = excluded.updated_at""",
            (device_id, level, admin_user_id),
        )
    if device_id == SERVER_DEVICE_ID:
        logging.getLogger().setLevel(LEVEL_NAME_TO_INT.get(level, logging.INFO) if level else logging.INFO)
        logger.warning("Server log level changed to %s by user_id=%s", level or "(default)", admin_user_id)


def get_device(device_id: str) -> dict:
    with _lock:
        seen = _last_seen.get(device_id, {})
        known = _known_labels.get(device_id, {})
        forced = _forced_levels.get(device_id)
    return {
        "device_id": device_id,
        "label": seen.get("label") or known.get("label"),
        "platform": seen.get("platform") or known.get("platform"),
        "last_seen_at": seen.get("last_seen_at"),
        "forced_level": forced,
        "online": device_id in _last_seen,
    }


def list_devices() -> list[dict]:
    with _lock:
        ids = set(_last_seen) | set(_known_labels) | {SERVER_DEVICE_ID}
    devices = [get_device(d) for d in ids]
    devices.sort(key=lambda d: (d["device_id"] != SERVER_DEVICE_ID, d["device_id"]))
    return devices
