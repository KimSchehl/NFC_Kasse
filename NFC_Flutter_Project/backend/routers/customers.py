from fastapi import APIRouter, Depends

from config import CHIP_DEPOSIT
from database import get_db
from dependencies import RequestContext, require_permission
from schemas import ChipResponse, ChipSummaryResponse

router = APIRouter(prefix="/api/customers", tags=["customers"])


@router.get("/", response_model=list[ChipResponse])
def list_chips(
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    """All registered chips for the tenant, newest/highest balance first."""
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        rows = db.execute(
            """
            SELECT
                c.nfc_uid,
                c.balance,
                c.is_available,
                (
                    SELECT s.booked_at FROM sale s
                    WHERE s.customer_id = c.id
                    ORDER BY s.booked_at DESC LIMIT 1
                ) AS last_booked_at,
                (
                    SELECT p.name FROM sale s
                    JOIN product p ON s.product_id = p.id
                    WHERE s.customer_id = c.id
                    ORDER BY s.booked_at DESC LIMIT 1
                ) AS last_product_name
            FROM customer c
            WHERE c.tenant_id = ?
            ORDER BY c.balance DESC, c.nfc_uid
            """,
            (tenant_id,),
        ).fetchall()
    return [ChipResponse(**dict(r)) for r in rows]


@router.get("/summary", response_model=ChipSummaryResponse)
def chip_summary(
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    """Aggregate balance overview for the current event."""
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    with get_db() as db:
        chip_row = db.execute(
            """
            SELECT
                COUNT(*) AS total_chips,
                COUNT(CASE WHEN is_available = 0 THEN 1 END) AS active_chips,
                COALESCE(SUM(balance), 0.0) AS total_balance
            FROM customer
            WHERE tenant_id = ?
            """,
            (tenant_id,),
        ).fetchone()

        topup_row = db.execute(
            """
            SELECT
                COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0.0) AS total_topup,
                COALESCE(ABS(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END)), 0.0) AS total_payout
            FROM topup
            WHERE event_id = ?
            """,
            (event_id,),
        ).fetchone()

        # Aufladungen die als Artikel gebucht wurden (negative price_at_sale)
        # gehen in die sale-Tabelle, nicht in topup — beide Quellen addieren.
        article_topup_row = db.execute(
            """
            SELECT COALESCE(SUM(ABS(price_at_sale)), 0.0) AS topup_from_articles
            FROM sale
            WHERE event_id = ? AND cancelled = 0 AND price_at_sale < 0
            """,
            (event_id,),
        ).fetchone()

    return ChipSummaryResponse(
        total_chips=chip_row["total_chips"],
        active_chips=chip_row["active_chips"],
        total_balance=chip_row["total_balance"],
        pending_pfand=chip_row["active_chips"] * CHIP_DEPOSIT,
        total_topup=topup_row["total_topup"] + article_topup_row["topup_from_articles"],
        total_payout=topup_row["total_payout"],
    )
