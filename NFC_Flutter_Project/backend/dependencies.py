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
        # Users of a Veranstalter that isn't active any more (switched in the
        # admin tool) are logged out right away, not when their token expires.
        user = db.execute(
            """
            SELECT u.* FROM user u JOIN tenant t ON t.id = u.tenant_id
            WHERE u.id=? AND u.active=1 AND u.deleted=0 AND t.active=1
            """,
            (user_id,),
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


class EventChangedError(Exception):
    """
    A fest was started or ended (admin tool, admin_cli.py) while this
    request was in flight, or the client is still on the previous fest's
    articles. main.py turns it into a 409 with code "event_changed", which
    makes the app reload its event-scoped data right away.
    """

    def __init__(self, message: str = "Das Fest wurde gerade gewechselt. Die Kasse lädt neu – bitte noch einmal versuchen."):
        super().__init__(message)


NOT_IN_EVENT = "Ein Artikel ist in diesem Fest nicht mehr aktiv. Die Kasse lädt neu – bitte noch einmal versuchen."


def ensure_event_active(db, event_id: int) -> None:
    """
    Call first thing inside get_db(exclusive=True) in every endpoint that
    writes rows for ctx["event"]. get_active_event() runs before that lock
    is taken, so a fest switch committing in between would otherwise let
    the write land in the event that was just ended — after its last period
    was closed, i.e. outside every period of its statistics.
    """
    row = db.execute("SELECT active FROM event WHERE id=?", (event_id,)).fetchone()
    if not row or not row["active"]:
        raise EventChangedError()


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


def user_has_permission(db, user_id: int, permission_id: str) -> bool:
    """Global permissions belong to the user, not to a fest."""
    return db.execute(
        "SELECT 1 FROM user_permission WHERE user_id=? AND permission_id=?",
        (user_id, permission_id),
    ).fetchone() is not None


def raise_if_missing_permission(db, user_id: int, permission_id: str) -> None:
    if user_has_permission(db, user_id, permission_id):
        return
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


def require_permission(permission_id: str):
    """
    Dependency factory. Returns a dependency that:
    1. Validates the bearer token
    2. Checks the user has the given (global) permission
    3. Returns RequestContext(user, event) — event = the active event, for
       endpoints that read or write event-scoped data
    """
    def checker(
        current_user: dict = Depends(get_current_user),
        active_event: dict = Depends(get_active_event),
    ) -> RequestContext:
        with get_db() as db:
            raise_if_missing_permission(db, current_user["id"], permission_id)
        return RequestContext(user=current_user, event=active_event)

    return checker
