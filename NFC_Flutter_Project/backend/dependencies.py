import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import TypedDict

import bcrypt
from fastapi import Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

from config import ACCESS_TOKEN_EXPIRE_MINUTES, ALGORITHM, REFRESH_TOKEN_EXPIRE_DAYS, SECRET_KEY
from database import get_db
from logging_config import user_ctx

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login/form")


# ---------------------------------------------------------------------------
# Password utilities
# ---------------------------------------------------------------------------

def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


# ---------------------------------------------------------------------------
# JWT — access token
# ---------------------------------------------------------------------------

def create_access_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "type": "access",
        "exp": datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def _decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Ungültiges oder abgelaufenes Token")
    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Ungültiger Token-Typ")
    return payload


# ---------------------------------------------------------------------------
# Refresh token — opaque random string, hashed in DB
# ---------------------------------------------------------------------------

def create_refresh_token() -> str:
    """Returns a plaintext refresh token (64-char hex). Store only the hash."""
    return secrets.token_hex(32)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------------------------
# FastAPI dependencies
# ---------------------------------------------------------------------------

def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    payload = _decode_access_token(token)
    user_id = int(payload["sub"])
    with get_db() as db:
        user = db.execute(
            "SELECT * FROM user WHERE id=? AND active=1", (user_id,)
        ).fetchone()
    if not user:
        raise HTTPException(status_code=401, detail="Benutzer nicht gefunden oder inaktiv")
    user_dict = dict(user)
    user_ctx.set({"id": user_dict["id"], "username": user_dict["username"]})
    return user_dict


def get_current_user_optional(request: Request) -> dict | None:
    """Like get_current_user, but returns None instead of raising when no/invalid
    token is present. Used only by endpoints that must also work for
    unauthenticated/pre-login clients (e.g. POST /api/logs/ingest — a client
    should be able to ship a login-failure log even though it isn't logged in)."""
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return None
    try:
        return get_current_user(auth[7:])
    except HTTPException:
        return None


def get_active_event(current_user: dict = Depends(get_current_user)) -> dict:
    """Returns the active event for the current user's tenant."""
    with get_db() as db:
        event = db.execute(
            "SELECT * FROM event WHERE tenant_id=? AND active=1",
            (current_user["tenant_id"],)
        ).fetchone()
    if not event:
        raise HTTPException(status_code=400, detail="Kein aktives Event für diesen Mandanten gefunden")
    return dict(event)


# ---------------------------------------------------------------------------
# Request context — returned by require_permission()
# ---------------------------------------------------------------------------

class RequestContext(TypedDict):
    user: dict
    event: dict


def require_permission(permission_id: str):
    """
    Dependency factory. Returns a dependency that:
    1. Validates the bearer token
    2. Checks the user has the given permission on the active event
    3. Returns RequestContext(user, event) for use in the endpoint
    """
    def checker(
        current_user: dict = Depends(get_current_user),
        active_event: dict = Depends(get_active_event),
    ) -> RequestContext:
        with get_db() as db:
            row = db.execute(
                """
                SELECT 1 FROM user_permission
                WHERE user_id=? AND event_id=? AND permission_id=?
                """,
                (current_user["id"], active_event["id"], permission_id),
            ).fetchone()
            if row:
                return RequestContext(user=current_user, event=active_event)

            # permission_node.label is the same German display label the
            # permission-tree endpoint already exposes to the UI — reuse it
            # here so a 403 shows a real name instead of a raw ID like
            # "guthaben.topup".
            label_row = db.execute(
                "SELECT label FROM permission_node WHERE id=?", (permission_id,)
            ).fetchone()
            label = label_row["label"] if label_row else permission_id
            raise HTTPException(
                status_code=403,
                detail=f"Berechtigung '{label}' erforderlich",
            )

    return checker
