"""
Statistics router — revenue summaries, paginated transaction list, CSV export.

All endpoints require the corresponding `statistics.*` permission.
Time filters use ISO-8601 strings compared directly against the SQLite
`booked_at` TEXT column (stored as UTC, formatted as `YYYY-MM-DD HH:MM:SS`).
"""

import csv
import io

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse

from database import get_db
from dependencies import RequestContext, require_permission
from schemas import CategoryRevenue, RevenueResponse, TransactionItem, TransactionListResponse

router = APIRouter(prefix="/api/stats", tags=["statistics"])


def _build_time_filter(period_start: str | None, period_end: str | None) -> tuple[str, list]:
    """
    Builds an optional SQL WHERE fragment for time-range filtering.

    Returns a tuple of (sql_fragment, params_list). The fragment starts with
    ` AND ` if any clause is present, or is empty if neither bound is given,
    so it can be appended directly to any existing WHERE clause.
    """
    clauses, params = [], []
    if period_start:
        clauses.append("s.booked_at >= ?")
        params.append(period_start)
    if period_end:
        clauses.append("s.booked_at <= ?")
        params.append(period_end)
    where = (" AND " + " AND ".join(clauses)) if clauses else ""
    return where, params


# ---------------------------------------------------------------------------
# Revenue summary
# ---------------------------------------------------------------------------

@router.get("/revenue", response_model=RevenueResponse)
def get_revenue(
    period_start: str | None = Query(None, description="ISO datetime, e.g. 2026-06-01T00:00:00"),
    period_end: str | None = Query(None, description="ISO datetime, e.g. 2026-06-01T23:59:59"),
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    event_id = ctx["event"]["id"]
    time_where, time_params = _build_time_filter(period_start, period_end)

    with get_db() as db:
        # Revenue per category
        rows = db.execute(
            f"""
            SELECT c.name as category_name,
                   COALESCE(SUM(s.price_at_sale), 0) as revenue,
                   COUNT(s.id) as transaction_count
            FROM category c
            LEFT JOIN product p ON p.category_id = c.id
            LEFT JOIN sale s ON s.product_id = p.id
                AND s.event_id=? AND s.cancelled=0 {time_where}
            WHERE c.event_id=? AND c.deleted=0
            GROUP BY c.id, c.name
            ORDER BY c.sort_order
            """,
            [event_id, *time_params, event_id],
        ).fetchall()

        total_row = db.execute(
            f"""
            SELECT COALESCE(SUM(price_at_sale), 0) as total,
                   COUNT(id) as count
            FROM sale s
            WHERE s.event_id=? AND s.cancelled=0 {time_where}
            """,
            [event_id, *time_params],
        ).fetchone()

    return RevenueResponse(
        total_revenue=total_row["total"],
        total_transactions=total_row["count"],
        by_category=[CategoryRevenue(**dict(r)) for r in rows],
        period_start=period_start,
        period_end=period_end,
    )


# ---------------------------------------------------------------------------
# Transaction list
# ---------------------------------------------------------------------------

@router.get("/transactions", response_model=TransactionListResponse)
def get_transactions(
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    category_id: int | None = Query(None),
    limit: int = Query(500, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    ctx: RequestContext = Depends(require_permission("statistics.transactions")),
):
    event_id = ctx["event"]["id"]
    time_where, time_params = _build_time_filter(period_start, period_end)

    category_where = "AND p.category_id = ?" if category_id else ""
    category_param = [category_id] if category_id else []

    with get_db() as db:
        rows = db.execute(
            f"""
            SELECT s.id, s.booked_at, cu.nfc_uid, p.name as product_name,
                   s.price_at_sale, c.name as category_name,
                   u.username as booked_by_username, s.cancelled
            FROM sale s
            JOIN customer cu ON s.customer_id = cu.id
            JOIN product p ON s.product_id = p.id
            JOIN category c ON p.category_id = c.id
            JOIN user u ON s.booked_by = u.id
            WHERE s.event_id=? {time_where} {category_where}
            ORDER BY s.booked_at DESC
            LIMIT ? OFFSET ?
            """,
            [event_id, *time_params, *category_param, limit, offset],
        ).fetchall()

        total_row = db.execute(
            f"""
            SELECT COUNT(*) as total FROM sale s
            JOIN product p ON s.product_id = p.id
            WHERE s.event_id=? {time_where} {category_where}
            """,
            [event_id, *time_params, *category_param],
        ).fetchone()

    items = [
        TransactionItem(
            id=r["id"],
            booked_at=r["booked_at"],
            nfc_uid=r["nfc_uid"],
            product_name=r["product_name"],
            price_at_sale=r["price_at_sale"],
            category_name=r["category_name"],
            booked_by_username=r["booked_by_username"],
            cancelled=bool(r["cancelled"]),
        )
        for r in rows
    ]
    return TransactionListResponse(items=items, total=total_row["total"])


# ---------------------------------------------------------------------------
# CSV export
# ---------------------------------------------------------------------------

@router.get("/export")
def export_transactions(
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    ctx: RequestContext = Depends(require_permission("statistics.export")),
):
    event_id = ctx["event"]["id"]
    time_where, time_params = _build_time_filter(period_start, period_end)

    with get_db() as db:
        rows = db.execute(
            f"""
            SELECT s.id, s.booked_at, cu.nfc_uid, p.name as product_name,
                   s.price_at_sale, c.name as category_name,
                   u.username as booked_by_username, s.cancelled,
                   s.cancelled_at
            FROM sale s
            JOIN customer cu ON s.customer_id = cu.id
            JOIN product p ON s.product_id = p.id
            JOIN category c ON p.category_id = c.id
            JOIN user u ON s.booked_by = u.id
            WHERE s.event_id=? {time_where}
            ORDER BY s.booked_at ASC
            """,
            [event_id, *time_params],
        ).fetchall()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "id", "booked_at", "nfc_uid", "product_name",
        "price_at_sale", "category_name", "booked_by", "cancelled", "cancelled_at",
    ])
    for r in rows:
        writer.writerow([
            r["id"], r["booked_at"], r["nfc_uid"], r["product_name"],
            r["price_at_sale"], r["category_name"], r["booked_by_username"],
            r["cancelled"], r["cancelled_at"] or "",
        ])

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=transactions.csv"},
    )
