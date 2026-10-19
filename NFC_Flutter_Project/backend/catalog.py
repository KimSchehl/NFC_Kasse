"""
Tenant catalog and per-category rights — shared by the routers.

Categories, articles and rights belong to the tenant (Veranstalter). An event
only switches categories and articles on: a row in event_category /
event_product means "shown and bookable in this event". event_product holds
base articles only; an option follows its base, so the id to look up is
COALESCE(group_id, id).
"""

MANAGER_PERMS = ("categories.create", "categories.edit", "categories.deactivate", "categories.delete")

ACCESS_FLAGS = (
    "can_book", "can_storno_5min", "can_storno_unlimited",
    "can_create_article", "can_edit_article", "can_deactivate_article", "can_delete_article",
)
FULL_ACCESS = {flag: True for flag in ACCESS_FLAGS}

# For queries on `product p`: true when the article (or, for an option, its
# base) is switched on in the event bound to the placeholder.
PRODUCT_IN_EVENT_SQL = "COALESCE(p.group_id, p.id) IN (SELECT product_id FROM event_product WHERE event_id = ?)"
# Same for `category c`.
CATEGORY_IN_EVENT_SQL = "c.id IN (SELECT category_id FROM event_category WHERE event_id = ?)"


def is_manager(db, user_id: int) -> bool:
    """Any category-management permission makes a user a manager: full
    access to every category, without per-category rows."""
    placeholders = ",".join("?" * len(MANAGER_PERMS))
    return db.execute(
        f"SELECT 1 FROM user_permission WHERE user_id=? AND permission_id IN ({placeholders}) LIMIT 1",
        (user_id, *MANAGER_PERMS),
    ).fetchone() is not None


def category_access(db, user_id: int, category_id: int) -> dict | None:
    """The user's 7 flags for this category, or None without a row."""
    row = db.execute(
        f"SELECT {', '.join(ACCESS_FLAGS)} FROM user_category_access WHERE user_id=? AND category_id=?",
        (user_id, category_id),
    ).fetchone()
    return {flag: bool(row[flag]) for flag in ACCESS_FLAGS} if row else None


def tenant_category(db, tenant_id: int, category_id: int):
    """The category row if it belongs to the tenant and isn't deleted."""
    return db.execute(
        "SELECT * FROM category WHERE id=? AND tenant_id=? AND deleted=0",
        (category_id, tenant_id),
    ).fetchone()


def tenant_product(db, tenant_id: int, product_id: int):
    """The product row (plus its category's tenant) if it belongs to the
    tenant and isn't deleted."""
    return db.execute(
        """
        SELECT p.* FROM product p
        JOIN category c ON c.id = p.category_id
        WHERE p.id=? AND c.tenant_id=? AND p.deleted=0
        """,
        (product_id, tenant_id),
    ).fetchone()


def category_in_event(db, event_id: int, category_id: int) -> bool:
    return db.execute(
        "SELECT 1 FROM event_category WHERE event_id=? AND category_id=?", (event_id, category_id)
    ).fetchone() is not None


def product_in_event(db, event_id: int, product) -> bool:
    """`product` is a row with id and group_id."""
    base_id = product["group_id"] if product["group_id"] is not None else product["id"]
    return db.execute(
        "SELECT 1 FROM event_product WHERE event_id=? AND product_id=?", (event_id, base_id)
    ).fetchone() is not None


def _touch_products(db, base_ids: list[int]) -> None:
    """Bumps updated_at so other devices' /changed poll picks the change up."""
    if not base_ids:
        return
    placeholders = ",".join("?" * len(base_ids))
    db.execute(
        f"UPDATE product SET updated_at=datetime('now') WHERE id IN ({placeholders}) OR group_id IN ({placeholders})",
        (*base_ids, *base_ids),
    )


def set_category_in_event(db, event_id: int, category_id: int, active: bool) -> None:
    """Switching a category on for the first time in an event also switches
    on all its articles — otherwise it would show up empty. A category that
    was on before keeps its article selection."""
    if not active:
        db.execute("DELETE FROM event_category WHERE event_id=? AND category_id=?", (event_id, category_id))
        return
    db.execute("INSERT OR IGNORE INTO event_category (event_id, category_id) VALUES (?, ?)", (event_id, category_id))
    base_ids = [r["id"] for r in db.execute(
        "SELECT id FROM product WHERE category_id=? AND group_id IS NULL AND deleted=0", (category_id,)
    ).fetchall()]
    if not base_ids:
        return
    placeholders = ",".join("?" * len(base_ids))
    already = db.execute(
        f"SELECT 1 FROM event_product WHERE event_id=? AND product_id IN ({placeholders}) LIMIT 1",
        (event_id, *base_ids),
    ).fetchone()
    if not already:
        db.executemany(
            "INSERT OR IGNORE INTO event_product (event_id, product_id) VALUES (?, ?)",
            [(event_id, pid) for pid in base_ids],
        )
        _touch_products(db, base_ids)


def set_product_in_event(db, event_id: int, base_id: int, active: bool) -> None:
    if active:
        db.execute("INSERT OR IGNORE INTO event_product (event_id, product_id) VALUES (?, ?)", (event_id, base_id))
    else:
        db.execute("DELETE FROM event_product WHERE event_id=? AND product_id=?", (event_id, base_id))
    _touch_products(db, [base_id])
