from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm

from database import get_db
from dependencies import (
    create_access_token,
    create_refresh_token,
    get_active_event,
    get_current_user,
    hash_refresh_token,
    verify_password,
    REFRESH_TOKEN_EXPIRE_DAYS,
)
from schemas import CategoryPermissionResponse, LoginRequest, MeResponse, RefreshRequest, TokenResponse

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _build_token_response(user_id: int) -> tuple[str, str]:
    """
    Creates a new access + refresh token pair and persists the hashed refresh
    token in the database.

    Returns (access_token_plaintext, refresh_token_plaintext). The refresh
    token plaintext is sent to the client; only its SHA-256 hash is stored,
    so a DB leak does not expose valid session tokens.
    """
    """Creates a new access + refresh token pair and stores the refresh token in DB."""
    access_token = create_access_token(user_id)
    refresh_token_plain = create_refresh_token()
    refresh_token_hash = hash_refresh_token(refresh_token_plain)
    expires_at = (datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)).isoformat()

    with get_db() as db:
        db.execute(
            """
            INSERT INTO refresh_token (user_id, token_hash, expires_at)
            VALUES (?, ?, ?)
            """,
            (user_id, refresh_token_hash, expires_at),
        )
    return access_token, refresh_token_plain


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest):
    with get_db() as db:
        user = db.execute(
            "SELECT * FROM user WHERE username=? AND active=1", (body.username,)
        ).fetchone()

    if not user or not verify_password(body.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    access_token, refresh_token = _build_token_response(user["id"])
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=3600,
    )


# Also accept OAuth2 form data so the Swagger UI "Authorize" button works
@router.post("/login/form", response_model=TokenResponse, include_in_schema=False)
def login_form(form_data: OAuth2PasswordRequestForm = Depends()):
    """Hidden endpoint used exclusively by the Swagger UI Authorize dialog."""
    with get_db() as db:
        user = db.execute(
            "SELECT * FROM user WHERE username=? AND active=1", (form_data.username,)
        ).fetchone()

    if not user or not verify_password(form_data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    access_token, refresh_token = _build_token_response(user["id"])
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=3600,
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest):
    token_hash = hash_refresh_token(body.refresh_token)

    with get_db() as db:
        row = db.execute(
            """
            SELECT rt.*, u.active as user_active
            FROM refresh_token rt
            JOIN user u ON rt.user_id = u.id
            WHERE rt.token_hash=?
            """,
            (token_hash,),
        ).fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Refresh token not found")
        if row["revoked"]:
            raise HTTPException(status_code=401, detail="Refresh token has been revoked")
        if not row["user_active"]:
            raise HTTPException(status_code=401, detail="User is inactive")

        expires_at = datetime.fromisoformat(row["expires_at"])
        if datetime.now(timezone.utc) > expires_at.replace(tzinfo=timezone.utc):
            raise HTTPException(status_code=401, detail="Refresh token expired")

        # Token rotation: revoke the consumed token before issuing a new one.
        # This limits a stolen refresh token to a single extra use — the
        # legitimate client will notice its token was revoked on the next
        # refresh attempt.
        db.execute(
            "UPDATE refresh_token SET revoked=1 WHERE token_hash=?",
            (token_hash,),
        )

    access_token, new_refresh_token = _build_token_response(row["user_id"])
    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        expires_in=3600,
    )


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest):
    token_hash = hash_refresh_token(body.refresh_token)
    with get_db() as db:
        db.execute(
            "UPDATE refresh_token SET revoked=1 WHERE token_hash=?",
            (token_hash,),
        )
    # No error if token wasn't found — idempotent logout


@router.get("/me", response_model=MeResponse)
def me(
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    event_id = active_event["id"]
    with get_db() as db:
        perm_rows = db.execute(
            "SELECT permission_id FROM user_permission WHERE user_id=? AND event_id=?",
            (current_user["id"], event_id),
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
            (current_user["id"], event_id),
        ).fetchall()

    permissions = [r["permission_id"] for r in perm_rows]

    # Managers (any category-management permission) bypass per-category access
    # rows and see every category with full rights.
    is_manager = any(
        p in permissions
        for p in ("categories.create", "categories.edit", "categories.deactivate", "categories.delete")
    )
    if is_manager:
        with get_db() as db:
            all_cats = db.execute(
                "SELECT id, name FROM category WHERE event_id=? AND deleted=0 ORDER BY sort_order",
                (event_id,),
            ).fetchall()
        categories = [
            CategoryPermissionResponse(
                category_id=r["id"], category_name=r["name"],
                can_book=True, can_storno_5min=True, can_storno_unlimited=True,
                can_create_article=True, can_edit_article=True,
                can_deactivate_article=True, can_delete_article=True,
            )
            for r in all_cats
        ]
    else:
        categories = [
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
        ]

    return MeResponse(
        id=current_user["id"],
        username=current_user["username"],
        display_name=current_user["display_name"],
        permissions=permissions,
        categories=categories,
    )
