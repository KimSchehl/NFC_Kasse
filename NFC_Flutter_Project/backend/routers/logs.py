import json
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query

import device_registry
from dependencies import RequestContext, get_current_user_optional, require_permission
from logging_config import LEVEL_NAME_TO_INT, log_dir
from schemas import (
    DeviceInfo,
    LogEntryOut,
    LogIngestRequest,
    LogIngestResponse,
    LogQueryResponse,
    SetDeviceLevelRequest,
)

router = APIRouter(prefix="/api/logs", tags=["logs"])


# ---------------------------------------------------------------------------
# Ingest — no permission required, must work for unauthenticated/pre-login
# clients too (e.g. a login-failure log). Each client already filtered
# entries to its own configured level before buffering them, so entries are
# accepted as-is; re-filtering against the server's own level would conflate
# two independent knobs (see logging_config.py's "client.*" logger note).
# ---------------------------------------------------------------------------

@router.post("/ingest", response_model=LogIngestResponse)
def ingest(
    body: LogIngestRequest,
    user: dict | None = Depends(get_current_user_optional),
):
    accepted = 0
    for entry in body.entries:
        level = LEVEL_NAME_TO_INT.get(entry.level.upper(), logging.INFO)
        logging.getLogger(f"client.{entry.logger}").log(
            level,
            entry.message[:4000],
            extra={
                "ts": entry.ts,
                "trace_id": entry.trace_id,
                "origin": "client",
                "device_id": body.device_id,
                "user_id": user["id"] if user else None,
                "username": user["username"] if user else None,
                "exception": entry.exception,
            },
        )
        accepted += 1
    return LogIngestResponse(accepted=accepted)


# ---------------------------------------------------------------------------
# Query — file-based, not SQL. since/until determine which
# kasse_YYYY-MM-DD_HH.log files are candidates; each is parsed line-by-line
# and filtered in Python. Sorted by the `ts` field (not file order — a
# client-shipped entry can lag its true timestamp by up to the client's ship
# interval). Response is {items, has_more}, not {items, total}: an exact
# count would require scanning the whole time window even for page 1.
# ---------------------------------------------------------------------------

def _to_local_naive(dt: datetime) -> datetime:
    """Rotation files are named using local wall-clock time
    (_TopOfHourHandler._filename_for_now(), unchanged pre-existing behavior) -
    since/until arrive UTC-aware, so they must be converted to local-naive
    before building filenames, or the wrong hour gets requested whenever the
    server isn't running in UTC."""
    if dt.tzinfo is not None:
        dt = dt.astimezone().replace(tzinfo=None)
    return dt


def _candidate_files(since: datetime, until: datetime) -> list:
    d = log_dir()
    hour = _to_local_naive(since).replace(minute=0, second=0, microsecond=0)
    end = _to_local_naive(until)
    files = []
    while hour <= end:
        p = d / hour.strftime("kasse_%Y-%m-%d_%H.log")
        if p.exists():
            files.append(p)
        hour += timedelta(hours=1)
    return files


@router.get("/query", response_model=LogQueryResponse)
def query_logs(
    level: str | None = Query(None, description="Minimum level, e.g. WARNING"),
    origin: str | None = Query(None),
    device_id: str | None = Query(None),
    trace_id: str | None = Query(None),
    logger_name: str | None = Query(None, alias="logger"),
    q: str | None = Query(None, description="Substring search in message"),
    since: str | None = Query(None),
    until: str | None = Query(None),
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    ctx: RequestContext = Depends(require_permission("logs.view")),
):
    now = datetime.now(timezone.utc)
    until_dt = datetime.fromisoformat(until) if until else now
    since_dt = datetime.fromisoformat(since) if since else until_dt - timedelta(hours=24)
    # 168h = the same 7-day retention window the rotation itself enforces
    since_dt = max(since_dt, until_dt - timedelta(hours=168))

    min_level = LEVEL_NAME_TO_INT.get(level.upper()) if level else None

    matches: list[dict] = []
    for path in _candidate_files(since_dt, until_dt):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue  # legacy plain-text line or malformed — skip
                if not isinstance(entry, dict) or "ts" not in entry:
                    continue
                if min_level is not None and LEVEL_NAME_TO_INT.get(entry.get("level", "INFO"), 0) < min_level:
                    continue
                if origin and entry.get("origin") != origin:
                    continue
                if device_id and entry.get("device_id") != device_id:
                    continue
                if trace_id and entry.get("trace_id") != trace_id:
                    continue
                if logger_name and logger_name not in (entry.get("logger") or ""):
                    continue
                if q and q.lower() not in (entry.get("message") or "").lower():
                    continue
                matches.append(entry)

    matches.sort(key=lambda e: e.get("ts", ""), reverse=True)
    page = matches[offset : offset + limit]
    has_more = offset + limit < len(matches)

    items = []
    for e in page:
        try:
            items.append(LogEntryOut(**e))
        except (TypeError, ValueError):
            continue  # unexpected shape — skip rather than fail the whole page

    return LogQueryResponse(items=items, has_more=has_more)


# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------

@router.get("/devices", response_model=list[DeviceInfo])
def list_devices(ctx: RequestContext = Depends(require_permission("logs.configure"))):
    return device_registry.list_devices()


@router.put("/devices/{device_id}/level", response_model=DeviceInfo)
def set_device_level(
    device_id: str,
    body: SetDeviceLevelRequest,
    ctx: RequestContext = Depends(require_permission("logs.configure")),
):
    device_registry.set_forced_level(device_id, body.level, ctx["user"]["id"])
    return device_registry.get_device(device_id)
