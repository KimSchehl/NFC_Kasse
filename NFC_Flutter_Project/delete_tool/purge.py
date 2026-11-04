"""
Deletes a whole Veranstalter (tenant) or a single ended Fest from kasse.db.

Used by delete_tool.py (interactive, run on the server with the service
stopped). Every function expects a connection with row_factory=sqlite3.Row
and foreign_keys=ON; delete_* must run inside one exclusive transaction —
they end with a foreign key check, so a reference this module forgot
raises PurgeError instead of leaving orphans behind.

Rules (same as the admin tool): the running event and Intern are never
deleted; the active Veranstalter and the last remaining one neither.
Chip balances belong to the Veranstalter, so deleting a Fest only removes
what happened during it (sales, top-ups, periods, pagers, bons, opt-ins) —
balances stay as they are.
"""

import sqlite3


class PurgeError(Exception):
    pass


def _count(db, sql: str, *args) -> int:
    return db.execute(sql, args).fetchone()[0] or 0


def list_tenants(db) -> list[dict]:
    return [tenant_summary(db, r["id"]) for r in db.execute("SELECT id FROM tenant ORDER BY id")]


def tenant_summary(db, tenant_id: int) -> dict:
    t = db.execute("SELECT * FROM tenant WHERE id = ?", (tenant_id,)).fetchone()
    if t is None:
        raise PurgeError("Veranstalter nicht gefunden.")
    events = "SELECT id FROM event WHERE tenant_id = ?"
    return {
        "id": t["id"],
        "name": t["name"],
        "active": bool(t["active"]),
        "fests": _count(db, "SELECT COUNT(*) FROM event WHERE tenant_id = ? AND is_intern = 0", tenant_id),
        "users": _count(db, "SELECT COUNT(*) FROM user WHERE tenant_id = ? AND deleted = 0", tenant_id),
        "categories": _count(db, "SELECT COUNT(*) FROM category WHERE tenant_id = ? AND deleted = 0", tenant_id),
        "products": _count(
            db,
            "SELECT COUNT(*) FROM product WHERE deleted = 0 AND category_id IN "
            "(SELECT id FROM category WHERE tenant_id = ? AND deleted = 0)",
            tenant_id,
        ),
        "chips": _count(db, "SELECT COUNT(*) FROM customer WHERE tenant_id = ? AND is_available = 0", tenant_id),
        "sales": _count(db, f"SELECT COUNT(*) FROM sale WHERE event_id IN ({events})", tenant_id),
        "open_balance": _count(db, "SELECT SUM(balance) FROM customer WHERE tenant_id = ? AND balance > 0", tenant_id),
        "open_balance_chips": _count(
            db, "SELECT COUNT(*) FROM customer WHERE tenant_id = ? AND balance > 0", tenant_id
        ),
        "open_deposit": _count(
            db, "SELECT SUM(deposit_paid) FROM customer WHERE tenant_id = ? AND is_available = 0", tenant_id
        ),
    }


def list_fests(db, tenant_id: int) -> list[dict]:
    rows = db.execute(
        "SELECT id FROM event WHERE tenant_id = ? AND is_intern = 0 ORDER BY COALESCE(started_at, created_at)",
        (tenant_id,),
    ).fetchall()
    return [fest_summary(db, r["id"]) for r in rows]


def fest_summary(db, event_id: int) -> dict:
    e = db.execute("SELECT * FROM event WHERE id = ?", (event_id,)).fetchone()
    if e is None:
        raise PurgeError("Fest nicht gefunden.")
    return {
        "id": e["id"],
        "tenant_id": e["tenant_id"],
        "name": e["name"],
        "active": bool(e["active"]),
        "is_intern": bool(e["is_intern"]),
        "date": e["date"],
        "started_at": e["started_at"],
        "ended_at": e["ended_at"],
        "sales": _count(db, "SELECT COUNT(*) FROM sale WHERE event_id = ?", event_id),
        "topups": _count(db, "SELECT COUNT(*) FROM topup WHERE event_id = ?", event_id),
        "periods": _count(db, "SELECT COUNT(*) FROM stats_period WHERE event_id = ?", event_id),
        "pagers": _count(db, "SELECT COUNT(*) FROM pager_order WHERE event_id = ?", event_id),
        "print_jobs": _count(db, "SELECT COUNT(*) FROM print_job WHERE event_id = ?", event_id),
    }


def check_can_delete_fest(db, event_id: int) -> None:
    e = fest_summary(db, event_id)
    if e["is_intern"]:
        raise PurgeError("„Intern“ kann nicht gelöscht werden.")
    if e["active"]:
        raise PurgeError(f"Das Fest „{e['name']}“ läuft gerade. Erst im Admin-Tool beenden.")


def check_can_delete_tenant(db, tenant_id: int) -> None:
    t = tenant_summary(db, tenant_id)
    if t["active"]:
        raise PurgeError(
            f"„{t['name']}“ ist der aktive Veranstalter. Erst im Admin-Tool auf einen anderen umschalten."
        )
    if _count(db, "SELECT COUNT(*) FROM tenant") <= 1:
        raise PurgeError("Der letzte Veranstalter kann nicht gelöscht werden.")


def _delete_event_rows(db, event_id: int) -> None:
    db.execute("DELETE FROM print_job WHERE event_id = ? OR sale_id IN (SELECT id FROM sale WHERE event_id = ?)",
               (event_id, event_id))
    db.execute(
        "DELETE FROM help_response WHERE request_id IN (SELECT id FROM help_request WHERE event_id = ?)", (event_id,)
    )
    for table in (
        "help_request", "pager_order", "leaderboard_entry", "stats_period", "topup", "sale",
        "event_category", "event_product", "user_setting",
    ):
        db.execute(f"DELETE FROM {table} WHERE event_id = ?", (event_id,))
    db.execute("DELETE FROM event WHERE id = ?", (event_id,))


def _check_references(db) -> None:
    broken = db.execute("PRAGMA foreign_key_check").fetchall()
    if broken:
        tables = sorted({row[0] for row in broken})
        raise PurgeError("Es blieben Verweise auf gelöschte Daten übrig (" + ", ".join(tables) + "). Nichts gelöscht.")


def delete_fest(db, event_id: int) -> None:
    check_can_delete_fest(db, event_id)
    _delete_event_rows(db, event_id)
    _check_references(db)


def delete_tenant(db, tenant_id: int) -> None:
    check_can_delete_tenant(db, tenant_id)
    for (event_id,) in db.execute("SELECT id FROM event WHERE tenant_id = ?", (tenant_id,)).fetchall():
        _delete_event_rows(db, event_id)

    users = "SELECT id FROM user WHERE tenant_id = ?"
    categories = "SELECT id FROM category WHERE tenant_id = ?"
    customers = "SELECT id FROM customer WHERE tenant_id = ?"

    # Optional "who did it" columns elsewhere just lose the name.
    for table, column in (
        ("user_permission", "granted_by"), ("user_category_access", "granted_by"),
        ("stats_period", "created_by"), ("sale", "cancelled_by"), ("topup", "cancelled_by"),
        ("device_log_level", "updated_by"),
    ):
        db.execute(f"UPDATE {table} SET {column} = NULL WHERE {column} IN ({users})", (tenant_id,))

    db.execute(f"DELETE FROM leaderboard_score WHERE customer_id IN ({customers})", (tenant_id,))
    db.execute(f"DELETE FROM leaderboard_entry WHERE customer_id IN ({customers})", (tenant_id,))
    db.execute("DELETE FROM customer WHERE tenant_id = ?", (tenant_id,))
    db.execute(
        f"DELETE FROM user_category_access WHERE user_id IN ({users}) OR category_id IN ({categories})",
        (tenant_id, tenant_id),
    )
    db.execute(f"DELETE FROM help_response WHERE responder_id IN ({users})", (tenant_id,))
    for table in ("user_permission", "refresh_token", "user_setting", "user_preference_store"):
        db.execute(f"DELETE FROM {table} WHERE user_id IN ({users})", (tenant_id,))
    db.execute(
        "DELETE FROM role_template_permission WHERE role_template_id IN "
        "(SELECT id FROM role_template WHERE tenant_id = ?)",
        (tenant_id,),
    )
    db.execute("DELETE FROM role_template WHERE tenant_id = ?", (tenant_id,))
    db.execute(f"UPDATE product SET group_id = NULL WHERE category_id IN ({categories})", (tenant_id,))
    db.execute(f"DELETE FROM product WHERE category_id IN ({categories})", (tenant_id,))
    db.execute("DELETE FROM category WHERE tenant_id = ?", (tenant_id,))
    db.execute("DELETE FROM user WHERE tenant_id = ?", (tenant_id,))
    db.execute("DELETE FROM tenant WHERE id = ?", (tenant_id,))
    _check_references(db)


def connect(path) -> sqlite3.Connection:
    """Autocommit connection; the caller opens BEGIN EXCLUSIVE itself."""
    db = sqlite3.connect(path, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    return db
