from fastapi import APIRouter, Depends, HTTPException

from database import get_db
from dependencies import RequestContext, get_active_event, get_current_user, require_permission
from schemas import (
    CategoryAccessItem,
    CategoryCreate,
    CategoryUpdate,
    CategoryWithPermissionsResponse,
    ProductActiveUpdate,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)

router = APIRouter(prefix="/api/products", tags=["products"])

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
        raise HTTPException(
            status_code=403,
            detail=f"No '{flag}' permission for category {category_id}",
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
            raise HTTPException(status_code=404, detail="Category not found")

        new_name = body.name if body.name is not None else row["name"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]

        db.execute(
            "UPDATE category SET name=?, sort_order=? WHERE id=?",
            (new_name, new_sort, category_id),
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
            raise HTTPException(status_code=404, detail="Category not found")
        db.execute("UPDATE category SET deleted=1 WHERE id=?", (category_id,))


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
            raise HTTPException(status_code=404, detail="Category not found")

        is_manager = _user_can_manage_categories(db, user_id, event_id)

        if not is_manager:
            access = _get_category_access(db, user_id, event_id, category_id)
            if not access:
                raise HTTPException(status_code=403, detail="No access to this category")

        # Users with can_deactivate_article see inactive products so they can re-enable them
        show_inactive = is_manager or bool((access or {}).get("can_deactivate_article", False))

        if show_inactive:
            rows = db.execute(
                """SELECT id, name, price, category_id, sort_order, active, color, is_payout
                   FROM product WHERE category_id=? AND deleted=0 ORDER BY sort_order""",
                (category_id,),
            ).fetchall()
        else:
            rows = db.execute(
                """SELECT id, name, price, category_id, sort_order, active, color, is_payout
                   FROM product WHERE category_id=? AND deleted=0 AND active=1 ORDER BY sort_order""",
                (category_id,),
            ).fetchall()

    return [ProductResponse(**dict(r)) for r in rows]


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
            raise HTTPException(status_code=404, detail="Category not found")

        _require_category_flag(db, user_id, event_id, body.category_id, "can_create_article")

        cursor = db.execute(
            "INSERT INTO product (category_id, name, price, sort_order, color, is_payout) VALUES (?, ?, ?, ?, ?, ?)",
            (body.category_id, body.name, body.price, body.sort_order, body.color, 1 if body.is_payout else 0),
        )
        new_id = cursor.lastrowid

    return ProductResponse(
        id=new_id, name=body.name, price=body.price,
        category_id=body.category_id, sort_order=body.sort_order, active=True,
        color=body.color, is_payout=body.is_payout,
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
            raise HTTPException(status_code=404, detail="Product not found")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_edit_article")

        new_name = body.name if body.name is not None else row["name"]
        new_price = body.price if body.price is not None else row["price"]
        new_sort = body.sort_order if body.sort_order is not None else row["sort_order"]
        # Flutter always sends the color field (sendColor=True in ProductService),
        # so body.color == None means the user explicitly cleared the color.
        new_color = body.color
        new_is_payout = body.is_payout if body.is_payout is not None else bool(row["is_payout"])

        db.execute(
            "UPDATE product SET name=?, price=?, sort_order=?, color=?, is_payout=? WHERE id=?",
            (new_name, new_price, new_sort, new_color, 1 if new_is_payout else 0, product_id),
        )

    return ProductResponse(
        id=product_id, name=new_name, price=new_price,
        category_id=row["category_id"], sort_order=new_sort, active=bool(row["active"]),
        color=new_color, is_payout=new_is_payout,
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
            SELECT p.id, p.name, p.price, p.category_id, p.sort_order, p.active, p.color, p.is_payout
            FROM product p
            JOIN category c ON p.category_id = c.id
            WHERE p.id=? AND c.event_id=? AND p.deleted=0
            """,
            (product_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Product not found")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_deactivate_article")

        db.execute("UPDATE product SET active=? WHERE id=?", (1 if body.active else 0, product_id))

    return ProductResponse(
        id=product_id, name=row["name"], price=row["price"],
        category_id=row["category_id"], sort_order=row["sort_order"], active=body.active,
        color=row["color"], is_payout=bool(row["is_payout"]),
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
            raise HTTPException(status_code=404, detail="Product not found")

        _require_category_flag(db, user_id, event_id, row["category_id"], "can_delete_article")

        db.execute("UPDATE product SET deleted=1 WHERE id=?", (product_id,))
