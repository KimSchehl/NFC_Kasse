from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException

from database import get_db
from dependencies import RequestContext, get_active_event, get_current_user
from schemas import BalanceResponse, BookingRequest, BookingResponse, CancelResponse

router = APIRouter(prefix="/api/sales", tags=["sales"])

CANCEL_WINDOW_MINUTES = 5

# Manager permissions — any of these bypasses per-category can_book / can_storno checks.
_MANAGER_PERMS = ('categories.create', 'categories.edit', 'categories.deactivate', 'categories.delete')


def _is_manager(db, user_id: int, event_id: int) -> bool:
    row = db.execute(
        f"""
        SELECT 1 FROM user_permission
        WHERE user_id=? AND event_id=?
        AND permission_id IN ({','.join('?' * len(_MANAGER_PERMS))})
        LIMIT 1
        """,
        (user_id, event_id, *_MANAGER_PERMS),
    ).fetchone()
    return row is not None


def _get_or_create_customer(db, tenant_id: int, nfc_uid: str) -> tuple[int, bool]:
    """
    Returns (customer_id, is_new_customer).
    Creates a new customer row if the NFC UID is unknown for this tenant.
    Must be called within an EXCLUSIVE transaction.
    """
    row = db.execute(
        "SELECT id FROM customer WHERE tenant_id=? AND nfc_uid=?",
        (tenant_id, nfc_uid),
    ).fetchone()
    if row:
        return row["id"], False

    cursor = db.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (?, ?, 0.0)",
        (tenant_id, nfc_uid),
    )
    return cursor.lastrowid, True


# ---------------------------------------------------------------------------
# Balance query — no permission required, all authenticated users can view
# ---------------------------------------------------------------------------

@router.get("/balance/{nfc_uid}", response_model=BalanceResponse)
def get_balance(
    nfc_uid: str,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    tenant_id = current_user["tenant_id"]
    with get_db() as db:
        row = db.execute(
            "SELECT balance FROM customer WHERE tenant_id=? AND nfc_uid=?",
            (tenant_id, nfc_uid),
        ).fetchone()

    if row:
        return BalanceResponse(nfc_uid=nfc_uid, balance=row["balance"], is_new_customer=False)
    return BalanceResponse(nfc_uid=nfc_uid, balance=0.0, is_new_customer=True)


# ---------------------------------------------------------------------------
# Create booking
# ---------------------------------------------------------------------------

@router.post("/", response_model=BookingResponse, status_code=201)
def create_booking(
    body: BookingRequest,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    # BEGIN EXCLUSIVE: balance read + deduction must be atomic to prevent two
    # concurrent bookings from both reading the same pre-deduction balance.
    with get_db(exclusive=True) as db:
        customer_id, is_new = _get_or_create_customer(db, tenant_id, body.nfc_uid)

        # body.product_ids may contain repeated IDs (e.g. [5, 5] = 2 beers).
        # SQL `IN` de-duplicates, so we query only the unique IDs, then use
        # the full product_ids list for pricing and sale row creation.
        unique_ids = list(set(body.product_ids))
        placeholders = ",".join("?" * len(unique_ids))
        products = db.execute(
            f"""
            SELECT p.id, p.price, p.active, p.category_id, c.event_id
            FROM product p
            JOIN category c ON p.category_id = c.id
            WHERE p.id IN ({placeholders}) AND p.deleted=0
            """,
            unique_ids,
        ).fetchall()

        if len(products) != len(unique_ids):
            raise HTTPException(status_code=404, detail="One or more products not found")

        for p in products:
            if p["event_id"] != event_id:
                raise HTTPException(status_code=400, detail="Product does not belong to this event")
            if not p["active"]:
                raise HTTPException(status_code=400, detail=f"Product {p['id']} is not available")

        # Per-category booking permission check.
        # Managers (any categories.* permission) bypass this check.
        if not _is_manager(db, user_id, event_id):
            unique_cat_ids = list(set(p["category_id"] for p in products))
            cat_placeholders = ",".join("?" * len(unique_cat_ids))
            authorized = db.execute(
                f"""
                SELECT COUNT(*) as cnt FROM user_category_access
                WHERE user_id=? AND event_id=? AND category_id IN ({cat_placeholders}) AND can_book=1
                """,
                [user_id, event_id, *unique_cat_ids],
            ).fetchone()["cnt"]

            if authorized < len(unique_cat_ids):
                raise HTTPException(
                    status_code=403,
                    detail="No booking permission for one or more product categories",
                )

        # Build a price lookup keyed by ID, then sum over the full list (with
        # repeats) so quantity is accounted for correctly.
        product_map = {p["id"]: p["price"] for p in products}
        total_price = sum(product_map[pid] for pid in body.product_ids)

        balance_row = db.execute(
            "SELECT balance FROM customer WHERE id=?", (customer_id,)
        ).fetchone()
        current_balance = balance_row["balance"]

        # Negative balances are allowed — the client guards against them with the
        # "Rest Guthaben" check, but we do not enforce it here so a manager can
        # override (e.g. vendor accepting cash debt at the stand).
        new_balance = current_balance - total_price
        db.execute(
            "UPDATE customer SET balance=? WHERE id=?",
            (new_balance, customer_id),
        )

        sale_ids = []
        for product_id in body.product_ids:
            cursor = db.execute(
                """
                INSERT INTO sale (event_id, customer_id, product_id, price_at_sale, booked_by)
                VALUES (?, ?, ?, ?, ?)
                """,
                (event_id, customer_id, product_id, product_map[product_id], user_id),
            )
            sale_ids.append(cursor.lastrowid)

    return BookingResponse(success=True, new_balance=new_balance, sale_ids=sale_ids)


# ---------------------------------------------------------------------------
# Cancel booking
# ---------------------------------------------------------------------------

@router.post("/{sale_id}/cancel", response_model=CancelResponse)
def cancel_booking(
    sale_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db(exclusive=True) as db:
        sale = db.execute(
            """
            SELECT s.*, p.category_id
            FROM sale s
            JOIN product p ON s.product_id = p.id
            WHERE s.id=? AND s.event_id=?
            """,
            (sale_id, event_id),
        ).fetchone()
        if not sale:
            raise HTTPException(status_code=404, detail="Sale not found")
        if sale["cancelled"]:
            raise HTTPException(status_code=400, detail="Sale is already cancelled")

        manager = _is_manager(db, user_id, event_id)

        if manager:
            # Managers can always cancel — no time restriction
            pass
        else:
            # Check per-category storno permissions
            access = db.execute(
                """
                SELECT can_storno_5min, can_storno_unlimited
                FROM user_category_access
                WHERE user_id=? AND event_id=? AND category_id=?
                """,
                (user_id, event_id, sale["category_id"]),
            ).fetchone()

            has_unlimited = access and bool(access["can_storno_unlimited"])
            has_5min = access and bool(access["can_storno_5min"])

            if not has_unlimited and not has_5min:
                raise HTTPException(status_code=403, detail="No cancel permission for this category")

            if not has_unlimited:
                booked_at = datetime.fromisoformat(sale["booked_at"])
                # SQLite stores `datetime('now')` as UTC without timezone suffix.
                if booked_at.tzinfo is None:
                    booked_at = booked_at.replace(tzinfo=timezone.utc)
                elapsed = datetime.now(timezone.utc) - booked_at
                if elapsed > timedelta(minutes=CANCEL_WINDOW_MINUTES):
                    raise HTTPException(
                        status_code=403,
                        detail=f"Cancel window of {CANCEL_WINDOW_MINUTES} minutes has expired",
                    )

        refunded = sale["price_at_sale"]

        db.execute(
            """
            UPDATE sale SET cancelled=1, cancelled_by=?, cancelled_at=datetime('now')
            WHERE id=?
            """,
            (user_id, sale_id),
        )
        db.execute(
            "UPDATE customer SET balance = balance + ? WHERE id=?",
            (refunded, sale["customer_id"]),
        )

    return CancelResponse(success=True, refunded_amount=refunded)
