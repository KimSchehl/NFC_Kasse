"""
Kiosk endpoint — self-service balance and transaction lookup for guests.

Architecture:
  GET /api/kiosk/chip/{nfc_uid}   — returns balance + full transaction history
                                    (auth required: kiosk user must be logged in)

The kiosk user has the 'kiosk.access' permission. The Flutter app routes such
users to KioskScreen instead of MainShell.
"""

from datetime import timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from config import CHIP_DEPOSIT, LEADERBOARD_ENABLED
from database import get_db
from dependencies import get_active_event, get_current_user

if LEADERBOARD_ENABLED:
    from routers import leaderboard as _leaderboard

router = APIRouter(prefix="/api/kiosk", tags=["kiosk"])


class _ChipSettingsBody(BaseModel):
    name: str = Field("", max_length=20)
    leaderboard_opt_in: bool = False


@router.put("/chip/{nfc_uid}/name")
def set_chip_name(
    nfc_uid: str,
    body: _ChipSettingsBody,
    current_user: dict = Depends(get_current_user),
):
    """Sets/clears the customer-supplied name and leaderboard opt-in for a chip."""
    tenant_id = current_user["tenant_id"]
    name = body.name.strip() or None  # empty string → NULL
    with get_db() as db:
        customer = db.execute(
            "SELECT id FROM customer WHERE tenant_id=? AND nfc_uid=?",
            (tenant_id, nfc_uid),
        ).fetchone()
        if not customer:
            raise HTTPException(status_code=404, detail="Chip not found")
        db.execute(
            "UPDATE customer SET customer_name=? WHERE id=?",
            (name, customer["id"]),
        )
        if LEADERBOARD_ENABLED:
            db.execute("""
                INSERT INTO leaderboard_score (customer_id, points, opt_in)
                VALUES (?, 0, ?)
                ON CONFLICT(customer_id) DO UPDATE SET
                    opt_in     = excluded.opt_in,
                    updated_at = datetime('now')
            """, (customer["id"], 1 if body.leaderboard_opt_in else 0))
    if LEADERBOARD_ENABLED:
        _leaderboard.check_and_notify()
    return {"ok": True, "name": name, "leaderboard_opt_in": body.leaderboard_opt_in}


@router.get("/chip/{nfc_uid}")
def kiosk_chip_info(
    nfc_uid: str,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """Returns current balance and full transaction history for a chip."""
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        customer = db.execute(
            "SELECT id, balance, customer_name, is_available FROM customer WHERE tenant_id=? AND nfc_uid=?",
            (tenant_id, nfc_uid),
        ).fetchone()

        if not customer:
            return {
                "nfc_uid": nfc_uid,
                "balance": 0.0,
                "chip_deposit": CHIP_DEPOSIT,
                "customer_name": None,
                "leaderboard_opt_in": False,
                "total_points": 0,
                "is_new_customer": True,
                "transactions": [],
            }

        customer_id = customer["id"]

        # Leaderboard score from dedicated table
        if LEADERBOARD_ENABLED:
            lb = db.execute(
                "SELECT points, opt_in FROM leaderboard_score WHERE customer_id=?",
                (customer_id,),
            ).fetchone()
            total_points = lb["points"] if lb else 0
            leaderboard_opt_in = bool(lb["opt_in"]) if lb else False
        else:
            total_points = 0
            leaderboard_opt_in = False

        # Sales — join product for name, join user for display name
        sales = db.execute(
            """
            SELECT
                s.id,
                s.price_at_sale AS price,
                s.booked_at,
                s.cancelled,
                s.cancelled_at,
                p.name  AS product_name,
                u.display_name AS booked_by_display,
                u.username     AS booked_by_user
            FROM sale s
            JOIN product p ON s.product_id = p.id
            JOIN user   u ON s.booked_by  = u.id
            WHERE s.customer_id = ? AND s.event_id = ?
            ORDER BY s.booked_at DESC
            """,
            (customer_id, event_id),
        ).fetchall()

        # Topups
        topups = db.execute(
            """
            SELECT
                t.id,
                t.amount,
                t.booked_at,
                t.cancelled,
                t.cancelled_at,
                u.display_name AS booked_by_display,
                u.username     AS booked_by_user
            FROM topup t
            JOIN user u ON t.booked_by = u.id
            WHERE t.customer_id = ? AND t.event_id = ?
            ORDER BY t.booked_at DESC
            """,
            (customer_id, event_id),
        ).fetchall()

    def _to_local_iso(raw: str) -> str:
        from datetime import datetime
        dt = datetime.fromisoformat(raw).replace(tzinfo=timezone.utc).astimezone()
        return dt.isoformat()

    transactions = []

    for s in sales:
        transactions.append({
            "type": "sale",
            "id": s["id"],
            "description": s["product_name"],
            "price": -s["price"],          # negative = money out
            "booked_at": _to_local_iso(s["booked_at"]),
            "cancelled": bool(s["cancelled"]),
            "cancelled_at": _to_local_iso(s["cancelled_at"]) if s["cancelled_at"] else None,
            "booked_by": s["booked_by_display"] or s["booked_by_user"],
        })

    for t in topups:
        transactions.append({
            "type": "topup",
            "id": t["id"],
            "description": "Aufladung",
            "price": t["amount"],           # positive = money in
            "booked_at": _to_local_iso(t["booked_at"]),
            "cancelled": bool(t["cancelled"]),
            "cancelled_at": _to_local_iso(t["cancelled_at"]) if t["cancelled_at"] else None,
            "booked_by": t["booked_by_display"] or t["booked_by_user"],
        })

    # Merge and sort newest first
    transactions.sort(key=lambda x: x["booked_at"], reverse=True)

    return {
        "nfc_uid": nfc_uid,
        "balance": customer["balance"],
        "chip_deposit": CHIP_DEPOSIT,
        "customer_name": customer["customer_name"],
        "leaderboard_opt_in": leaderboard_opt_in,
        "total_points": total_points,
        "is_new_customer": bool(customer["is_available"]),
        "transactions": transactions,
    }
