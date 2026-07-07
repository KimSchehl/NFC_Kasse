"""
Bon printing router — books items to the virtual BAR customer, inserts one
print_job row per bon slip, and returns immediately (HTTP 200).

A background daemon thread (_print_worker) processes the queue FIFO:
  pending → printing → done   (or error on printer failure)

This decouples cashier tablets and phones from the physical printer:
  • Any device can submit jobs without waiting for the printer.
  • If the printer is temporarily offline, jobs accumulate and are processed
    when it comes back — without the user having to retry.
  • Booking (BAR chip debit + sale row) always happens synchronously so
    statistics stay up-to-date even if the printer is disconnected.

Supported printer types (PRINTER_TYPE in config.env):
  serial  — USB-to-Serial adapter, e.g. Epson TM-T88II on COM3 (default)
  network — TCP/IP socket, e.g. LAN printer or Bluetooth-to-Serial bridge

The bon layout is driven by bon_template.yaml.  Editing that file takes
effect on the next print — no server restart needed.

Requires the 'bon.drucken' user permission.
"""

import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml
from fastapi import APIRouter, Depends, HTTPException

from config import (
    BAR_CHIP_UID,
    PRINTER_BAUDRATE,
    PRINTER_HOST,
    PRINTER_LINE_WIDTH,
    PRINTER_PORT,
    PRINTER_TYPE,
)
from database import get_db
from dependencies import RequestContext, require_permission
from schemas import PrintBonRequest, PrintBonResponse

router = APIRouter(prefix="/api/print", tags=["print"])

_TEMPLATE_PATH = Path(__file__).parent.parent / "bon_template.yaml"
_worker_started = False

_DEFAULT_TEMPLATE: dict = {
    "header": {
        "show_event_name": True,
        "show_datetime": True,
        "separator_before": True,
        "separator_after": True,
        "separator_char": "-",
    },
    "article": {
        "bold": True,
        "uppercase": False,
        "show_price": True,
        "price_same_line": True,
    },
    "footer": {
        "custom_text": "",
        "show_user": True,
        "user_label": "Kassierer",
        "blank_lines": 3,
        "cut": True,
    },
}


# ---------------------------------------------------------------------------
# Template / Printer helpers
# ---------------------------------------------------------------------------

def _load_template() -> dict:
    """Read bon_template.yaml on every call so edits take effect without restart."""
    if _TEMPLATE_PATH.exists():
        try:
            with open(_TEMPLATE_PATH, encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
            return data
        except Exception:
            pass
    return _DEFAULT_TEMPLATE


def _get_printer():
    """
    Factory — returns an open escpos Printer instance.
    Lazy import so the server starts even when python-escpos is not installed yet.
    """
    if PRINTER_TYPE == "network":
        from escpos.printer import Network  # type: ignore[import]
        port = int(PRINTER_PORT) if PRINTER_PORT.isdigit() else 9100
        return Network(host=PRINTER_HOST, port=port)

    from escpos.printer import Serial  # type: ignore[import]
    return Serial(
        devfile=PRINTER_PORT,
        baudrate=PRINTER_BAUDRATE,
        bytesize=8,
        parity="N",
        stopbits=1,
        timeout=1.0,
    )


def _format_price(amount: float) -> str:
    return f"{amount:.2f} EUR".replace(".", ",")


def _print_bon(
    p,
    template: dict,
    event_name: str,
    dt: datetime,
    product_name: str,
    price: float,
    line_width: int,
    username: str,
) -> None:
    """Print one bon slip to an already-open printer instance."""
    h = template.get("header", _DEFAULT_TEMPLATE["header"])
    a = template.get("article", _DEFAULT_TEMPLATE["article"])
    f = template.get("footer", _DEFAULT_TEMPLATE["footer"])

    sep_char = str(h.get("separator_char", "-"))[0]
    sep = sep_char * line_width

    # Header
    if h.get("separator_before", True):
        p.set(align="left", bold=False)
        p.text(sep + "\n")

    if h.get("show_event_name", True):
        p.set(align="center", bold=True)
        p.text(event_name[:line_width] + "\n")

    if h.get("show_datetime", True):
        p.set(align="center", bold=False)
        p.text(dt.strftime("%d.%m.%Y") + "  " + dt.strftime("%H:%M Uhr") + "\n")

    if h.get("separator_after", True):
        p.set(align="left", bold=False)
        p.text(sep + "\n")

    # Article
    is_bold = bool(a.get("bold", True))
    show_price = bool(a.get("show_price", True))
    same_line = bool(a.get("price_same_line", True))
    display_name = product_name.upper() if a.get("uppercase", False) else product_name

    if show_price and same_line:
        price_str = _format_price(price)
        max_name = line_width - len(price_str) - 1
        if len(display_name) > max_name:
            p.set(align="left", bold=is_bold)
            p.text(display_name + "\n")
            p.set(align="right", bold=False)
            p.text(price_str + "\n")
        else:
            padding = " " * (line_width - len(display_name) - len(price_str))
            p.set(align="left", bold=is_bold)
            p.text(display_name + padding + price_str + "\n")
    elif show_price:
        p.set(align="left", bold=is_bold)
        p.text(display_name + "\n")
        p.set(align="right", bold=False)
        p.text(_format_price(price) + "\n")
    else:
        p.set(align="left", bold=is_bold)
        p.text(display_name + "\n")

    # Footer
    p.set(align="left", bold=False)

    custom = str(f.get("custom_text", "")).strip()
    if custom:
        p.text(custom + "\n")

    if f.get("show_user", True) and username:
        label = str(f.get("user_label", "Kassierer")).strip()
        user_line = f"{label}: {username}" if label else username
        p.text(user_line[:line_width] + "\n")

    blank_lines = max(0, int(f.get("blank_lines", 3)))
    p.text("\n" * blank_lines)

    if f.get("cut", True):
        p.cut()


# ---------------------------------------------------------------------------
# Background print worker
# ---------------------------------------------------------------------------

def _reset_stuck_jobs() -> None:
    """On startup: jobs left in 'printing' state (from a crash) go back to pending."""
    with get_db() as db:
        db.execute("UPDATE print_job SET status = 'pending' WHERE status = 'printing'")


def _print_worker() -> None:
    """
    Daemon thread — polls print_job for pending rows and prints them FIFO.

    The printer is opened ONCE per batch and kept open until the queue is empty
    or a print error occurs.  This avoids the PermissionError that arises when
    the OS hasn't released the COM port before the next job tries to reopen it
    (common when multiple bons are queued within milliseconds of each other).

    On printer-open failure (offline/busy) jobs stay 'pending' and the worker
    retries after 2 s — no job is ever marked 'error' for a connect failure.
    On mid-print failure the offending job is marked 'error', the port is
    closed, and the worker pauses 2 s before the next attempt.
    """
    _reset_stuck_jobs()

    while True:
        # Fast-path: skip printer open if nothing is pending
        with get_db() as db:
            pending = db.execute(
                "SELECT COUNT(*) FROM print_job WHERE status = 'pending'"
            ).fetchone()[0]

        if not pending:
            time.sleep(0.3)
            continue

        # Open printer once for the whole batch
        try:
            p = _get_printer()
        except Exception:
            time.sleep(2.0)
            continue

        try:
            while True:
                with get_db() as db:
                    job = db.execute(
                        "SELECT * FROM print_job WHERE status = 'pending' ORDER BY created_at, id LIMIT 1"
                    ).fetchone()

                if not job:
                    break  # Queue drained — close printer and go back to sleep

                job = dict(job)
                job_id = job["id"]

                # Claim atomically
                with get_db(exclusive=True) as db:
                    db.execute(
                        "UPDATE print_job SET status = 'printing' WHERE id = ? AND status = 'pending'",
                        (job_id,),
                    )

                try:
                    dt = datetime.fromisoformat(job["created_at"]).replace(tzinfo=timezone.utc).astimezone()
                    template = _load_template()

                    event_name = job["event_name"]
                    override = str(template.get("header", {}).get("event_name_override", "")).strip()
                    if override:
                        event_name = override

                    _print_bon(
                        p, template,
                        event_name, dt,
                        job["product_name"], job["price"],
                        PRINTER_LINE_WIDTH, job["username"],
                    )

                    with get_db() as db:
                        db.execute(
                            "UPDATE print_job SET status = 'done', processed_at = datetime('now') WHERE id = ?",
                            (job_id,),
                        )

                except Exception as exc:
                    with get_db() as db:
                        db.execute(
                            "UPDATE print_job SET status = 'error', error_msg = ? WHERE id = ?",
                            (str(exc)[:500], job_id),
                        )
                    time.sleep(2.0)
                    break  # Close printer; outer loop will reopen on next attempt

        finally:
            try:
                p.close()
            except Exception:
                pass


def start_worker() -> None:
    """Start the print-queue worker thread (idempotent — safe to call multiple times)."""
    global _worker_started
    if _worker_started:
        return
    _worker_started = True
    t = threading.Thread(target=_print_worker, daemon=True, name="print-worker")
    t.start()


# ---------------------------------------------------------------------------
# HTTP endpoint
# ---------------------------------------------------------------------------

@router.post("/bon", response_model=PrintBonResponse)
def print_bon(
    body: PrintBonRequest,
    ctx: RequestContext = Depends(require_permission("bon.drucken")),
):
    """
    Books all cart items to the BAR virtual chip and queues one print job
    per unit.  Returns immediately — printing happens asynchronously.

    Response bons_printed = number of jobs queued (not yet printed).
    Requires 'bon.drucken' permission.
    """
    user_id = ctx["user"]["id"]
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    event_name = ctx["event"]["name"]
    username: str = ctx["user"].get("display_name") or ctx["user"]["username"]

    sale_ids: list[int] = []
    product_map: dict[int, dict] = {}

    with get_db(exclusive=True) as db:
        bar_row = db.execute(
            "SELECT id FROM customer WHERE tenant_id = ? AND nfc_uid = ?",
            (tenant_id, BAR_CHIP_UID),
        ).fetchone()
        if not bar_row:
            raise HTTPException(
                status_code=500,
                detail="BAR-Chip nicht gefunden. Bitte Datenbank neu initialisieren (init_db.py).",
            )
        bar_customer_id = bar_row["id"]

        # Expand item list to one entry per unit
        product_ids_flat: list[int] = []
        for item in body.items:
            product_ids_flat.extend([item.product_id] * max(1, item.quantity))

        unique_ids = list(set(product_ids_flat))
        ph = ",".join("?" * len(unique_ids))
        products = db.execute(
            f"SELECT p.id, p.name, p.price "
            f"FROM product p "
            f"JOIN category c ON p.category_id = c.id "
            f"WHERE p.id IN ({ph}) AND p.deleted = 0 AND p.active = 1 AND c.event_id = ?",
            [*unique_ids, event_id],
        ).fetchall()

        if len(products) != len(unique_ids):
            found_ids = {p["id"] for p in products}
            missing = [pid for pid in unique_ids if pid not in found_ids]
            raise HTTPException(
                status_code=404,
                detail=f"Unbekannte oder inaktive Artikel-IDs: {missing}",
            )

        product_map = {p["id"]: {"name": p["name"], "price": p["price"]} for p in products}
        total_price = sum(product_map[pid]["price"] for pid in product_ids_flat)

        # Debit BAR chip (balance intentionally goes negative — it's a cash-sales counter)
        db.execute(
            "UPDATE customer SET balance = balance - ? WHERE id = ?",
            (total_price, bar_customer_id),
        )

        # Insert sale rows and print jobs in one transaction
        jobs_queued = 0
        sale_idx = 0
        for item in body.items:
            info = product_map[item.product_id]
            for _ in range(max(1, item.quantity)):
                cursor = db.execute(
                    "INSERT INTO sale (event_id, customer_id, product_id, price_at_sale, booked_by) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (event_id, bar_customer_id, item.product_id, info["price"], user_id),
                )
                sale_id = cursor.lastrowid
                sale_ids.append(sale_id)

                db.execute(
                    "INSERT INTO print_job "
                    "(event_id, sale_id, username, event_name, product_name, price) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (event_id, sale_id, username, event_name, info["name"], info["price"]),
                )
                jobs_queued += 1
                sale_idx += 1

    return PrintBonResponse(success=True, bons_printed=jobs_queued, sale_ids=sale_ids)
