from fastapi import APIRouter, Depends, Query

from config import BAR_CHIP_UID, CHIP_DEPOSIT
from database import get_db
from dependencies import RequestContext, require_permission
from routers.stats import _period_time_bounds
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
            WHERE c.tenant_id = ? AND c.nfc_uid != ?
            ORDER BY c.balance DESC, c.nfc_uid
            """,
            (tenant_id, BAR_CHIP_UID),
        ).fetchall()
    return [ChipResponse(**dict(r)) for r in rows]


@router.get("/summary", response_model=ChipSummaryResponse)
def chip_summary(
    period_ids: str | None = Query(None, description="Comma-separated period IDs to scope topup/sale totals"),
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    """Aggregate balance overview. total_topup/total_payout respect period_ids if given."""
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    with get_db() as db:
        # Current chip counts and balance are always event-wide (live state).
        # BAR virtual chip is excluded — it's not a real guest chip.
        chip_row = db.execute(
            """
            SELECT
                COUNT(*) AS total_chips,
                COUNT(CASE WHEN is_available = 0 THEN 1 END) AS active_chips,
                COALESCE(SUM(balance), 0.0) AS total_balance
            FROM customer
            WHERE tenant_id = ? AND nfc_uid != ?
            """,
            (tenant_id, BAR_CHIP_UID),
        ).fetchone()

        # Build optional time bounds from period selection.
        min_start, max_end = _period_time_bounds(db, event_id, period_ids)
        time_clauses: list[str] = []
        time_params: list = []
        if min_start:
            time_clauses.append("booked_at >= ?")
            time_params.append(min_start)
        if max_end:
            time_clauses.append("booked_at <= ?")
            time_params.append(max_end)
        time_where = (" AND " + " AND ".join(time_clauses)) if time_clauses else ""

        topup_row = db.execute(
            f"""
            SELECT
                COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0.0) AS total_topup,
                COALESCE(ABS(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END)), 0.0) AS total_payout
            FROM topup
            WHERE event_id = ? AND cancelled = 0 {time_where}
            """,
            (event_id, *time_params),
        ).fetchone()

        # Aufladungen die als Artikel gebucht wurden (negative price_at_sale)
        # gehen in die sale-Tabelle, nicht in topup — beide Quellen addieren.
        article_topup_row = db.execute(
            f"""
            SELECT COALESCE(SUM(ABS(price_at_sale)), 0.0) AS topup_from_articles
            FROM sale
            WHERE event_id = ? AND cancelled = 0 AND price_at_sale < 0 {time_where}
            """,
            (event_id, *time_params),
        ).fetchone()

    return ChipSummaryResponse(
        total_chips=chip_row["total_chips"],
        active_chips=chip_row["active_chips"],
        total_balance=chip_row["total_balance"],
        pending_pfand=chip_row["active_chips"] * CHIP_DEPOSIT,
        total_topup=topup_row["total_topup"] + article_topup_row["topup_from_articles"],
        total_payout=topup_row["total_payout"],
    )
