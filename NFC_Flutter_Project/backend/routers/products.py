import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

import catalog
from database import get_db
from dependencies import RequestContext, get_active_event, get_current_user, require_permission, user_has_permission
from schemas import (
    AdminCategoryResponse,
    AdminProductsResponse,
    CategoryCreate,
    CategoryUpdate,
    CategoryWithPermissionsResponse,
    EventActiveUpdate,
    ProductActiveUpdate,
    ProductChangesResponse,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)

router = APIRouter(prefix="/api/products", tags=["products"])
logger = logging.getLogger(__name__)

# Categories and articles belong to the tenant (Veranstalter); the running
# fest only switches them on (event_category / event_product, see catalog.py).

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

_ARTICLE_FLAGS = ("can_create_article", "can_edit_article", "can_deactivate_article", "can_delete_article")

_PRODUCT_COLUMNS = (
    "p.id, p.name, p.price, p.category_id, p.sort_order, p.active, p.is_payout, p.is_pfand, "
    "p.exclude_from_stats, p.points, p.stock, p.requires_pager, p.group_id, p.color"
)


def _require_category_flag(db, user_id: int, category_id: int, flag: str):
    """Raises 403 if user lacks the given flag for this category."""
    if catalog.is_manager(db, user_id):
        return  # managers always have full access
    access = catalog.category_access(db, user_id, category_id)
    if not access or not access[flag]:
        logger.warning(
            "Article action denied: user_id=%s missing '%s' for category_id=%s",
            user_id, flag, category_id,
        )
        raise HTTPException(
            status_code=403,
            detail=f"Keine Berechtigung '{_FLAG_LABELS.get(flag, flag)}' für diese Kategorie",
        )


def _category_or_404(db, tenant_id: int, category_id: int, message: str = "Kategorie nicht gefunden"):
    row = catalog.tenant_category(db, tenant_id, category_id)
    if not row:
        raise HTTPException(status_code=404, detail=message)
    return row


def _product_or_404(db, tenant_id: int, product_id: int):
    row = catalog.tenant_product(db, tenant_id, product_id)
    if not row:
        raise HTTPException(status_code=404, detail="Artikel nicht gefunden")
    return row


def _category_response(row, access: dict, active_in_event: bool) -> CategoryWithPermissionsResponse:
    return CategoryWithPermissionsResponse(
        id=row["id"], name=row["name"], sort_order=row["sort_order"],
        active_in_event=active_in_event, **access,
    )


def _validate_group_id(db, group_id: int | None, category_id: int, self_id: int | None = None):
    """
    Raises if `group_id` isn't a valid base article for a product being
    created/updated in `category_id`. A valid base: exists, not deleted,
    same category (options never span categories), has no `group_id` of its
    own (max one level of nesting — an option can't itself have options),
    and isn't the product being saved (no self-reference).
    """
    if group_id is None:
        return
    if group_id == self_id:
        raise HTTPException(status_code=400, detail="Ein Artikel kann nicht seine eigene Option sein")
    base = db.execute(
        "SELECT id, category_id, group_id FROM product WHERE id=? AND deleted=0",
        (group_id,),
    ).fetchone()
    if not base:
        raise HTTPException(status_code=404, detail="Basis-Artikel für die Option nicht gefunden")
    if base["category_id"] != category_id:
        raise HTTPException(
            status_code=400,
            detail="Eine Option muss in derselben Kategorie wie ihr Basis-Artikel liegen",
        )
    if base["group_id"] is not None:
        raise HTTPException(status_code=400, detail="Eine Option kann nicht selbst Optionen haben")


def _get_article_manageable_category_ids(db, user_id: int) -> list[int] | None:
    """
    Category IDs where the user holds any of the 4 article-management flags.
    Returns None as a sentinel for "manager — every category" rather than
    materializing the full id list, so callers can branch cheaply.
    """
    if catalog.is_manager(db, user_id):
        return None
    rows = db.execute(
        f"""
        SELECT category_id FROM user_category_access
        WHERE user_id=? AND ({" OR ".join(f + "=1" for f in _ARTICLE_FLAGS)})
        """,
        (user_id,),
    ).fetchall()
    return [r["category_id"] for r in rows]


# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------

@router.get("/categories", response_model=list[CategoryWithPermissionsResponse])
def list_categories(
    all: bool = Query(False, description="Every category of the tenant, also those not switched on in the running fest"),
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """
    Default: the categories of the running fest the user may see (managers:
    all of them, with full rights).

    all=true: every category of the tenant with `active_in_event` — for
    switching categories on/off and for assigning rights (which hold in every
    fest). Only for managers and holders of users.manage_permissions; the
    flags are then the caller's own.
    """
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        is_manager = catalog.is_manager(db, user_id)
        if all and not (is_manager or user_has_permission(db, user_id, "users.manage_permissions")):
            raise HTTPException(status_code=403, detail="Keine Berechtigung für die Kategorienliste")

        rows = db.execute(
            f"""
            SELECT c.id, c.name, c.sort_order, {catalog.CATEGORY_IN_EVENT_SQL} AS in_event
            FROM category c
            WHERE c.tenant_id=? AND c.deleted=0
            ORDER BY c.sort_order, c.id
            """,
            (event_id, tenant_id),
        ).fetchall()
        if not all:
            rows = [r for r in rows if r["in_event"]]

        result = []
        for r in rows:
            if is_manager:
                access = catalog.FULL_ACCESS
            else:
                access = catalog.category_access(db, user_id, r["id"])
                if not all and not (access and any(access.values())):
                    continue
                access = access or {f: False for f in catalog.ACCESS_FLAGS}
            result.append(_category_response(r, access, bool(r["in_event"])))
    return result


@router.post("/categories", response_model=CategoryWithPermissionsResponse, status_code=201)
def create_category(
    body: CategoryCreate,
    ctx: RequestContext = Depends(require_permission("categories.create")),
):
    """A new category belongs to the tenant and is switched on in the
    running fest right away."""
    user_id = ctx["user"]["id"]
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    with get_db() as db:
        cursor = db.execute(
            "INSERT INTO category (tenant_id, name, sort_order) VALUES (?, ?, ?)",
            (tenant_id, body.name, body.sort_order),
        )
        new_id = cursor.lastrowid
        catalog.set_category_in_event(db, event_id, new_id, True)
        # Grant full access to the creator so the category shows up in their view.
        db.execute(
            f"""
            INSERT OR IGNORE INTO user_category_access (user_id, category_id, {", ".join(catalog.ACCESS_FLAGS)})
            VALUES (?, ?, {", ".join("1" for _ in catalog.ACCESS_FLAGS)})
            """,
            (user_id, new_id),
        )
        row = catalog.tenant_category(db, tenant_id, new_id)
        catalog.bump_revision(db, tenant_id)
    logger.info(
        "Category created: category_id=%s name=%s by=%s",
        new_id, body.name, ctx["user"]["username"],
    )
    return _category_response(row, catalog.FULL_ACCESS, True)


@router.put("/categories/{category_id}", response_model=CategoryWithPermissionsResponse)
def update_category(
    category_id: int,
    body: CategoryUpdate,
    ctx: RequestContext = Depends(require_permission("categories.edit")),
):
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    with get_db() as db:
        row = _category_or_404(db, tenant_id, category_id)

        new_name = body.name if body.name is not None else row["name"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]

        db.execute(
            "UPDATE category SET name=?, sort_order=? WHERE id=?",
            (new_name, new_sort, category_id),
        )
        row = catalog.tenant_category(db, tenant_id, category_id)
        in_event = catalog.category_in_event(db, event_id, category_id)
        catalog.bump_revision(db, tenant_id)
    logger.info(
        "Category updated: category_id=%s name=%s by=%s",
        category_id, new_name, ctx["user"]["username"],
    )
    return _category_response(row, catalog.FULL_ACCESS, in_event)


@router.patch("/categories/{category_id}/active", response_model=CategoryWithPermissionsResponse)
def set_category_active_in_event(
    category_id: int,
    body: EventActiveUpdate,
    ctx: RequestContext = Depends(require_permission("categories.deactivate")),
):
    """Switches the category on/off for the running fest only. Switched on
    for the first time there, it brings all its articles along."""
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    with get_db(exclusive=True) as db:
        row = _category_or_404(db, tenant_id, category_id)
        catalog.set_category_in_event(db, event_id, category_id, body.active)
        catalog.bump_revision(db, tenant_id)
    logger.info(
        "Category %s in event %s: category_id=%s by=%s",
        "switched on" if body.active else "switched off", event_id, category_id, ctx["user"]["username"],
    )
    return _category_response(row, catalog.FULL_ACCESS, body.active)


@router.delete("/categories/{category_id}", status_code=204)
def delete_category(
    category_id: int,
    ctx: RequestContext = Depends(require_permission("categories.delete")),
):
    """Soft-deletes the category for every fest of the tenant."""
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        _category_or_404(db, tenant_id, category_id)
        db.execute("UPDATE category SET deleted=1 WHERE id=?", (category_id,))
        catalog.bump_revision(db, tenant_id)

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
    """The category's articles switched on in the running fest."""
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        _category_or_404(db, tenant_id, category_id)
        if not catalog.category_in_event(db, event_id, category_id):
            raise HTTPException(status_code=404, detail="Kategorie ist in diesem Fest nicht aktiv")

        is_manager = catalog.is_manager(db, user_id)
        access = None
        if not is_manager:
            access = catalog.category_access(db, user_id, category_id)
            if not access:
                raise HTTPException(status_code=403, detail="Kein Zugriff auf diese Kategorie")

        # Users with can_deactivate_article see inactive products so they can re-enable them
        show_inactive = is_manager or bool((access or {}).get("can_deactivate_article", False))

        rows = db.execute(
            f"""SELECT {_PRODUCT_COLUMNS} FROM product p
                WHERE p.category_id=? AND p.deleted=0 AND {catalog.PRODUCT_IN_EVENT_SQL}
                {"" if show_inactive else "AND p.active=1"}
                ORDER BY p.sort_order""",
            (category_id, event_id),
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
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    try:
        since_dt = datetime.fromisoformat(since)
    except ValueError:
        raise HTTPException(status_code=400, detail="Ungültiges Datumsformat für 'since'")
    if since_dt.tzinfo is None:
        since_dt = since_dt.replace(tzinfo=timezone.utc)

    with get_db() as db:
        _category_or_404(db, tenant_id, category_id)
        if not catalog.category_in_event(db, event_id, category_id):
            raise HTTPException(status_code=404, detail="Kategorie ist in diesem Fest nicht aktiv")

        is_manager = catalog.is_manager(db, user_id)
        access = None
        if not is_manager:
            access = catalog.category_access(db, user_id, category_id)
            if not access:
                raise HTTPException(status_code=403, detail="Kein Zugriff auf diese Kategorie")
        show_inactive = is_manager or bool((access or {}).get("can_deactivate_article", False))

        rows = db.execute(
            f"""SELECT {_PRODUCT_COLUMNS}, p.deleted, p.updated_at,
                       {catalog.PRODUCT_IN_EVENT_SQL} AS in_event
                FROM product p WHERE p.category_id=?""",
            (event_id, category_id),
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
        if r["deleted"] or not r["in_event"]:
            # Switched off for this fest counts as removed for the device.
            removed_ids.append(r["id"])
        elif show_inactive or r["active"]:
            products.append(ProductResponse(**dict(r)))

    return ProductChangesResponse(
        products=products,
        removed_ids=removed_ids,
        checked_at=datetime.now(timezone.utc).isoformat(),
    )


@router.get("/admin", response_model=AdminProductsResponse)
def list_admin_products(
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """
    Powers the article admin page: every article (including inactive) across
    every category the user can manage articles in — unlike every other
    endpoint above, not scoped to a single category.

    Deliberately its own endpoint rather than looping GET / per category:
    (a) far fewer round trips for a page that shows everything at once, and
    (b) list_products()'s show_inactive is keyed to can_deactivate_article,
    not can_edit_article — a user with only edit rights would never see
    inactive articles via that endpoint. This endpoint uses a simpler,
    correct rule instead: any article-management right on a category means
    you see all of that category's articles, active or not.

    Lists every category and article of the tenant, also those not switched
    on in the running fest (`active_in_event` / `in_event`), since this is
    where they are switched on and off.
    """
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        manageable_ids = _get_article_manageable_category_ids(db, user_id)
        is_manager = manageable_ids is None

        if is_manager or manageable_ids:
            id_filter = "" if is_manager else f"AND c.id IN ({','.join('?' * len(manageable_ids))})"
            cat_rows = db.execute(
                f"""SELECT c.id, c.name, c.sort_order, {catalog.CATEGORY_IN_EVENT_SQL} AS in_event
                    FROM category c
                    WHERE c.tenant_id=? AND c.deleted=0 {id_filter}
                    ORDER BY c.sort_order, c.id""",
                [event_id, tenant_id, *([] if is_manager else manageable_ids)],
            ).fetchall()
        else:
            cat_rows = []

        categories = []
        for cat in cat_rows:
            if is_manager:
                access = {
                    "can_create_article": True, "can_edit_article": True,
                    "can_deactivate_article": True, "can_delete_article": True,
                }
            else:
                access = catalog.category_access(db, user_id, cat["id"]) or {}

            product_rows = db.execute(
                f"""SELECT {_PRODUCT_COLUMNS}, {catalog.PRODUCT_IN_EVENT_SQL} AS in_event
                    FROM product p WHERE p.category_id=? AND p.deleted=0 ORDER BY p.sort_order""",
                (event_id, cat["id"]),
            ).fetchall()

            categories.append(AdminCategoryResponse(
                id=cat["id"], name=cat["name"], sort_order=cat["sort_order"],
                can_create_article=bool(access.get("can_create_article", False)),
                can_edit_article=bool(access.get("can_edit_article", False)),
                can_deactivate_article=bool(access.get("can_deactivate_article", False)),
                can_delete_article=bool(access.get("can_delete_article", False)),
                active_in_event=bool(cat["in_event"]),
                products=[ProductResponse(**{**dict(r), "in_event": bool(r["in_event"])}) for r in product_rows],
            ))

    return AdminProductsResponse(categories=categories)


@router.post("/", response_model=ProductResponse, status_code=201)
def create_product(
    body: ProductCreate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """A new article belongs to the tenant and is switched on in the running
    fest right away (an option follows its base instead)."""
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        _category_or_404(db, tenant_id, body.category_id)
        _require_category_flag(db, user_id, body.category_id, "can_create_article")
        _validate_group_id(db, body.group_id, body.category_id)

        max_row = db.execute(
            "SELECT COALESCE(MAX(sort_order), -1) AS m FROM product WHERE category_id=? AND deleted=0",
            (body.category_id,),
        ).fetchone()
        next_sort = max_row["m"] + 1

        exclude_from_stats = body.exclude_from_stats or body.is_pfand
        cursor = db.execute(
            "INSERT INTO product (category_id, name, price, sort_order, is_payout, is_pfand, exclude_from_stats, points, stock, requires_pager, group_id, color) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (body.category_id, body.name, body.price, next_sort,
             1 if body.is_payout else 0, 1 if body.is_pfand else 0, 1 if exclude_from_stats else 0,
             body.points, body.stock, 1 if body.requires_pager else 0, body.group_id, body.color),
        )
        new_id = cursor.lastrowid
        if body.group_id is None:
            catalog.set_product_in_event(db, event_id, new_id, True)
        in_event = catalog.product_in_event(db, event_id, {"id": new_id, "group_id": body.group_id})
        catalog.bump_revision(db, tenant_id)

    logger.info(
        "Product created: product_id=%s name=%s price=%s category_id=%s by=%s",
        new_id, body.name, body.price, body.category_id, current_user["username"],
    )
    return ProductResponse(
        id=new_id, name=body.name, price=body.price,
        category_id=body.category_id, sort_order=next_sort, active=True,
        is_payout=body.is_payout, is_pfand=body.is_pfand, exclude_from_stats=exclude_from_stats,
        points=body.points, stock=body.stock, requires_pager=body.requires_pager,
        group_id=body.group_id, color=body.color, in_event=in_event,
    )


@router.put("/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: int,
    body: ProductUpdate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = _product_or_404(db, tenant_id, product_id)
        _require_category_flag(db, user_id, row["category_id"], "can_edit_article")

        # Moving to a different category requires edit rights on BOTH the
        # current and the destination category — otherwise a user could use
        # a category they own as a one-way dumping ground into (or out of)
        # one they have no rights to.
        new_category_id = body.category_id if body.category_id is not None else row["category_id"]
        if new_category_id != row["category_id"]:
            # An option can only change category by moving its base article
            # (which cascades to its options, below) — moving it directly
            # would leave it in a different category than its base,
            # violating the same-category invariant _validate_group_id
            # enforces on creation. Ungrouping in the same request (either
            # via an explicit group_id=null, or by pointing it at a new base
            # already in the destination category) is still fine — only a
            # bare category move while still grouped is rejected.
            if row["group_id"] is not None and "group_id" not in body.model_fields_set:
                raise HTTPException(
                    status_code=400,
                    detail="Eine Option kann nicht direkt verschoben werden — verschiebe stattdessen ihren Basis-Artikel",
                )
            _category_or_404(db, tenant_id, new_category_id, "Zielkategorie nicht gefunden")
            _require_category_flag(db, user_id, new_category_id, "can_edit_article")

        new_name = body.name if body.name is not None else row["name"]
        new_price = body.price if body.price is not None else row["price"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]
        new_is_payout = body.is_payout if body.is_payout is not None else bool(row["is_payout"])
        new_is_pfand = body.is_pfand if body.is_pfand is not None else bool(row["is_pfand"])
        new_exclude = body.exclude_from_stats if body.exclude_from_stats is not None else bool(row["exclude_from_stats"])
        if new_is_pfand:
            new_exclude = True
        # Same tri-state as stock: an explicit null clears the default color.
        new_color = body.color if "color" in body.model_fields_set else row["color"]
        new_points = body.points if body.points is not None else int(row["points"])
        new_requires_pager = body.requires_pager if body.requires_pager is not None else bool(row["requires_pager"])
        # stock/group_id are the fields where "omitted" and "explicit null"
        # must be told apart — null means "clear tracking"/"ungroup this
        # article", which the `!= None` pattern above can't express.
        if "stock" in body.model_fields_set:
            new_stock = body.stock
        else:
            new_stock = row["stock"]
        if "group_id" in body.model_fields_set:
            new_group_id = body.group_id
            if new_group_id is not None:
                _validate_group_id(db, new_group_id, new_category_id, self_id=product_id)
                has_children = db.execute(
                    "SELECT 1 FROM product WHERE group_id=? AND deleted=0 LIMIT 1", (product_id,)
                ).fetchone()
                if has_children:
                    raise HTTPException(
                        status_code=400,
                        detail="Ein Artikel mit eigenen Optionen kann nicht selbst zur Option werden",
                    )
        else:
            new_group_id = row["group_id"]

        db.execute(
            "UPDATE product SET name=?, price=?, category_id=?, sort_order=?, is_payout=?, is_pfand=?, exclude_from_stats=?, points=?, stock=?, requires_pager=?, group_id=?, color=?, updated_at=datetime('now') WHERE id=?",
            (new_name, new_price, new_category_id, new_sort,
             1 if new_is_payout else 0, 1 if new_is_pfand else 0, 1 if new_exclude else 0, new_points, new_stock,
             1 if new_requires_pager else 0, new_group_id, new_color, product_id),
        )

        # Options move along with their base article — otherwise they'd be
        # left referencing a base in a different category, violating the
        # same-category invariant _validate_group_id enforces on creation.
        if new_category_id != row["category_id"]:
            db.execute(
                "UPDATE product SET category_id=?, updated_at=datetime('now') WHERE group_id=? AND deleted=0",
                (new_category_id, product_id),
            )
        in_event = catalog.product_in_event(db, event_id, {"id": product_id, "group_id": new_group_id})
        catalog.bump_revision(db, tenant_id)

    logger.info(
        "Product updated: product_id=%s name=%s price=%s by=%s",
        product_id, new_name, new_price, current_user["username"],
    )
    return ProductResponse(
        id=product_id, name=new_name, price=new_price,
        category_id=new_category_id, sort_order=new_sort, active=bool(row["active"]),
        is_payout=new_is_payout, is_pfand=new_is_pfand, exclude_from_stats=new_exclude,
        points=new_points, stock=new_stock, requires_pager=new_requires_pager,
        group_id=new_group_id, color=new_color, in_event=in_event,
    )


@router.patch("/{product_id}/active", response_model=ProductResponse)
def set_product_active(
    product_id: int,
    body: ProductActiveUpdate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = _product_or_404(db, tenant_id, product_id)
        _require_category_flag(db, user_id, row["category_id"], "can_deactivate_article")

        db.execute(
            "UPDATE product SET active=?, updated_at=datetime('now') WHERE id=?",
            (1 if body.active else 0, product_id),
        )
        in_event = catalog.product_in_event(db, event_id, row)
        catalog.bump_revision(db, tenant_id)

    logger.info(
        "Product %s: product_id=%s by=%s",
        "activated" if body.active else "deactivated", product_id, current_user["username"],
    )
    return ProductResponse(
        id=product_id, name=row["name"], price=row["price"],
        category_id=row["category_id"], sort_order=row["sort_order"], active=body.active,
        is_payout=bool(row["is_payout"]),
        is_pfand=bool(row["is_pfand"]),
        exclude_from_stats=bool(row["exclude_from_stats"]),
        points=int(row["points"]),
        stock=row["stock"],
        requires_pager=bool(row["requires_pager"]),
        group_id=row["group_id"],
        color=row["color"],
        in_event=in_event,
    )


@router.patch("/{product_id}/event-active", response_model=ProductResponse)
def set_product_in_event(
    product_id: int,
    body: EventActiveUpdate,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """Switches the article (with its options) on/off for the running fest
    only. Its data — price, stock, colour — is the same in every fest."""
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]
    event_id = active_event["id"]

    with get_db() as db:
        row = _product_or_404(db, tenant_id, product_id)
        if row["group_id"] is not None:
            raise HTTPException(status_code=400, detail="Eine Option folgt ihrem Basis-Artikel")
        _require_category_flag(db, user_id, row["category_id"], "can_deactivate_article")
        catalog.set_product_in_event(db, event_id, product_id, body.active)
        catalog.bump_revision(db, tenant_id)

    logger.info(
        "Product %s in event %s: product_id=%s by=%s",
        "switched on" if body.active else "switched off", event_id, product_id, current_user["username"],
    )
    data = {k: row[k] for k in ProductResponse.model_fields if k not in ("in_event",)}
    return ProductResponse(**data, in_event=body.active)


@router.delete("/{product_id}", status_code=204)
def delete_product(
    product_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    tenant_id = current_user["tenant_id"]

    with get_db() as db:
        row = _product_or_404(db, tenant_id, product_id)
        _require_category_flag(db, user_id, row["category_id"], "can_delete_article")

        db.execute(
            "UPDATE product SET deleted=1, updated_at=datetime('now') WHERE id=?",
            (product_id,),
        )
        # Options have no standalone meaning once their base is gone (e.g.
        # "mit Pommes" without "Currywurst") — cascade the soft-delete
        # rather than leaving them as orphaned, ungrouped articles.
        db.execute(
            "UPDATE product SET deleted=1, updated_at=datetime('now') WHERE group_id=? AND deleted=0",
            (product_id,),
        )
        catalog.bump_revision(db, tenant_id)

    logger.warning(
        "Product deleted: product_id=%s by=%s", product_id, current_user["username"],
    )
