"""
Statistics router — revenue summaries, paginated transaction list, CSV export,
and period management (Tagesabschluss).

All endpoints require the corresponding `statistics.*` permission.
Time filters use ISO-8601 strings compared directly against the SQLite
`booked_at` TEXT column (stored as UTC, formatted as `YYYY-MM-DD HH:MM:SS`).
"""

import csv
import io

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse

from config import BAR_CHIP_UID
from database import get_db
from dependencies import RequestContext, require_permission
from schemas import (
    CategoryArticle,
    CategoryRevenue,
    PeriodCloseRequest,
    PeriodCloseResponse,
    RevenueResponse,
    StatsPeriodResponse,
    TransactionItem,
    TransactionListResponse,
)

router = APIRouter(prefix="/api/stats", tags=["statistics"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


def _resolve_time_filter(
    db,
    event_id: int,
    period_ids: str | None,
    period_id: int | None,
    period_start: str | None,
    period_end: str | None,
) -> tuple[str, list]:
    """
    Returns a time-filter fragment + params for the `sale` table (alias `s`).

    Priority: period_ids (multi) > period_id (single) > manual start/end.
    period_ids is a comma-separated string of stats_period IDs.
    The resolved time range spans min(started_at) … max(closed_at) of all
    selected periods; if any selected period is still open, no upper bound.
    """
    if period_ids:
        ids = [int(x) for x in period_ids.split(",") if x.strip().isdigit()]
        if ids:
            ph = ",".join("?" * len(ids))
            rows = db.execute(
                f"SELECT started_at, closed_at FROM stats_period "
                f"WHERE id IN ({ph}) AND event_id=?",
                [*ids, event_id],
            ).fetchall()
            if rows:
                min_start = min(r["started_at"] for r in rows)
                has_open = any(r["closed_at"] is None for r in rows)
                max_end = None if has_open else max(r["closed_at"] for r in rows)
                clauses = ["s.booked_at >= ?"]
                params: list = [min_start]
                if max_end:
                    clauses.append("s.booked_at <= ?")
                    params.append(max_end)
                return " AND " + " AND ".join(clauses), params

    if period_id is not None:
        row = db.execute(
            "SELECT started_at, closed_at FROM stats_period WHERE id=? AND event_id=?",
            (period_id, event_id),
        ).fetchone()
        if row:
            clauses = ["s.booked_at >= ?"]
            params = [row["started_at"]]
            if row["closed_at"]:
                clauses.append("s.booked_at <= ?")
                params.append(row["closed_at"])
            return " AND " + " AND ".join(clauses), params

    return _build_time_filter(period_start, period_end)


def _period_time_bounds(
    db, event_id: int, period_ids: str | None
) -> tuple[str | None, str | None]:
    """
    Returns (min_started_at, max_closed_at) for a given period_ids string.
    max_closed_at is None if any selected period is still open.
    Used by other routers that need the same bounds with different table aliases.
    """
    if not period_ids:
        return None, None
    ids = [int(x) for x in period_ids.split(",") if x.strip().isdigit()]
    if not ids:
        return None, None
    ph = ",".join("?" * len(ids))
    rows = db.execute(
        f"SELECT started_at, closed_at FROM stats_period "
        f"WHERE id IN ({ph}) AND event_id=?",
        [*ids, event_id],
    ).fetchall()
    if not rows:
        return None, None
    min_start = min(r["started_at"] for r in rows)
    has_open = any(r["closed_at"] is None for r in rows)
    max_end = None if has_open else max(r["closed_at"] for r in rows)
    return min_start, max_end


# ---------------------------------------------------------------------------
# Period management
# ---------------------------------------------------------------------------

@router.get("/periods", response_model=list[StatsPeriodResponse])
def list_periods(
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    event_id = ctx["event"]["id"]
    with get_db() as db:
        rows = db.execute(
            """
            SELECT id, label, started_at, closed_at
            FROM stats_period
            WHERE event_id=?
            ORDER BY started_at DESC
            """,
            (event_id,),
        ).fetchall()
    return [StatsPeriodResponse(**dict(r)) for r in rows]


@router.post("/periods/close", response_model=PeriodCloseResponse, status_code=201)
def close_period(
    body: PeriodCloseRequest,
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    """
    Closes the current open period and immediately opens a new one.
    The new period's label comes from the request body.
    """
    user_id = ctx["user"]["id"]
    event_id = ctx["event"]["id"]

    with get_db(exclusive=True) as db:
        # Close any currently open period for this event.
        db.execute(
            "UPDATE stats_period SET closed_at = datetime('now') WHERE event_id=? AND closed_at IS NULL",
            (event_id,),
        )
        # Open the new period.
        cursor = db.execute(
            "INSERT INTO stats_period (event_id, label, created_by) VALUES (?, ?, ?)",
            (event_id, body.label, user_id),
        )
        new_id = cursor.lastrowid
        new_row = db.execute(
            "SELECT id, label, started_at, closed_at FROM stats_period WHERE id=?",
            (new_id,),
        ).fetchone()

    return PeriodCloseResponse(new_period=StatsPeriodResponse(**dict(new_row)))


@router.post("/event-reset", response_model=PeriodCloseResponse, status_code=201)
def event_reset(
    body: PeriodCloseRequest,
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    """
    Neues Event vorbereiten: Tagesabschluss + Kunden-Reset.

    1. Schließt die aktuelle Periode und öffnet eine neue.
    2. Setzt alle Chip-Guthaben auf 0 und markiert alle Chips als
       'verfügbar für Neuausgabe' (is_available=1), sodass der nächste
       Scan eines Chips als neuer Kunde behandelt wird (inkl. Pfand).

    Artikel, Benutzer und der komplette Buchungsverlauf bleiben erhalten.
    """
    user_id = ctx["user"]["id"]
    event_id = ctx["event"]["id"]
    tenant_id = ctx["user"]["tenant_id"]

    with get_db(exclusive=True) as db:
        # Tagesabschluss
        db.execute(
            "UPDATE stats_period SET closed_at = datetime('now') WHERE event_id=? AND closed_at IS NULL",
            (event_id,),
        )
        cursor = db.execute(
            "INSERT INTO stats_period (event_id, label, created_by) VALUES (?, ?, ?)",
            (event_id, body.label, user_id),
        )
        new_id = cursor.lastrowid
        new_row = db.execute(
            "SELECT id, label, started_at, closed_at FROM stats_period WHERE id=?",
            (new_id,),
        ).fetchone()

        # Alle Kunden zurücksetzen: Guthaben = 0, als neu markieren.
        # is_available=1 bewirkt beim nächsten Scan: neuer Kunde + Pfand wird erneut erhoben.
        # BAR-Chip wird ausgenommen — er ist kein echter Gast-Chip.
        db.execute(
            "UPDATE customer SET balance = 0.0, is_available = 1 WHERE tenant_id = ? AND nfc_uid != ?",
            (tenant_id, BAR_CHIP_UID),
        )

    return PeriodCloseResponse(new_period=StatsPeriodResponse(**dict(new_row)))


# ---------------------------------------------------------------------------
# Revenue summary
# ---------------------------------------------------------------------------

@router.get("/revenue", response_model=RevenueResponse)
def get_revenue(
    period_ids: str | None = Query(None, description="Comma-separated period IDs (highest priority)"),
    period_id: int | None = Query(None, description="Single period ID (fallback)"),
    period_start: str | None = Query(None, description="ISO datetime, e.g. 2026-06-01T00:00:00"),
    period_end: str | None = Query(None, description="ISO datetime, e.g. 2026-06-01T23:59:59"),
    ctx: RequestContext = Depends(require_permission("statistics.revenue")),
):
    event_id = ctx["event"]["id"]

    with get_db() as db:
        time_where, time_params = _resolve_time_filter(
            db, event_id, period_ids, period_id, period_start, period_end
        )

        # Revenue per category — excludes payout articles and products marked
        # exclude_from_stats (e.g. Pfand products, Aufladungs-Artikel).
        rows = db.execute(
            f"""
            SELECT c.id as category_id, c.name as category_name,
                   COALESCE(SUM(s.price_at_sale), 0) as revenue,
                   COUNT(s.id) as transaction_count
            FROM category c
            LEFT JOIN product p ON p.category_id = c.id
                AND p.is_payout = 0 AND p.exclude_from_stats = 0
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
            SELECT COALESCE(SUM(s.price_at_sale), 0) as total,
                   COUNT(s.id) as count
            FROM sale s
            JOIN product p ON s.product_id = p.id
            WHERE s.event_id=? AND s.cancelled=0
                AND p.is_payout = 0 AND p.exclude_from_stats = 0
                {time_where}
            """,
            [event_id, *time_params],
        ).fetchone()

        # Per-article breakdown — all product types (incl. Pfand, Aufladungen, Auszahlungen).
        # Only products that actually had sales in the selected period are returned.
        article_rows = db.execute(
            f"""
            SELECT c.id as category_id,
                   p.name as product_name,
                   p.is_payout,
                   p.exclude_from_stats,
                   COALESCE(SUM(s.price_at_sale), 0.0) as revenue,
                   COUNT(s.id) as transaction_count
            FROM category c
            JOIN product p ON p.category_id = c.id
            LEFT JOIN sale s ON s.product_id = p.id
                AND s.event_id = ? AND s.cancelled = 0 {time_where}
            WHERE c.event_id = ? AND c.deleted = 0
            GROUP BY c.id, p.id, p.name, p.is_payout, p.exclude_from_stats
            HAVING COUNT(s.id) > 0
            ORDER BY c.sort_order, c.id, p.is_payout, p.exclude_from_stats, p.sort_order
            """,
            [event_id, *time_params, event_id],
        ).fetchall()

    articles_by_cat: dict[int, list[CategoryArticle]] = {}
    for ar in article_rows:
        cid = ar["category_id"]
        if cid not in articles_by_cat:
            articles_by_cat[cid] = []
        articles_by_cat[cid].append(
            CategoryArticle(
                product_name=ar["product_name"],
                revenue=float(ar["revenue"]),
                transaction_count=ar["transaction_count"],
                is_payout=bool(ar["is_payout"]),
                exclude_from_stats=bool(ar["exclude_from_stats"]),
            )
        )

    return RevenueResponse(
        total_revenue=total_row["total"],
        total_transactions=total_row["count"],
        by_category=[
            CategoryRevenue(
                category_name=r["category_name"],
                revenue=r["revenue"],
                transaction_count=r["transaction_count"],
                articles=articles_by_cat.get(r["category_id"], []),
            )
            for r in rows
        ],
        period_start=period_start,
        period_end=period_end,
    )


# ---------------------------------------------------------------------------
# Transaction list
# ---------------------------------------------------------------------------

@router.get("/transactions", response_model=TransactionListResponse)
def get_transactions(
    period_ids: str | None = Query(None),
    period_id: int | None = Query(None),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    category_id: int | None = Query(None),
    customer_name: str | None = Query(None, description="Filter by customer name (case-insensitive substring)"),
    limit: int = Query(500, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    ctx: RequestContext = Depends(require_permission("statistics.transactions")),
):
    event_id = ctx["event"]["id"]

    category_where = "AND p.category_id = ?" if category_id else ""
    category_param = [category_id] if category_id else []

    name_where = "AND cu.customer_name LIKE ?" if customer_name else ""
    name_param = [f"%{customer_name}%"] if customer_name else []

    with get_db() as db:
        time_where, time_params = _resolve_time_filter(
            db, event_id, period_ids, period_id, period_start, period_end
        )

        rows = db.execute(
            f"""
            SELECT s.id, s.booked_at, cu.nfc_uid, cu.customer_name,
                   p.name as product_name,
                   s.price_at_sale, c.name as category_name,
                   u.username as booked_by_username, s.cancelled
            FROM sale s
            JOIN customer cu ON s.customer_id = cu.id
            JOIN product p ON s.product_id = p.id
            JOIN category c ON p.category_id = c.id
            JOIN user u ON s.booked_by = u.id
            WHERE s.event_id=? {time_where} {category_where} {name_where}
            ORDER BY s.booked_at DESC
            LIMIT ? OFFSET ?
            """,
            [event_id, *time_params, *category_param, *name_param, limit, offset],
        ).fetchall()

        total_row = db.execute(
            f"""
            SELECT COUNT(*) as total FROM sale s
            JOIN customer cu ON s.customer_id = cu.id
            JOIN product p ON s.product_id = p.id
            WHERE s.event_id=? {time_where} {category_where} {name_where}
            """,
            [event_id, *time_params, *category_param, *name_param],
        ).fetchone()

    items = [
        TransactionItem(
            id=r["id"],
            booked_at=r["booked_at"],
            nfc_uid=r["nfc_uid"],
            customer_name=r["customer_name"],
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
    period_ids: str | None = Query(None),
    period_id: int | None = Query(None),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    ctx: RequestContext = Depends(require_permission("statistics.export")),
):
    event_id = ctx["event"]["id"]

    with get_db() as db:
        time_where, time_params = _resolve_time_filter(
            db, event_id, period_ids, period_id, period_start, period_end
        )

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
