from fastapi import APIRouter, Depends, HTTPException

from database import get_db
from dependencies import RequestContext, require_permission
from schemas import PayoutResponse, TopupRequest, TopupResponse

router = APIRouter(prefix="/api/topup", tags=["topup"])


def _get_or_create_customer(db, tenant_id: int, nfc_uid: str) -> int:
    """Returns customer_id, creating the customer if the UID is new."""
    row = db.execute(
        "SELECT id FROM customer WHERE tenant_id=? AND nfc_uid=?",
        (tenant_id, nfc_uid),
    ).fetchone()
    if row:
        return row["id"]
    cursor = db.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (?, ?, 0.0)",
        (tenant_id, nfc_uid),
    )
    return cursor.lastrowid


# ---------------------------------------------------------------------------
# Top-up
# ---------------------------------------------------------------------------

@router.post("/", response_model=TopupResponse, status_code=201)
def topup(
    body: TopupRequest,
    ctx: RequestContext = Depends(require_permission("guthaben.topup")),
):
    user_id = ctx["user"]["id"]
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]

    with get_db(exclusive=True) as db:
        customer_id = _get_or_create_customer(db, tenant_id, body.nfc_uid)

        db.execute(
            """
            INSERT INTO topup (event_id, customer_id, amount, payment_method, booked_by)
            VALUES (?, ?, ?, ?, ?)
            """,
            (event_id, customer_id, body.amount, body.payment_method, user_id),
        )
        db.execute(
            "UPDATE customer SET balance = balance + ? WHERE id=?",
            (body.amount, customer_id),
        )
        new_balance = db.execute(
            "SELECT balance FROM customer WHERE id=?", (customer_id,)
        ).fetchone()["balance"]

    return TopupResponse(success=True, new_balance=new_balance)


# ---------------------------------------------------------------------------
# Payout — returns full balance to guest, records as negative topup
# ---------------------------------------------------------------------------

@router.post("/payout/{nfc_uid}", response_model=PayoutResponse)
def payout(
    nfc_uid: str,
    ctx: RequestContext = Depends(require_permission("guthaben.payout")),
):
    user_id = ctx["user"]["id"]
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]

    with get_db(exclusive=True) as db:
        customer = db.execute(
            "SELECT id, balance FROM customer WHERE tenant_id=? AND nfc_uid=?",
            (tenant_id, nfc_uid),
        ).fetchone()
        if not customer:
            raise HTTPException(status_code=404, detail="Customer not found")

        current_balance = customer["balance"]
        if current_balance <= 0:
            raise HTTPException(status_code=400, detail="No balance to pay out")

        # Record the payout as a negative amount topup row so the audit trail
        # shows who paid out how much and when, without a separate table.
        db.execute(
            """
            INSERT INTO topup (event_id, customer_id, amount, payment_method, booked_by)
            VALUES (?, ?, ?, 'payout', ?)
            """,
            (event_id, customer["id"], -current_balance, user_id),
        )
        db.execute(
            "UPDATE customer SET balance=0.0 WHERE id=?",
            (customer["id"],),
        )

    return PayoutResponse(success=True, paid_out=current_balance, new_balance=0.0)
