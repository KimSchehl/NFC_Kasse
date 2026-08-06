"""
Structured logging setup — JSON-lines files, hourly rotation.

Reuses main.py's existing _TopOfHourHandler (rotation/retention behavior
unchanged) but writes one JSON object per line instead of plain text, and
fixes a pre-existing bug: the root logger never had an explicit level set
anywhere, so it silently defaulted to WARNING — any logger.info()/.debug()
call would have been dropped before this.

Contextvars carry per-request identifiers (trace_id, device_id, path, method,
user) from middleware.py into every LogRecord emitted during that request,
without threading them through every function signature.
"""

import contextvars
import json
import logging
import logging.handlers
from datetime import datetime, timezone
from pathlib import Path

from config import LOG_LEVEL

# ---------------------------------------------------------------------------
# Extra levels: TRACE below DEBUG, FATAL as the display name for CRITICAL
# ---------------------------------------------------------------------------

TRACE = 5
logging.addLevelName(TRACE, "TRACE")
logging.addLevelName(logging.CRITICAL, "FATAL")


def _trace(self: logging.Logger, msg: object, *args, **kwargs) -> None:
    if self.isEnabledFor(TRACE):
        self._log(TRACE, msg, args, **kwargs)


logging.Logger.trace = _trace  # type: ignore[attr-defined]

LEVEL_NAME_TO_INT = {
    "TRACE": TRACE,
    "DEBUG": logging.DEBUG,
    "INFO": logging.INFO,
    "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
    "FATAL": logging.CRITICAL,
}

# ---------------------------------------------------------------------------
# Contextvars — set by middleware.py per request, read by ContextFilter
# ---------------------------------------------------------------------------

trace_id_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar("trace_id", default=None)
device_id_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar("device_id", default=None)
path_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar("path", default=None)
method_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar("method", default=None)
user_ctx: contextvars.ContextVar[dict | None] = contextvars.ContextVar("user", default=None)


class ContextFilter(logging.Filter):
    """Stamps request-scoped identifiers onto every record that doesn't
    already carry an explicit value (e.g. the /logs/ingest endpoint sets
    origin/device_id/user_id explicitly per shipped entry — those win)."""

    def filter(self, record: logging.LogRecord) -> bool:
        user = user_ctx.get()
        if not hasattr(record, "trace_id"):
            record.trace_id = trace_id_ctx.get()
        if not hasattr(record, "device_id"):
            record.device_id = device_id_ctx.get()
        if not hasattr(record, "path"):
            record.path = path_ctx.get()
        if not hasattr(record, "method"):
            record.method = method_ctx.get()
        if not hasattr(record, "origin"):
            record.origin = "server"
        if not hasattr(record, "user_id"):
            record.user_id = user["id"] if user else None
        if not hasattr(record, "username"):
            record.username = user["username"] if user else None
        if not hasattr(record, "status_code"):
            record.status_code = None
        if not hasattr(record, "exception"):
            record.exception = None
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        # Prefer an explicit client-supplied timestamp (set via `extra={"ts": ...}`,
        # used when ingesting a shipped batch) over the record's own creation time,
        # so a delayed/retried client log entry keeps its true original event time.
        ts = getattr(record, "ts", None) or datetime.fromtimestamp(
            record.created, tz=timezone.utc
        ).isoformat(timespec="milliseconds")
        payload = {
            "ts": ts,
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "trace_id": getattr(record, "trace_id", None),
            "origin": getattr(record, "origin", "server"),
            "device_id": getattr(record, "device_id", None),
            "user_id": getattr(record, "user_id", None),
            "username": getattr(record, "username", None),
            "path": getattr(record, "path", None),
            "method": getattr(record, "method", None),
            "status_code": getattr(record, "status_code", None),
            "exception": getattr(record, "exception", None),
        }
        if record.exc_info and payload["exception"] is None:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


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
        return datetime.now().strftime("kasse_%Y-%m-%d_%H.log")

    @staticmethod
    def _next_full_hour() -> int:
        import time
        t = int(time.time())
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


def log_dir() -> Path:
    return Path(__file__).parent / "logs"


def setup_logging() -> None:
    d = log_dir()
    d.mkdir(exist_ok=True)

    file_handler = _TopOfHourHandler(log_dir=d, backup_count=168)
    file_handler.setFormatter(JsonFormatter())
    file_handler.addFilter(ContextFilter())

    root = logging.getLogger()
    root.addHandler(file_handler)
    root.setLevel(LEVEL_NAME_TO_INT.get(LOG_LEVEL, logging.INFO))

    # Client-shipped entries were already filtered against that device's own
    # level before being sent — re-filtering them against the server's root
    # level here would conflate two independent knobs, so the "client.*"
    # logger subtree always accepts everything handed to it.
    logging.getLogger("client").setLevel(TRACE)

    # uvicorn --reload watches this whole directory (including backend/logs/
    # itself) via watchfiles, which logs an INFO "N changes detected" line on
    # every filesystem event through the stdlib logging module. Since every
    # log write is itself such an event, leaving this at the root's INFO
    # level creates a self-sustaining feedback loop that floods the log file
    # with nothing but its own writes. --reload is dev-only, but this is
    # cheap insurance regardless of how the server was started.
    logging.getLogger("watchfiles").setLevel(logging.WARNING)
