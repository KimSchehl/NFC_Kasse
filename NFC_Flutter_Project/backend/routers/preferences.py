import json

from fastapi import APIRouter, Depends, Query

from database import get_db
from dependencies import get_current_user
from schemas import PreferenceItem, PreferenceUpsert

router = APIRouter(prefix="/api/preferences", tags=["preferences"])


@router.get("/", response_model=list[PreferenceItem])
def get_preferences(current_user: dict = Depends(get_current_user)):
    """Returns all saved preferences for the authenticated user."""
    user_id = current_user["id"]
    with get_db() as db:
        rows = db.execute(
            "SELECT key, profile, value FROM user_preference_store WHERE user_id = ?",
            (user_id,),
        ).fetchall()
    return [
        PreferenceItem(key=r["key"], profile=r["profile"], value=json.loads(r["value"]))
        for r in rows
    ]


@router.put("/{key}", response_model=PreferenceItem)
def upsert_preference(
    key: str,
    body: PreferenceUpsert,
    current_user: dict = Depends(get_current_user),
):
    """Creates or replaces a single preference entry."""
    user_id = current_user["id"]
    with get_db() as db:
        db.execute(
            """
            INSERT INTO user_preference_store (user_id, key, profile, value)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id, key, profile) DO UPDATE SET value = excluded.value
            """,
            (user_id, key, body.profile, json.dumps(body.value)),
        )
    return PreferenceItem(key=key, profile=body.profile, value=body.value)


@router.delete("/{key}", status_code=204)
def delete_preference(
    key: str,
    profile: str | None = Query(default=None),
    current_user: dict = Depends(get_current_user),
):
    """Deletes a preference. If profile is omitted, all profiles for that key are deleted."""
    user_id = current_user["id"]
    with get_db() as db:
        if profile is None:
            db.execute(
                "DELETE FROM user_preference_store WHERE user_id=? AND key=?",
                (user_id, key),
            )
        else:
            db.execute(
                "DELETE FROM user_preference_store WHERE user_id=? AND key=? AND profile=?",
                (user_id, key, profile),
            )
