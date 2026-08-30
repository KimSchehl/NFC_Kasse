import logging

from fastapi import APIRouter, Depends, HTTPException, Query

from database import get_db
from dependencies import get_active_event, get_current_user
from schemas import PagerOrderResponse

router = APIRouter(prefix="/api/pager", tags=["pager"])
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# List open (or done) pager orders — scoped to the requesting operator, not
# the whole event. No permission check: the created_by filter below *is* the
# access boundary, same reasoning as help_request's "my own requests" scope.
# ---------------------------------------------------------------------------

@router.get("/", response_model=list[PagerOrderResponse])
def list_pager_orders(
    status: str = Query("open"),
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db() as db:
        rows = db.execute(
            """
            SELECT id, item_summary, pager_number, status, created_at, done_at
            FROM pager_order
            WHERE created_by=? AND event_id=? AND status=?
            ORDER BY created_at ASC
            """,
            (user_id, event_id, status),
        ).fetchall()

    return [PagerOrderResponse(**dict(r)) for r in rows]


# ---------------------------------------------------------------------------
# Mark a pager order done
# ---------------------------------------------------------------------------

@router.post("/{pager_order_id}/done", response_model=PagerOrderResponse)
def mark_pager_order_done(
    pager_order_id: int,
    current_user: dict = Depends(get_current_user),
    active_event: dict = Depends(get_active_event),
):
    user_id = current_user["id"]
    event_id = active_event["id"]

    with get_db(exclusive=True) as db:
        # created_by is part of the WHERE clause, not just a post-hoc check —
        # this is what stops one operator from closing another's entry by
        # guessing an ID (no separate permission node exists for this).
        row = db.execute(
            "SELECT id, status FROM pager_order WHERE id=? AND created_by=? AND event_id=?",
            (pager_order_id, user_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Pager-Eintrag nicht gefunden")
        if row["status"] == "done":
            raise HTTPException(status_code=400, detail="Pager-Eintrag bereits erledigt")

        db.execute(
            "UPDATE pager_order SET status='done', done_at=datetime('now') WHERE id=?",
            (pager_order_id,),
        )
        updated = db.execute(
            "SELECT id, item_summary, pager_number, status, created_at, done_at FROM pager_order WHERE id=?",
            (pager_order_id,),
        ).fetchone()

    logger.info(
        "Pager order done: pager_order_id=%s by=%s",
        pager_order_id, current_user["username"],
    )
    return PagerOrderResponse(**dict(updated))
