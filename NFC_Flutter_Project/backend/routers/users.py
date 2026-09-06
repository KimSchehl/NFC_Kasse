import logging

from fastapi import APIRouter, Depends, HTTPException

from database import get_db
from dependencies import RequestContext, hash_password, require_permission
from schemas import (
    CategoryAccessItem,
    CategoryAccessUpdate,
    CategoryPermissionResponse,
    PermissionsUpdate,
    RoleTemplateResponse,
    UserActiveUpdate,
    UserCreate,
    UserPermissionsResponse,
    UserResponse,
    UserUpdate,
)

router = APIRouter(prefix="/api/users", tags=["users"])
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# User CRUD
# ---------------------------------------------------------------------------

def _blocks_last_manager(db, user_id: int, event_id: int) -> bool:
    """True if deactivating/deleting `user_id` would leave nobody with
    users.manage_permissions for this event -- otherwise no one could ever
    fix a permissions mistake again short of direct DB access (same class of
    self-lockout as the kiosk.access admin bug elsewhere in this project).
    A no-op (returns False) if the user doesn't even hold that permission."""
    holds_it = db.execute(
        "SELECT 1 FROM user_permission WHERE user_id=? AND event_id=? AND permission_id='users.manage_permissions'",
        (user_id, event_id),
    ).fetchone()
    if not holds_it:
        return False
    other = db.execute(
        """
        SELECT COUNT(*) as cnt
        FROM user_permission up
        JOIN user u ON u.id = up.user_id
        WHERE up.permission_id = 'users.manage_permissions' AND up.event_id = ?
          AND u.active = 1 AND u.deleted = 0 AND u.id != ?
        """,
        (event_id, user_id),
    ).fetchone()
    return other["cnt"] == 0


@router.get("/", response_model=list[UserResponse])
def list_users(ctx: RequestContext = Depends(require_permission("users.view"))):
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        rows = db.execute(
            "SELECT id, username, display_name, active FROM user WHERE tenant_id=? AND deleted=0 ORDER BY username",
            (tenant_id,),
        ).fetchall()
    return [UserResponse(**dict(r)) for r in rows]


@router.post("/", response_model=UserResponse, status_code=201)
def create_user(
    body: UserCreate,
    ctx: RequestContext = Depends(require_permission("users.create")),
):
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        existing = db.execute(
            "SELECT id FROM user WHERE tenant_id=? AND username=? AND deleted=0",
            (tenant_id, body.username),
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Benutzername bereits vergeben")

        cursor = db.execute(
            "INSERT INTO user (tenant_id, username, password_hash, display_name) VALUES (?, ?, ?, ?)",
            (tenant_id, body.username, hash_password(body.password), body.display_name),
        )
        new_id = cursor.lastrowid

    logger.info(
        "User created: user_id=%s username=%s by=%s",
        new_id, body.username, ctx["user"]["username"],
    )
    return UserResponse(
        id=new_id,
        username=body.username,
        display_name=body.display_name,
        active=True,
    )


@router.put("/{user_id}", response_model=UserResponse)
def update_user(
    user_id: int,
    body: UserUpdate,
    ctx: RequestContext = Depends(require_permission("users.edit")),
):
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        row = db.execute(
            "SELECT * FROM user WHERE id=? AND tenant_id=? AND deleted=0",
            (user_id, tenant_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        # Check for duplicate username if changing it
        if body.username and body.username != row["username"]:
            dup = db.execute(
                "SELECT id FROM user WHERE tenant_id=? AND username=? AND id!=? AND deleted=0",
                (tenant_id, body.username, user_id),
            ).fetchone()
            if dup:
                raise HTTPException(status_code=409, detail="Benutzername bereits vergeben")

        new_username = body.username or row["username"]
        new_display = body.display_name if body.display_name is not None else row["display_name"]
        new_hash = hash_password(body.password) if body.password else row["password_hash"]

        db.execute(
            "UPDATE user SET username=?, password_hash=?, display_name=? WHERE id=?",
            (new_username, new_hash, new_display, user_id),
        )

    logger.info(
        "User updated: user_id=%s username=%s password_changed=%s by=%s",
        user_id, new_username, bool(body.password), ctx["user"]["username"],
    )
    return UserResponse(
        id=user_id,
        username=new_username,
        display_name=new_display,
        active=bool(row["active"]),
    )


@router.patch("/{user_id}/active", response_model=UserResponse)
def set_user_active(
    user_id: int,
    body: UserActiveUpdate,
    ctx: RequestContext = Depends(require_permission("users.deactivate")),
):
    """Toggles active in both directions -- deactivate AND reactivate go
    through here, mirroring products.py's PATCH /{id}/active."""
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    current_user_id = ctx["user"]["id"]

    if user_id == current_user_id and not body.active:
        raise HTTPException(status_code=400, detail="Eigenes Konto kann nicht deaktiviert werden")

    with get_db() as db:
        row = db.execute(
            "SELECT id, username, display_name FROM user WHERE id=? AND tenant_id=? AND deleted=0",
            (user_id, tenant_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        if not body.active and _blocks_last_manager(db, user_id, event_id):
            raise HTTPException(
                status_code=400,
                detail="Letzter Benutzer mit Benutzerverwaltungs-Rechten kann nicht deaktiviert werden",
            )

        db.execute("UPDATE user SET active=? WHERE id=?", (1 if body.active else 0, user_id))

    logger.warning(
        "User %s: user_id=%s by=%s",
        "reactivated" if body.active else "deactivated",
        user_id, ctx["user"]["username"],
    )
    return UserResponse(
        id=user_id, username=row["username"], display_name=row["display_name"], active=body.active,
    )


@router.delete("/{user_id}", status_code=204)
def delete_user(
    user_id: int,
    ctx: RequestContext = Depends(require_permission("users.delete")),
):
    """Soft-delete, mirroring products.py's delete_product -- the row stays
    for sale.booked_by/user_permission.granted_by/etc. audit trails, just
    hidden from every normal query (deleted=0 filter). The username is
    renamed to free it up for reuse (see _blocks_last_manager's neighbor
    comment in main.py's migration for why: relaxing the UNIQUE(tenant_id,
    username) constraint isn't safely doable with foreign_keys=ON)."""
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    current_user_id = ctx["user"]["id"]

    if user_id == current_user_id:
        raise HTTPException(status_code=400, detail="Eigenes Konto kann nicht gelöscht werden")

    with get_db() as db:
        row = db.execute(
            "SELECT id, username FROM user WHERE id=? AND tenant_id=? AND deleted=0",
            (user_id, tenant_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        if _blocks_last_manager(db, user_id, event_id):
            raise HTTPException(
                status_code=400,
                detail="Letzter Benutzer mit Benutzerverwaltungs-Rechten kann nicht gelöscht werden",
            )

        renamed = f"{row['username']}__geloescht_{user_id}"
        db.execute(
            "UPDATE user SET deleted=1, active=0, username=? WHERE id=?",
            (renamed, user_id),
        )

    logger.warning(
        "User deleted: user_id=%s (was %s) by=%s", user_id, row["username"], ctx["user"]["username"],
    )


# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

@router.get("/{user_id}/permissions", response_model=UserPermissionsResponse)
def get_user_permissions(
    user_id: int,
    ctx: RequestContext = Depends(require_permission("users.manage_permissions")),
):
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]

    with get_db() as db:
        user_row = db.execute(
            "SELECT id, username, display_name, active FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        perm_rows = db.execute(
            "SELECT permission_id FROM user_permission WHERE user_id=? AND event_id=?",
            (user_id, event_id),
        ).fetchall()
        cat_rows = db.execute(
            """
            SELECT uca.category_id, c.name as category_name,
                   uca.can_book, uca.can_storno_5min, uca.can_storno_unlimited,
                   uca.can_create_article, uca.can_edit_article,
                   uca.can_deactivate_article, uca.can_delete_article
            FROM user_category_access uca
            JOIN category c ON c.id = uca.category_id
            WHERE uca.user_id=? AND uca.event_id=?
            ORDER BY c.sort_order
            """,
            (user_id, event_id),
        ).fetchall()

    return UserPermissionsResponse(
        user=UserResponse(**dict(user_row)),
        permissions=[r["permission_id"] for r in perm_rows],
        categories=[
            CategoryPermissionResponse(
                category_id=r["category_id"],
                category_name=r["category_name"],
                can_book=bool(r["can_book"]),
                can_storno_5min=bool(r["can_storno_5min"]),
                can_storno_unlimited=bool(r["can_storno_unlimited"]),
                can_create_article=bool(r["can_create_article"]),
                can_edit_article=bool(r["can_edit_article"]),
                can_deactivate_article=bool(r["can_deactivate_article"]),
                can_delete_article=bool(r["can_delete_article"]),
            )
            for r in cat_rows
        ],
    )


@router.put("/{user_id}/permissions", status_code=204)
def set_user_permissions(
    user_id: int,
    body: PermissionsUpdate,
    ctx: RequestContext = Depends(require_permission("users.manage_permissions")),
):
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    granter_id = ctx["user"]["id"]

    with get_db() as db:
        user_row = db.execute(
            "SELECT id FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        # Validate all permission IDs exist
        for perm_id in body.permission_ids:
            valid = db.execute(
                "SELECT 1 FROM permission_node WHERE id=? AND node_type != 'group'",
                (perm_id,),
            ).fetchone()
            if not valid:
                raise HTTPException(status_code=400, detail=f"Ungültige Berechtigung: '{perm_id}'")

        # Full replace pattern: delete all existing rows then insert the new set
        # in one transaction. Simpler than a diff-merge and less error-prone —
        # the client always sends the complete desired state.
        db.execute(
            "DELETE FROM user_permission WHERE user_id=? AND event_id=?",
            (user_id, event_id),
        )
        for perm_id in body.permission_ids:
            db.execute(
                """
                INSERT INTO user_permission (user_id, event_id, permission_id, granted_by)
                VALUES (?, ?, ?, ?)
                """,
                (user_id, event_id, perm_id, granter_id),
            )

    logger.info(
        "Permissions changed: user_id=%s permissions=%s by=%s",
        user_id, body.permission_ids, ctx["user"]["username"],
    )


@router.put("/{user_id}/categories", status_code=204)
def set_user_category_access(
    user_id: int,
    body: CategoryAccessUpdate,
    ctx: RequestContext = Depends(require_permission("users.manage_permissions")),
):
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    granter_id = ctx["user"]["id"]

    with get_db() as db:
        user_row = db.execute(
            "SELECT id FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        for item in body.categories:
            valid = db.execute(
                "SELECT 1 FROM category WHERE id=? AND event_id=? AND deleted=0",
                (item.category_id, event_id),
            ).fetchone()
            if not valid:
                raise HTTPException(
                    status_code=400,
                    detail=f"Kategorie {item.category_id} nicht in diesem Event gefunden",
                )

        # Full replace — same pattern as set_user_permissions above.
        db.execute(
            "DELETE FROM user_category_access WHERE user_id=? AND event_id=?",
            (user_id, event_id),
        )
        for item in body.categories:
            db.execute(
                """
                INSERT INTO user_category_access (
                    user_id, event_id, category_id,
                    can_book, can_storno_5min, can_storno_unlimited,
                    can_create_article, can_edit_article, can_deactivate_article, can_delete_article,
                    granted_by
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id, event_id, item.category_id,
                    1 if item.can_book else 0,
                    1 if item.can_storno_5min else 0,
                    1 if item.can_storno_unlimited else 0,
                    1 if item.can_create_article else 0,
                    1 if item.can_edit_article else 0,
                    1 if item.can_deactivate_article else 0,
                    1 if item.can_delete_article else 0,
                    granter_id,
                ),
            )

    logger.info(
        "Category access changed: user_id=%s category_ids=%s by=%s",
        user_id, [item.category_id for item in body.categories], ctx["user"]["username"],
    )


# ---------------------------------------------------------------------------
# Permission tree — served from DB so no Flutter change needed for new perms
# ---------------------------------------------------------------------------

@router.get("/permission-tree")
def get_permission_tree(ctx: RequestContext = Depends(require_permission("users.manage_permissions"))):
    """
    Returns all leaf permission nodes grouped by their parent label.
    Sorted by parent sort_order, then child sort_order.
    The Flutter edit dialog renders this list without any hardcoded mapping.
    """
    with get_db() as db:
        rows = db.execute(
            """
            SELECT n.id, n.label, n.sort_order,
                   p.label     AS group_label,
                   p.sort_order AS group_sort
            FROM permission_node n
            LEFT JOIN permission_node p ON n.parent_id = p.id
            WHERE n.node_type != 'group'
            ORDER BY p.sort_order, n.sort_order
            """
        ).fetchall()
    return [
        {"id": r["id"], "label": r["label"], "group": r["group_label"] or "Sonstiges"}
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Role templates
# ---------------------------------------------------------------------------

@router.get("/role-templates", response_model=list[RoleTemplateResponse])
def list_role_templates(ctx: RequestContext = Depends(require_permission("users.manage_permissions"))):
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        templates = db.execute(
            "SELECT id, name, description FROM role_template WHERE tenant_id=? ORDER BY name",
            (tenant_id,),
        ).fetchall()

        result = []
        for tmpl in templates:
            perm_rows = db.execute(
                "SELECT permission_id FROM role_template_permission WHERE role_template_id=?",
                (tmpl["id"],),
            ).fetchall()
            result.append(RoleTemplateResponse(
                id=tmpl["id"],
                name=tmpl["name"],
                description=tmpl["description"],
                permission_ids=[r["permission_id"] for r in perm_rows],
            ))
    return result


@router.post("/{user_id}/apply-template/{template_id}", status_code=204)
def apply_role_template(
    user_id: int,
    template_id: int,
    ctx: RequestContext = Depends(require_permission("users.manage_permissions")),
):
    tenant_id = ctx["user"]["tenant_id"]
    event_id = ctx["event"]["id"]
    granter_id = ctx["user"]["id"]

    with get_db() as db:
        user_row = db.execute(
            "SELECT id FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

        template = db.execute(
            "SELECT id FROM role_template WHERE id=? AND tenant_id=?",
            (template_id, tenant_id),
        ).fetchone()
        if not template:
            raise HTTPException(status_code=404, detail="Rollenvorlage nicht gefunden")

        perm_rows = db.execute(
            "SELECT permission_id FROM role_template_permission WHERE role_template_id=?",
            (template_id,),
        ).fetchall()

        # Full replace — removes the user's current permissions and grants the
        # template's permission set. Existing category access is not touched.
        db.execute(
            "DELETE FROM user_permission WHERE user_id=? AND event_id=?",
            (user_id, event_id),
        )
        for row in perm_rows:
            db.execute(
                """
                INSERT INTO user_permission (user_id, event_id, permission_id, granted_by)
                VALUES (?, ?, ?, ?)
                """,
                (user_id, event_id, row["permission_id"], granter_id),
            )

    logger.info(
        "Role template applied: user_id=%s template_id=%s by=%s",
        user_id, template_id, ctx["user"]["username"],
    )
