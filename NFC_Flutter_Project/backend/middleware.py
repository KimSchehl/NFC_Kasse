"""
Trace-id / device-id middleware — pure ASGI, not BaseHTTPMiddleware.

BaseHTTPMiddleware has known interaction issues with StreamingResponse in
some Starlette versions, and stats.py's CSV export uses exactly that — pure
ASGI sidesteps the issue entirely.

Gives us, for free: trace-id propagation (+ echoed back in the response),
device-id capture for every request (not just /health), a per-request
access-log-equivalent line (uvicorn's own "uvicorn"/"uvicorn.access" loggers
have propagate=False, so today nothing like this reaches the log file at
all), and a safety net that turns today's silent 500s into a logged FATAL
line with a full traceback.
"""

import logging
import time
import uuid

from starlette.datastructures import MutableHeaders
from starlette.requests import Request

from logging_config import TRACE, device_id_ctx, method_ctx, path_ctx, trace_id_ctx, user_ctx

logger = logging.getLogger("middleware")


class TraceIdMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request = Request(scope, receive)
        trace_id = request.headers.get("x-trace-id") or uuid.uuid4().hex
        device_id = request.headers.get("x-device-id")

        trace_id_ctx.set(trace_id)
        device_id_ctx.set(device_id)
        path_ctx.set(request.url.path)
        method_ctx.set(request.method)
        user_ctx.set(None)  # populated later by dependencies.get_current_user, if this request hits it

        status_holder = {"code": 500}

        async def send_wrapper(message):
            if message["type"] == "http.response.start":
                status_holder["code"] = message["status"]
                headers = MutableHeaders(scope=message)
                headers.append("x-trace-id", trace_id)
            await send(message)

        start = time.monotonic()
        try:
            await self.app(scope, receive, send_wrapper)
        except Exception:
            logger.critical(
                "Unhandled exception in %s %s", request.method, request.url.path, exc_info=True
            )
            raise
        finally:
            elapsed_ms = (time.monotonic() - start) * 1000
            code = status_holder["code"]
            if request.url.path == "/health":
                level = TRACE
            elif code < 400:
                level = logging.INFO
            elif code < 500:
                level = logging.WARNING
            else:
                level = logging.ERROR
            logger.log(
                level,
                "%s %s -> %d (%.0fms)",
                request.method,
                request.url.path,
                code,
                elapsed_ms,
                extra={"status_code": code},
            )
