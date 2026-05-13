from fastapi import APIRouter, Depends, HTTPException

from database import get_db
from dependencies import RequestContext, hash_password, require_permission
from schemas import (
    CategoryAccessItem,
    CategoryAccessUpdate,
    CategoryPermissionResponse,
    PermissionsUpdate,
    RoleTemplateResponse,
    UserCreate,
    UserPermissionsResponse,
    UserResponse,
    UserUpdate,
)

router = APIRouter(prefix="/api/users", tags=["users"])


# ---------------------------------------------------------------------------
# User CRUD
# ---------------------------------------------------------------------------

@router.get("/", response_model=list[UserResponse])
def list_users(ctx: RequestContext = Depends(require_permission("users.view"))):
    tenant_id = ctx["user"]["tenant_id"]
    with get_db() as db:
        rows = db.execute(
            "SELECT id, username, display_name, active FROM user WHERE tenant_id=? ORDER BY username",
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
            "SELECT id FROM user WHERE tenant_id=? AND username=?",
            (tenant_id, body.username),
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Username already exists")

        cursor = db.execute(
            "INSERT INTO user (tenant_id, username, password_hash, display_name) VALUES (?, ?, ?, ?)",
            (tenant_id, body.username, hash_password(body.password), body.display_name),
        )
        new_id = cursor.lastrowid

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
            "SELECT * FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="User not found")

        # Check for duplicate username if changing it
        if body.username and body.username != row["username"]:
            dup = db.execute(
                "SELECT id FROM user WHERE tenant_id=? AND username=? AND id!=?",
                (tenant_id, body.username, user_id),
            ).fetchone()
            if dup:
                raise HTTPException(status_code=409, detail="Username already taken")

        new_username = body.username or row["username"]
        new_display = body.display_name if body.display_name is not None else row["display_name"]
        new_hash = hash_password(body.password) if body.password else row["password_hash"]

        db.execute(
            "UPDATE user SET username=?, password_hash=?, display_name=? WHERE id=?",
            (new_username, new_hash, new_display, user_id),
        )

    return UserResponse(
        id=user_id,
        username=new_username,
        display_name=new_display,
        active=bool(row["active"]),
    )


@router.delete("/{user_id}", status_code=204)
def deactivate_user(
    user_id: int,
    ctx: RequestContext = Depends(require_permission("users.deactivate")),
):
    tenant_id = ctx["user"]["tenant_id"]
    current_user_id = ctx["user"]["id"]

    if user_id == current_user_id:
        raise HTTPException(status_code=400, detail="Cannot deactivate your own account")

    with get_db() as db:
        row = db.execute(
            "SELECT id FROM user WHERE id=? AND tenant_id=?",
            (user_id, tenant_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        db.execute("UPDATE user SET active=0 WHERE id=?", (user_id,))


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
            raise HTTPException(status_code=404, detail="User not found")

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
            raise HTTPException(status_code=404, detail="User not found")

        # Validate all permission IDs exist
        for perm_id in body.permission_ids:
            valid = db.execute(
                "SELECT 1 FROM permission_node WHERE id=? AND node_type != 'group'",
                (perm_id,),
            ).fetchone()
            if not valid:
                raise HTTPException(status_code=400, detail=f"Invalid permission: '{perm_id}'")

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
            raise HTTPException(status_code=404, detail="User not found")

        for item in body.categories:
            valid = db.execute(
                "SELECT 1 FROM category WHERE id=? AND event_id=? AND deleted=0",
                (item.category_id, event_id),
            ).fetchone()
            if not valid:
                raise HTTPException(
                    status_code=400,
                    detail=f"Category {item.category_id} not found for this event",
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
            raise HTTPException(status_code=404, detail="User not found")

        template = db.execute(
            "SELECT id FROM role_template WHERE id=? AND tenant_id=?",
            (template_id, tenant_id),
        ).fetchone()
        if not template:
            raise HTTPException(status_code=404, detail="Role template not found")

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
