"""
Veranstalter (= tenant). Everything of a kasse belongs to one: users, rights,
categories, articles, chips with their balances, Feste and Intern. Two
Veranstalter on one server are completely separate kassen.

Locally exactly one Veranstalter is active (tenant.active), chosen in the
admin tool; only its users can log in. Authenticated requests are scoped by
the user's own tenant_id anyway — the active Veranstalter only matters where
there is no user: login, and the unauthenticated pages (leaderboard,
/health). In the planned cloud version many tenants are active at once and
the login names its tenant instead.

Called by admin_cli.py (admin tool, no login) and the routers.
"""

import bcrypt

from event_lifecycle import EventError


def active_tenant_id(db) -> int:
    row = db.execute("SELECT id FROM tenant WHERE active = 1 ORDER BY id LIMIT 1").fetchone()
    if row:
        return row["id"]
    row = db.execute("SELECT MIN(id) AS id FROM tenant").fetchone()
    if row is None or row["id"] is None:
        raise EventError("Kein Veranstalter angelegt.")
    return row["id"]


def active_event(db, tenant_id: int | None = None):
    """The running event (fest or Intern) of the tenant — by default of
    the active Veranstalter. None if the database has no event yet."""
    if tenant_id is None:
        tenant_id = active_tenant_id(db)
    return db.execute("SELECT * FROM event WHERE tenant_id = ? AND active = 1", (tenant_id,)).fetchone()


def ensure_bar_chips(db, bar_chip_uid: str) -> None:
    """Every Veranstalter has its own virtual BAR chip for cash sales."""
    db.execute(
        """
        INSERT OR IGNORE INTO customer (tenant_id, nfc_uid, balance, is_available)
        SELECT id, ?, 0.0, 0 FROM tenant
        """,
        (bar_chip_uid,),
    )


def _tenant_dict(db, row) -> dict:
    count = lambda sql: db.execute(sql, (row["id"],)).fetchone()[0]
    running = db.execute(
        "SELECT name, is_intern FROM event WHERE tenant_id = ? AND active = 1", (row["id"],)
    ).fetchone()
    return {
        "id": row["id"],
        "name": row["name"],
        "active": bool(row["active"]),
        "users": count("SELECT COUNT(*) FROM user WHERE tenant_id = ? AND deleted = 0"),
        "categories": count("SELECT COUNT(*) FROM category WHERE tenant_id = ? AND deleted = 0"),
        "fests": count("SELECT COUNT(*) FROM event WHERE tenant_id = ? AND is_intern = 0"),
        "running": None if running is None else ("Intern" if running["is_intern"] else running["name"]),
    }


def list_tenants(db) -> list[dict]:
    return [_tenant_dict(db, r) for r in db.execute("SELECT * FROM tenant ORDER BY id").fetchall()]


def create_tenant(db, *, name: str, admin_username: str, admin_password: str, bar_chip_uid: str) -> dict:
    """
    A new, empty Veranstalter: its own Intern event (running — the first
    fest is started in the admin tool), its own BAR chip and one admin
    account with every right except kiosk.access. Not activated: switching
    is its own step (activate_tenant).
    """
    name = name.strip()
    admin_username = admin_username.strip()
    if not name:
        raise EventError("Der Name des Veranstalters darf nicht leer sein.")
    if not admin_username:
        raise EventError("Bitte einen Benutzernamen für den Administrator angeben.")
    if len(admin_password) < 6:
        raise EventError("Das Passwort muss mindestens 6 Zeichen haben.")
    if db.execute("SELECT 1 FROM tenant WHERE name = ?", (name,)).fetchone():
        raise EventError(f"Einen Veranstalter „{name}“ gibt es schon.")

    tenant_id = db.execute("INSERT INTO tenant (name, plan, active) VALUES (?, 'local', 0)", (name,)).lastrowid
    intern_id = db.execute(
        "INSERT INTO event (tenant_id, name, active, is_intern) VALUES (?, 'Intern', 1, 1)", (tenant_id,)
    ).lastrowid
    db.execute("INSERT INTO stats_period (event_id, label) VALUES (?, 'Intern')", (intern_id,))
    password_hash = bcrypt.hashpw(admin_password.encode(), bcrypt.gensalt()).decode()
    admin_id = db.execute(
        "INSERT INTO user (tenant_id, username, password_hash, display_name) VALUES (?, ?, ?, 'Administrator')",
        (tenant_id, admin_username, password_hash),
    ).lastrowid
    db.execute(
        """
        INSERT INTO user_permission (user_id, permission_id, granted_by)
        SELECT ?, id, ? FROM permission_node
        WHERE node_type != 'group' AND (parent_id IS NULL OR parent_id != 'kiosk')
        """,
        (admin_id, admin_id),
    )
    db.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (?, ?, 0.0, 0)",
        (tenant_id, bar_chip_uid),
    )
    return _tenant_dict(db, db.execute("SELECT * FROM tenant WHERE id = ?", (tenant_id,)).fetchone())


def check_can_activate(db, tenant_id: int) -> None:
    if not db.execute("SELECT 1 FROM tenant WHERE id = ?", (tenant_id,)).fetchone():
        raise EventError("Veranstalter nicht gefunden.")
    current = active_tenant_id(db)
    if current == tenant_id:
        raise EventError("Dieser Veranstalter ist schon aktiv.")
    running = active_event(db, current)
    if running is not None and not running["is_intern"]:
        raise EventError("Es läuft noch ein Fest. Bitte zuerst das Fest beenden, dann den Veranstalter wechseln.")


def activate_tenant(db, tenant_id: int) -> dict:
    """Must run inside get_db(exclusive=True). Only while the current
    Veranstalter runs Intern (no fest). Logs every device out: refresh
    tokens are revoked, and get_current_user refuses users of a
    Veranstalter that is no longer active."""
    check_can_activate(db, tenant_id)
    db.execute("UPDATE tenant SET active = 0")
    db.execute("UPDATE tenant SET active = 1 WHERE id = ?", (tenant_id,))
    db.execute("UPDATE refresh_token SET revoked = 1 WHERE revoked = 0")
    return _tenant_dict(db, db.execute("SELECT * FROM tenant WHERE id = ?", (tenant_id,)).fetchone())


def rename_tenant(db, tenant_id: int, name: str) -> dict:
    name = name.strip()
    if not name:
        raise EventError("Der Name des Veranstalters darf nicht leer sein.")
    if not db.execute("SELECT 1 FROM tenant WHERE id = ?", (tenant_id,)).fetchone():
        raise EventError("Veranstalter nicht gefunden.")
    if db.execute("SELECT 1 FROM tenant WHERE name = ? AND id != ?", (name, tenant_id)).fetchone():
        raise EventError(f"Einen Veranstalter „{name}“ gibt es schon.")
    db.execute("UPDATE tenant SET name = ? WHERE id = ?", (name, tenant_id))
    return _tenant_dict(db, db.execute("SELECT * FROM tenant WHERE id = ?", (tenant_id,)).fetchone())
