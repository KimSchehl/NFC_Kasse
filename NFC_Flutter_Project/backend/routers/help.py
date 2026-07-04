"""
Help / Mayday system.

Any logged-in user can press HILFE — this creates a help_request and broadcasts
it in real-time via WebSocket to all connected clients.  Users with the
'help.receive' permission (Notfall-Kontakt) can respond with on_way / 5min /
cannot.  The requester sees responses immediately; other responders are notified
so they know if someone is already handling it.
"""

import json

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from jose import JWTError, jwt

from database import get_db
from dependencies import ALGORITHM, SECRET_KEY, get_active_event, get_current_user
from schemas import HelpRespondBody

router = APIRouter(prefix="/api/help", tags=["help"])


# ---------------------------------------------------------------------------
# Connection manager
# ---------------------------------------------------------------------------

class _HelpManager:
    def __init__(self) -> None:
        self._connections: dict[int, WebSocket] = {}

    async def connect(self, user_id: int, ws: WebSocket) -> None:
        await ws.accept()
        self._connections[user_id] = ws

    def disconnect(self, user_id: int) -> None:
        self._connections.pop(user_id, None)

    async def broadcast(self, message: dict) -> None:
        dead: list[int] = []
        for uid, ws in list(self._connections.items()):
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self._connections.pop(uid, None)


_manager = _HelpManager()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_active_requests(db, event_id: int) -> list[dict]:
    reqs = db.execute(
        """SELECT r.id, r.requester_id,
                  COALESCE(u.display_name, u.username) AS requester_name,
                  r.created_at
           FROM help_request r
           JOIN user u ON u.id = r.requester_id
           WHERE r.event_id = ? AND r.status = 'active'
           ORDER BY r.created_at""",
        (event_id,),
    ).fetchall()

    result = []
    for req in reqs:
        responses = db.execute(
            """SELECT hr.responder_id,
                      COALESCE(u.display_name, u.username) AS responder_name,
                      hr.response, hr.created_at
               FROM help_response hr
               JOIN user u ON u.id = hr.responder_id
               WHERE hr.request_id = ?
               ORDER BY hr.created_at""",
            (req["id"],),
        ).fetchall()
        result.append({
            "id": req["id"],
            "requester_id": req["requester_id"],
            "requester_name": req["requester_name"],
            "created_at": req["created_at"],
            "responses": [dict(r) for r in responses],
        })
    return result


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------

@router.websocket("/ws")
async def ws_endpoint(ws: WebSocket, token: str = Query(...)) -> None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "access":
            await ws.close(code=1008)
            return
        user_id = int(payload["sub"])
    except (JWTError, ValueError, TypeError):
        await ws.close(code=1008)
        return

    with get_db() as db:
        user = db.execute(
            "SELECT id FROM user WHERE id=? AND active=1", (user_id,)
        ).fetchone()
        if not user:
            await ws.close(code=1008)
            return
        event = db.execute("SELECT id FROM event WHERE active=1 LIMIT 1").fetchone()
        event_id = event["id"] if event else 1
        active = _load_active_requests(db, event_id)

    await _manager.connect(user_id, ws)
    try:
        await ws.send_json({"type": "init", "requests": active})
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
                if msg.get("type") == "ping":
                    await ws.send_json({"type": "pong"})
            except Exception:
                pass
    except WebSocketDisconnect:
        _manager.disconnect(user_id)
    except Exception:
        _manager.disconnect(user_id)


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@router.post("/request", status_code=201)
async def create_request(
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
) -> dict:
    user_id = current_user["id"]
    event_id = active_event["id"]
    requester_name = current_user.get("display_name") or current_user["username"]

    with get_db() as db:
        db.execute(
            "UPDATE help_request SET status='resolved' "
            "WHERE requester_id=? AND event_id=? AND status='active'",
            (user_id, event_id),
        )
        cursor = db.execute(
            "INSERT INTO help_request (event_id, requester_id) VALUES (?, ?)",
            (event_id, user_id),
        )
        request_id = cursor.lastrowid
        created_at = db.execute(
            "SELECT created_at FROM help_request WHERE id=?", (request_id,)
        ).fetchone()["created_at"]

    await _manager.broadcast({
        "type": "new_request",
        "request": {
            "id": request_id,
            "requester_id": user_id,
            "requester_name": requester_name,
            "created_at": created_at,
            "responses": [],
        },
    })
    return {"id": request_id}


@router.post("/{request_id}/respond")
async def respond(
    request_id: int,
    body: HelpRespondBody,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
) -> dict:
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        perm = db.execute(
            "SELECT 1 FROM user_permission "
            "WHERE user_id=? AND event_id=? AND permission_id='help.receive'",
            (user_id, event_id),
        ).fetchone()
        if not perm:
            raise HTTPException(403, "Berechtigung 'help.receive' erforderlich")

        req = db.execute(
            "SELECT id FROM help_request WHERE id=? AND status='active'",
            (request_id,),
        ).fetchone()
        if not req:
            raise HTTPException(404, "Hilferuf nicht gefunden oder bereits erledigt")

        db.execute(
            """INSERT INTO help_response (request_id, responder_id, response)
               VALUES (?, ?, ?)
               ON CONFLICT(request_id, responder_id)
               DO UPDATE SET response = excluded.response""",
            (request_id, user_id, body.response),
        )

    responder_name = current_user.get("display_name") or current_user["username"]
    await _manager.broadcast({
        "type": "new_response",
        "request_id": request_id,
        "response": {
            "responder_id": user_id,
            "responder_name": responder_name,
            "response": body.response,
        },
    })
    return {"ok": True}


@router.delete("/{request_id}", status_code=204)
async def resolve(
    request_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
) -> None:
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        req = db.execute(
            "SELECT requester_id FROM help_request WHERE id=? AND status='active'",
            (request_id,),
        ).fetchone()
        if not req:
            raise HTTPException(404, "Hilferuf nicht gefunden")

        is_ec = db.execute(
            "SELECT 1 FROM user_permission "
            "WHERE user_id=? AND event_id=? AND permission_id='help.receive'",
            (user_id, event_id),
        ).fetchone()

        if req["requester_id"] != user_id and not is_ec:
            raise HTTPException(403, "Keine Berechtigung")

        db.execute(
            "UPDATE help_request SET status='resolved' WHERE id=?", (request_id,)
        )

    await _manager.broadcast({"type": "resolved", "request_id": request_id})
