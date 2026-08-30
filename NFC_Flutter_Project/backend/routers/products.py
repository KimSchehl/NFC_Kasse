import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from database import get_db
from dependencies import RequestContext, get_active_event, get_current_user, require_permission
from schemas import (
    CategoryAccessItem,
    CategoryCreate,
    CategoryUpdate,
    CategoryWithPermissionsResponse,
    ProductActiveUpdate,
    ProductChangesResponse,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)

router = APIRouter(prefix="/api/products", tags=["products"])
logger = logging.getLogger(__name__)

# Mirrors the German labels the Flutter edit_user_dialog checkbox tree uses
# for these same columns, so a 403 names the actual missing right instead of
# a raw DB column name like "can_create_article".
_FLAG_LABELS = {
    "can_book": "Buchen",
    "can_storno_5min": "Storno (5 Min.)",
    "can_storno_unlimited": "Storno (unbegrenzt)",
    "can_create_article": "Erstellen",
    "can_edit_article": "Bearbeiten",
    "can_deactivate_article": "Deaktivieren",
    "can_delete_article": "Löschen",
}

# Manager permissions — any of these grants full access to all categories.
_MANAGER_PERMS = ('categories.create', 'categories.edit', 'categories.deactivate', 'categories.delete')


def _user_can_manage_categories(db, user_id: int, event_id: int) -> bool:
    """True if user has any category-management permission (manager path)."""
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


def _get_category_access(db, user_id: int, event_id: int, category_id: int) -> dict | None:
    """Returns the user_category_access row as dict, or None if no access."""
    row = db.execute(
        """
        SELECT can_book, can_storno_5min, can_storno_unlimited,
               can_create_article, can_edit_article, can_deactivate_article, can_delete_article
        FROM user_category_access
        WHERE user_id=? AND event_id=? AND category_id=?
        """,
        (user_id, event_id, category_id),
    ).fetchone()
    return dict(row) if row else None


def _require_category_flag(db, user_id: int, event_id: int, category_id: int, flag: str):
    """Raises 403 if user lacks the given flag for this category."""
    if _user_can_manage_categories(db, user_id, event_id):
        return  # managers always have full access
    access = _get_category_access(db, user_id, event_id, category_id)
    if not access or not access[flag]:
        logger.warning(
            "Article action denied: user_id=%s missing '%s' for category_id=%s",
            user_id, flag, category_id,
        )
        raise HTTPException(
            status_code=403,
            detail=f"Keine Berechtigung '{_FLAG_LABELS.get(flag, flag)}' für diese Kategorie",
        )


# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------

@router.get("/categories", response_model=list[CategoryWithPermissionsResponse])
def list_categories(
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        is_manager = _user_can_manage_categories(db, user_id, event_id)

        if is_manager:
            rows = db.execute(
                "SELECT id, name, sort_order FROM category WHERE event_id=? AND deleted=0 ORDER BY sort_order",
                (event_id,),
            ).fetchall()
            return [
                CategoryWithPermissionsResponse(
                    id=r["id"], name=r["name"], sort_order=r["sort_order"],
                    can_book=True, can_storno_5min=True, can_storno_unlimited=True,
                    can_create_article=True, can_edit_article=True,
                    can_deactivate_article=True, can_delete_article=True,
                )
                for r in rows
            ]
        else:
            rows = db.execute(
                """
                SELECT c.id, c.name, c.sort_order,
                       uca.can_book, uca.can_storno_5min, uca.can_storno_unlimited,
                       uca.can_create_article, uca.can_edit_article,
                       uca.can_deactivate_article, uca.can_delete_article
                FROM category c
                JOIN user_category_access uca ON uca.category_id = c.id
                WHERE uca.user_id=? AND uca.event_id=? AND c.deleted=0
                AND (uca.can_book=1 OR uca.can_storno_5min=1 OR uca.can_storno_unlimited=1
                     OR uca.can_create_article=1 OR uca.can_edit_article=1
                     OR uca.can_deactivate_article=1 OR uca.can_delete_article=1)
                ORDER BY c.sort_order
                """,
                (user_id, event_id),
            ).fetchall()
            return [
                CategoryWithPermissionsResponse(
                    id=r["id"], name=r["name"], sort_order=r["sort_order"],
                    can_book=bool(r["can_book"]),
                    can_storno_5min=bool(r["can_storno_5min"]),
                    can_storno_unlimited=bool(r["can_storno_unlimited"]),
                    can_create_article=bool(r["can_create_article"]),
                    can_edit_article=bool(r["can_edit_article"]),
                    can_deactivate_article=bool(r["can_deactivate_article"]),
                    can_delete_article=bool(r["can_delete_article"]),
                )
                for r in rows
            ]


@router.post("/categories", response_model=CategoryWithPermissionsResponse, status_code=201)
def create_category(
    body: CategoryCreate,
    ctx: RequestContext = Depends(require_permission("categories.create")),
):
    user_id = ctx["user"]["id"]
    event_id = ctx["event"]["id"]
    with get_db() as db:
        cursor = db.execute(
            "INSERT INTO category (event_id, name, sort_order) VALUES (?, ?, ?)",
            (event_id, body.name, body.sort_order),
        )
        new_id = cursor.lastrowid
        # Grant full access to the creator so the category shows up in their view.
        db.execute(
            """
            INSERT INTO user_category_access (
                user_id, event_id, category_id,
                can_book, can_storno_5min, can_storno_unlimited,
                can_create_article, can_edit_article, can_deactivate_article, can_delete_article
            ) VALUES (?, ?, ?, 1, 1, 1, 1, 1, 1, 1)
            """,
            (user_id, event_id, new_id),
        )
    logger.info(
        "Category created: category_id=%s name=%s by=%s",
        new_id, body.name, ctx["user"]["username"],
    )
    return CategoryWithPermissionsResponse(
        id=new_id, name=body.name, sort_order=body.sort_order,
        can_book=True, can_storno_5min=True, can_storno_unlimited=True,
        can_create_article=True, can_edit_article=True,
        can_deactivate_article=True, can_delete_article=True,
    )


@router.put("/categories/{category_id}", response_model=CategoryWithPermissionsResponse)
def update_category(
    category_id: int,
    body: CategoryUpdate,
    ctx: RequestContext = Depends(require_permission("categories.edit")),
):
    event_id = ctx["event"]["id"]
    with get_db() as db:
        row = db.execute(
            "SELECT * FROM category WHERE id=? AND event_id=? AND deleted=0",
            (category_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Kategorie nicht gefunden")

        new_name = body.name if body.name is not None else row["name"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]

        db.execute(
            "UPDATE category SET name=?, sort_order=? WHERE id=?",
            (new_name, new_sort, category_id),
        )
    logger.info(
        "Category updated: category_id=%s name=%s by=%s",
        category_id, new_name, ctx["user"]["username"],
    )
    return CategoryWithPermissionsResponse(
        id=category_id, name=new_name, sort_order=new_sort,
        can_book=True, can_storno_5min=True, can_storno_unlimited=True,
        can_create_article=True, can_edit_article=True,
        can_deactivate_article=True, can_delete_article=True,
    )


@router.delete("/categories/{category_id}", status_code=204)
def delete_category(
    category_id: int,
    ctx: RequestContext = Depends(require_permission("categories.delete")),
):
    event_id = ctx["event"]["id"]
    with get_db() as db:
        row = db.execute(
            "SELECT id FROM category WHERE id=? AND event_id=? AND deleted=0",
            (category_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Kategorie nicht gefunden")
        db.execute("UPDATE category SET deleted=1 WHERE id=?", (category_id,))

    logger.warning(
        "Category deleted: category_id=%s by=%s", category_id, ctx["user"]["username"],
    )


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------

@router.get("/", response_model=list[ProductResponse])
def list_products(
    category_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        cat = db.execute(
            "SELECT id FROM category WHERE id=? AND event_id=? AND deleted=0",
            (category_id, event_id),
        ).fetchone()
        if not cat:
            raise HTTPException(status_code=404, detail="Kategorie nicht gefunden")

        is_manager = _user_can_manage_categories(db, user_id, event_id)

        if not is_manager:
            access = _get_category_access(db, user_id, event_id, category_id)
            if not access:
                raise HTTPException(status_code=403, detail="Kein Zugriff auf diese Kategorie")

        # Users with can_deactivate_article see inactive products so they can re-enable them
        show_inactive = is_manager or bool((access or {}).get("can_deactivate_article", False))

        if show_inactive:
            rows = db.execute(
                """SELECT id, name, price, category_id, sort_order, active, is_payout, exclude_from_stats, points, stock, requires_pager
                   FROM product WHERE category_id=? AND deleted=0 ORDER BY sort_order""",
                (category_id,),
            ).fetchall()
        else:
            rows = db.execute(
                """SELECT id, name, price, category_id, sort_order, active, is_payout, exclude_from_stats, stock, requires_pager
                   FROM product WHERE category_id=? AND deleted=0 AND active=1 ORDER BY sort_order""",
                (category_id,),
            ).fetchall()

    return [ProductResponse(**dict(r)) for r in rows]


@router.get("/changed", response_model=ProductChangesResponse)
def get_changed_products(
    category_id: int,
    since: str = Query(..., description="ISO datetime — products changed after this are returned"),
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """
    Powers the cross-device catalog sync poll: devices remember the
    server-returned `checked_at` from their last call and pass it back as
    `since`, getting back only what actually changed for this category since
    then — either a full products list (on first view of a category) or a
    handful of updates (on every subsequent poll / pre-booking check).

    Deliberately compares timestamps in Python, not SQL: SQLite stores
    `datetime('now')` as naive UTC ("2026-08-18 20:15:00"), while `since`
    arrives as an ISO string with a 'T'/'Z' ("2026-08-18T20:15:00.000Z") — a
    raw SQL string comparison of those two formats isn't reliable. Fetching
    a whole category (typically well under 100 rows) and filtering in Python
    is the same trade-off `sales.py`'s cancel-window check already makes for
    the same reason.
    """
    user_id = current_user["id"]
    event_id = active_event["id"]

    try:
        since_dt = datetime.fromisoformat(since)
    except ValueError:
        raise HTTPException(status_code=400, detail="Ungültiges Datumsformat für 'since'")
    if since_dt.tzinfo is None:
        since_dt = since_dt.replace(tzinfo=timezone.utc)

    with get_db() as db:
        cat = db.execute(
            "SELECT id FROM category WHERE id=? AND event_id=? AND deleted=0",
            (category_id, event_id),
        ).fetchone()
        if not cat:
            raise HTTPException(status_code=404, detail="Kategorie nicht gefunden")

        is_manager = _user_can_manage_categories(db, user_id, event_id)
        access = None
        if not is_manager:
            access = _get_category_access(db, user_id, event_id, category_id)
            if not access:
                raise HTTPException(status_code=403, detail="Kein Zugriff auf diese Kategorie")
        show_inactive = is_manager or bool((access or {}).get("can_deactivate_article", False))

        rows = db.execute(
            """SELECT id, name, price, category_id, sort_order, active, is_payout,
                      exclude_from_stats, points, stock, requires_pager, deleted, updated_at
               FROM product WHERE category_id=?""",
            (category_id,),
        ).fetchall()

    products = []
    removed_ids = []
    for r in rows:
        if r["updated_at"] is None:
            continue  # never touched since this column was added — can't have "changed"
        updated_at = datetime.fromisoformat(r["updated_at"])
        if updated_at.tzinfo is None:
            updated_at = updated_at.replace(tzinfo=timezone.utc)
        if updated_at <= since_dt:
            continue
        if r["deleted"]:
            removed_ids.append(r["id"])
        elif show_inactive or r["active"]:
            products.append(ProductResponse(**dict(r)))

    return ProductChangesResponse(
        products=products,
        removed_ids=removed_ids,
        checked_at=datetime.now(timezone.utc).isoformat(),
    )


@router.post("/", response_model=ProductResponse, status_code=201)
def create_product(
    body: ProductCreate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        cat = db.execute(
            "SELECT id FROM category WHERE id=? AND event_id=? AND deleted=0",
            (body.category_id, event_id),
        ).fetchone()
        if not cat:
            raise HTTPException(status_code=404, detail="Kategorie nicht gefunden")

        _require_category_flag(db, user_id, event_id, body.category_id, "can_create_article")

        max_row = db.execute(
            "SELECT COALESCE(MAX(sort_order), -1) AS m FROM product WHERE category_id=? AND deleted=0",
            (body.category_id,),
        ).fetchone()
        next_sort = max_row["m"] + 1

        cursor = db.execute(
            "INSERT INTO product (category_id, name, price, sort_order, is_payout, exclude_from_stats, points, stock, requires_pager) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (body.category_id, body.name, body.price, next_sort,
             1 if body.is_payout else 0, 1 if body.exclude_from_stats else 0, body.points, body.stock,
             1 if body.requires_pager else 0),
        )
        new_id = cursor.lastrowid

    logger.info(
        "Product created: product_id=%s name=%s price=%s category_id=%s by=%s",
        new_id, body.name, body.price, body.category_id, current_user["username"],
    )
    return ProductResponse(
        id=new_id, name=body.name, price=body.price,
        category_id=body.category_id, sort_order=next_sort, active=True,
        is_payout=body.is_payout, exclude_from_stats=body.exclude_from_stats, points=body.points,
        stock=body.stock, requires_pager=body.requires_pager,
    )


@router.put("/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: int,
    body: ProductUpdate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = db.execute(
            """
            SELECT p.* FROM product p
            JOIN category c ON p.category_id = c.id
            WHERE p.id=? AND c.event_id=? AND p.deleted=0
            """,
            (product_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artikel nicht gefunden")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_edit_article")

        new_name = body.name if body.name is not None else row["name"]
        new_price = body.price if body.price is not None else row["price"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]
        new_is_payout = body.is_payout if body.is_payout is not None else bool(row["is_payout"])
        new_exclude = body.exclude_from_stats if body.exclude_from_stats is not None else bool(row["exclude_from_stats"])
        new_points = body.points if body.points is not None else int(row["points"])
        new_requires_pager = body.requires_pager if body.requires_pager is not None else bool(row["requires_pager"])
        # stock is the one field where "omitted" and "explicit null" must be
        # told apart — null means "clear tracking", which the `!= None`
        # pattern above can't express (it would just mean "unchanged" for a
        # field that legitimately wants to *become* null).
        if "stock" in body.model_fields_set:
            new_stock = body.stock
        else:
            new_stock = row["stock"]

        db.execute(
            "UPDATE product SET name=?, price=?, sort_order=?, is_payout=?, exclude_from_stats=?, points=?, stock=?, requires_pager=?, updated_at=datetime('now') WHERE id=?",
            (new_name, new_price, new_sort,
             1 if new_is_payout else 0, 1 if new_exclude else 0, new_points, new_stock,
             1 if new_requires_pager else 0, product_id),
        )

    logger.info(
        "Product updated: product_id=%s name=%s price=%s by=%s",
        product_id, new_name, new_price, current_user["username"],
    )
    return ProductResponse(
        id=product_id, name=new_name, price=new_price,
        category_id=row["category_id"], sort_order=new_sort, active=bool(row["active"]),
        is_payout=new_is_payout, exclude_from_stats=new_exclude, points=new_points,
        stock=new_stock, requires_pager=new_requires_pager,
    )


@router.patch("/{product_id}/active", response_model=ProductResponse)
def set_product_active(
    product_id: int,
    body: ProductActiveUpdate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = db.execute(
            """
            SELECT p.id, p.name, p.price, p.category_id, p.sort_order, p.active, p.is_payout, p.exclude_from_stats, p.points, p.stock, p.requires_pager
            FROM product p
            JOIN category c ON p.category_id = c.id
            WHERE p.id=? AND c.event_id=? AND p.deleted=0
            """,
            (product_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artikel nicht gefunden")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_deactivate_article")

        db.execute(
            "UPDATE product SET active=?, updated_at=datetime('now') WHERE id=?",
            (1 if body.active else 0, product_id),
        )

    logger.info(
        "Product %s: product_id=%s by=%s",
        "activated" if body.active else "deactivated", product_id, current_user["username"],
    )
    return ProductResponse(
        id=product_id, name=row["name"], price=row["price"],
        category_id=row["category_id"], sort_order=row["sort_order"], active=body.active,
        is_payout=bool(row["is_payout"]),
        exclude_from_stats=bool(row["exclude_from_stats"]),
        points=int(row["points"]),
        stock=row["stock"],
        requires_pager=bool(row["requires_pager"]),
    )


@router.delete("/{product_id}", status_code=204)
def delete_product(
    product_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = db.execute(
            """
            SELECT p.id, p.category_id FROM product p
            JOIN category c ON p.category_id = c.id
            WHERE p.id=? AND c.event_id=? AND p.deleted=0
            """,
            (product_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artikel nicht gefunden")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_delete_article")

        db.execute(
            "UPDATE product SET deleted=1, updated_at=datetime('now') WHERE id=?",
            (product_id,),
        )

    logger.warning(
        "Product deleted: product_id=%s by=%s", product_id, current_user["username"],
    )
