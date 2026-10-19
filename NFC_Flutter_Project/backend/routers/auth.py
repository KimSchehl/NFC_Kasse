import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm

import catalog
from database import get_db
from dependencies import (
    create_access_token,
    create_refresh_token,
    get_active_event,
    get_current_user,
    hash_refresh_token,
    verify_password,
    ACCESS_TOKEN_EXPIRE_MINUTES,
    REFRESH_TOKEN_EXPIRE_DAYS,
)
from schemas import CategoryPermissionResponse, LoginRequest, MeResponse, RefreshRequest, TokenResponse

router = APIRouter(prefix="/api/auth", tags=["auth"])
logger = logging.getLogger(__name__)


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
            # Locally only the active Veranstalter's users can log in — the same
            # username may exist at another Veranstalter.
            """
            SELECT u.* FROM user u JOIN tenant t ON t.id = u.tenant_id
            WHERE u.username=? AND u.active=1 AND u.deleted=0 AND t.active=1
            """,
            (body.username,),
        ).fetchone()

    if not user or not verify_password(body.password, user["password_hash"]):
        logger.warning("Login failed: username=%s", body.username)
        raise HTTPException(status_code=401, detail="Benutzername oder Passwort ungültig")

    logger.info("Login success: username=%s user_id=%s", body.username, user["id"])
    access_token, refresh_token = _build_token_response(user["id"])
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


# Also accept OAuth2 form data so the Swagger UI "Authorize" button works
@router.post("/login/form", response_model=TokenResponse, include_in_schema=False)
def login_form(form_data: OAuth2PasswordRequestForm = Depends()):
    """Hidden endpoint used exclusively by the Swagger UI Authorize dialog."""
    with get_db() as db:
        user = db.execute(
            # Locally only the active Veranstalter's users can log in — the same
            # username may exist at another Veranstalter.
            """
            SELECT u.* FROM user u JOIN tenant t ON t.id = u.tenant_id
            WHERE u.username=? AND u.active=1 AND u.deleted=0 AND t.active=1
            """,
            (form_data.username,),
        ).fetchone()

    if not user or not verify_password(form_data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Benutzername oder Passwort ungültig")

    access_token, refresh_token = _build_token_response(user["id"])
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest):
    token_hash = hash_refresh_token(body.refresh_token)

    with get_db() as db:
        row = db.execute(
            """
            SELECT rt.*, u.active AND NOT u.deleted AND t.active AS user_active
            FROM refresh_token rt
            JOIN user u ON rt.user_id = u.id
            JOIN tenant t ON t.id = u.tenant_id
            WHERE rt.token_hash=?
            """,
            (token_hash,),
        ).fetchone()

        if not row:
            logger.warning("Refresh failed: token not found (possibly forged/garbage)")
            raise HTTPException(status_code=401, detail="Refresh-Token nicht gefunden")
        if row["revoked"]:
            # A revoked token being reused is exactly the signal token rotation
            # exists to surface — could mean a stolen token is in play.
            logger.warning(
                "Refresh token reuse detected: already-revoked token for user_id=%s",
                row["user_id"],
            )
            raise HTTPException(status_code=401, detail="Refresh-Token wurde widerrufen")
        if not row["user_active"]:
            raise HTTPException(status_code=401, detail="Benutzer ist inaktiv")

        expires_at = datetime.fromisoformat(row["expires_at"])
        if datetime.now(timezone.utc) > expires_at.replace(tzinfo=timezone.utc):
            raise HTTPException(status_code=401, detail="Refresh-Token abgelaufen")

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
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60,
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
    logger.info("Logout")


@router.get("/me", response_model=MeResponse)
def me(
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    """Permissions are the user's own (valid in every fest); categories are
    those switched on in the running fest that the user has rights in —
    managers get every switched-on category with full rights."""
    event_id = active_event["id"]
    with get_db() as db:
        permissions = [
            r["permission_id"]
            for r in db.execute(
                "SELECT permission_id FROM user_permission WHERE user_id=?", (current_user["id"],)
            ).fetchall()
        ]
        is_manager = any(p in permissions for p in catalog.MANAGER_PERMS)
        if is_manager:
            rows = db.execute(
                f"""
                SELECT c.id AS category_id, c.name AS category_name
                FROM category c
                WHERE c.tenant_id=? AND c.deleted=0 AND {catalog.CATEGORY_IN_EVENT_SQL}
                ORDER BY c.sort_order, c.id
                """,
                (current_user["tenant_id"], event_id),
            ).fetchall()
            categories = [
                CategoryPermissionResponse(category_id=r["category_id"], category_name=r["category_name"], **catalog.FULL_ACCESS)
                for r in rows
            ]
        else:
            rows = db.execute(
                f"""
                SELECT c.id AS category_id, c.name AS category_name, {", ".join("uca." + f for f in catalog.ACCESS_FLAGS)}
                FROM user_category_access uca
                JOIN category c ON c.id = uca.category_id
                WHERE uca.user_id=? AND c.deleted=0 AND {catalog.CATEGORY_IN_EVENT_SQL}
                ORDER BY c.sort_order, c.id
                """,
                (current_user["id"], event_id),
            ).fetchall()
            categories = [
                CategoryPermissionResponse(
                    category_id=r["category_id"],
                    category_name=r["category_name"],
                    **{f: bool(r[f]) for f in catalog.ACCESS_FLAGS},
                )
                for r in rows
            ]

    with get_db() as db:
        can_manage_articles = is_manager or db.execute(
            """
            SELECT 1 FROM user_category_access uca JOIN category c ON c.id = uca.category_id
            WHERE uca.user_id=? AND c.deleted=0 AND (uca.can_create_article=1 OR uca.can_edit_article=1
                  OR uca.can_deactivate_article=1 OR uca.can_delete_article=1)
            LIMIT 1
            """,
            (current_user["id"],),
        ).fetchone() is not None

    from config import LEADERBOARD_ENABLED, PAGER_ENABLED
    return MeResponse(
        id=current_user["id"],
        username=current_user["username"],
        display_name=current_user["display_name"],
        permissions=permissions,
        categories=categories,
        leaderboard_enabled=LEADERBOARD_ENABLED,
        pager_enabled=PAGER_ENABLED,
        event_name=active_event["name"],
        event_is_intern=bool(active_event["is_intern"]),
        can_manage_articles=can_manage_articles,
    )
