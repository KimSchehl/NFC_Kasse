"""
NFC-Kasse — Database Initialization
=====================================
Phase 1: Local / SQLite / Single-Event

Forward compatibility without overengineering:
- tenant_id columns present everywhere (NULL = local install, ready for cloud)
- event_id linked throughout (multi-event ready)
- permission_node as data table, not hardcoded enum in code
- user_category_access for fine-grained category visibility per user
- Repository pattern recommended for DB access (easy PostgreSQL migration later)
"""

import sqlite3
import os

DB_PATH = os.environ.get("DB_PATH", "kasse.db")


def init_db():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")   # Allows concurrent reads during event operation
    conn.execute("PRAGMA foreign_keys=ON")
    c = conn.cursor()

    # ------------------------------------------------------------------
    # TENANT
    # Local: exactly one tenant with id=1, plan='local'
    # Cloud future: multiple tenants without schema change
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE tenant (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        plan        TEXT    NOT NULL DEFAULT 'local',  -- 'local' | 'cloud'
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
    )""")

    # ------------------------------------------------------------------
    # EVENT
    # Local: exactly one event, active=1
    # Future: multiple events per tenant simultaneously
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE event (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id   INTEGER NOT NULL REFERENCES tenant(id),
        name        TEXT    NOT NULL,
        active      INTEGER NOT NULL DEFAULT 1,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
    )""")

    # ------------------------------------------------------------------
    # USER
    # password_hash: bcrypt via passlib (NEVER plaintext)
    # tenant_id: prepared for cloud (locally always =1)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE user (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id       INTEGER NOT NULL REFERENCES tenant(id),
        username        TEXT    NOT NULL,
        password_hash   TEXT    NOT NULL,
        display_name    TEXT,
        active          INTEGER NOT NULL DEFAULT 1,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(tenant_id, username)
    )""")

    # ------------------------------------------------------------------
    # PERMISSION NODE — extensible permission tree
    # New permissions = new DB rows, no code update needed
    # parent_id NULL = root node (category)
    # node_type: 'group' (branch) | 'r' (read-only) | 'w' (write) | 'rw'
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE permission_node (
        id          TEXT    PRIMARY KEY,   -- e.g. 'sales.booking.create'
        parent_id   TEXT    REFERENCES permission_node(id),
        label       TEXT    NOT NULL,      -- display label (German for UI)
        node_type   TEXT    NOT NULL DEFAULT 'w',  -- 'group'|'r'|'w'|'rw'
        sort_order  INTEGER NOT NULL DEFAULT 0
    )""")

    # ------------------------------------------------------------------
    # ROLE TEMPLATE — reusable role presets (e.g. "Standverkäufer")
    # Speeds up creating new users, does not replace individual permissions
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE role_template (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id   INTEGER NOT NULL REFERENCES tenant(id),
        name        TEXT    NOT NULL,
        description TEXT,
        UNIQUE(tenant_id, name)
    )""")

    c.execute("""
    CREATE TABLE role_template_permission (
        role_template_id    INTEGER NOT NULL REFERENCES role_template(id),
        permission_id       TEXT    NOT NULL REFERENCES permission_node(id),
        PRIMARY KEY (role_template_id, permission_id)
    )""")

    # ------------------------------------------------------------------
    # USER PERMISSION — individual permissions per user per event
    # Each row = one checked leaf node in the permission tree
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE user_permission (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id         INTEGER NOT NULL REFERENCES user(id),
        event_id        INTEGER NOT NULL REFERENCES event(id),
        permission_id   TEXT    NOT NULL REFERENCES permission_node(id),
        granted_by      INTEGER REFERENCES user(id),
        granted_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(user_id, event_id, permission_id)
    )""")

    # ------------------------------------------------------------------
    # CATEGORY & PRODUCT
    # deleted flag (soft-delete): historical sales remain valid
    # sort_order: display order adjustable per event
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE category (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id    INTEGER NOT NULL REFERENCES event(id),
        name        TEXT    NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        deleted     INTEGER NOT NULL DEFAULT 0
    )""")

    c.execute("""
    CREATE TABLE product (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL REFERENCES category(id),
        name        TEXT    NOT NULL,
        price       REAL    NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        active      INTEGER NOT NULL DEFAULT 1,  -- temporarily disable without deleting
        deleted     INTEGER NOT NULL DEFAULT 0,  -- soft-delete, keeps historical sales valid
        is_payout           INTEGER NOT NULL DEFAULT 0,  -- marks article as full-balance payout
        exclude_from_stats  INTEGER NOT NULL DEFAULT 0,  -- exclude from revenue statistics
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
    )""")

    # ------------------------------------------------------------------
    # USER CATEGORY ACCESS — per-category booking and article permissions
    #
    # Why a separate table instead of permission_node entries?
    # Categories are dynamic (differ per event, can be renamed).
    # permission_node is for static, code-level permissions.
    #
    # How it works:
    #   user_category_access          = which categories + what the user can do
    #   Users with 'categories.*' see all categories (manager path)
    #
    # can_book:              may book products from this category
    # can_storno_5min:       may cancel a booking within 5 minutes
    # can_storno_unlimited:  may cancel any booking regardless of age
    # can_create_article:    may create new articles in this category
    # can_edit_article:      may edit name/price of existing articles
    # can_deactivate_article: may toggle active/inactive (out-of-stock)
    # can_delete_article:    may permanently delete articles
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE user_category_access (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id                 INTEGER NOT NULL REFERENCES user(id),
        event_id                INTEGER NOT NULL REFERENCES event(id),
        category_id             INTEGER NOT NULL REFERENCES category(id),
        can_book                INTEGER NOT NULL DEFAULT 0,
        can_storno_5min         INTEGER NOT NULL DEFAULT 0,
        can_storno_unlimited    INTEGER NOT NULL DEFAULT 0,
        can_create_article      INTEGER NOT NULL DEFAULT 0,
        can_edit_article        INTEGER NOT NULL DEFAULT 0,
        can_deactivate_article  INTEGER NOT NULL DEFAULT 0,
        can_delete_article      INTEGER NOT NULL DEFAULT 0,
        granted_by              INTEGER REFERENCES user(id),
        granted_at              TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(user_id, event_id, category_id)
    )""")

    # ------------------------------------------------------------------
    # CUSTOMER — guests with NFC chip
    # tenant_id: one wristband works across all events of the same tenant
    # Balance is ALWAYS server-side — chip stores only the UID
    # is_available: set to 0 after a payout to mark the chip as returned/reset
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE customer (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id    INTEGER NOT NULL REFERENCES tenant(id),
        nfc_uid      TEXT    NOT NULL,
        display_name TEXT,                -- future: writable to tag
        balance      REAL    NOT NULL DEFAULT 0.0,
        is_available INTEGER NOT NULL DEFAULT 1,
        created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(tenant_id, nfc_uid)
    )""")

    # ------------------------------------------------------------------
    # SALE — every booking is immutable (append-only)
    # price_at_sale: REQUIRED — snapshot, price changes must not alter history
    # cancelled: cancel sets cancelled=1 and refunds balance
    #            original row is preserved (audit trail)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE sale (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id        INTEGER NOT NULL REFERENCES event(id),
        customer_id     INTEGER NOT NULL REFERENCES customer(id),
        product_id      INTEGER NOT NULL REFERENCES product(id),
        price_at_sale   REAL    NOT NULL,   -- price snapshot at booking time
        booked_by       INTEGER NOT NULL REFERENCES user(id),
        booked_at       TEXT    NOT NULL DEFAULT (datetime('now')),  -- used for 5-min cancel check
        cancelled       INTEGER NOT NULL DEFAULT 0,
        cancelled_by    INTEGER REFERENCES user(id),
        cancelled_at    TEXT
    )""")

    # ------------------------------------------------------------------
    # TOPUP — balance top-ups tracked separately from purchases
    # payment_method: 'cash' | 'google_pay' | 'paypal' (future)
    # Payouts use a negative amount topup row (full audit trail)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE topup (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id        INTEGER NOT NULL REFERENCES event(id),
        customer_id     INTEGER NOT NULL REFERENCES customer(id),
        amount          REAL    NOT NULL,
        payment_method  TEXT    NOT NULL DEFAULT 'cash',
        booked_by       INTEGER NOT NULL REFERENCES user(id),
        booked_at       TEXT    NOT NULL DEFAULT (datetime('now')),
        cancelled       INTEGER NOT NULL DEFAULT 0,
        cancelled_by    INTEGER REFERENCES user(id),
        cancelled_at    TEXT
    )""")

    # ------------------------------------------------------------------
    # REFRESH TOKEN — JWT session management
    # token_hash: SHA-256 of token (never store plaintext)
    # revoked=1 on logout — enables server-side session invalidation
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE refresh_token (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL REFERENCES user(id),
        token_hash  TEXT    NOT NULL UNIQUE,
        device_info TEXT,                      -- e.g. "Flutter Android"
        created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        expires_at  TEXT    NOT NULL,
        revoked     INTEGER NOT NULL DEFAULT 0
    )""")

    # ------------------------------------------------------------------
    # USER SETTING — per-user, per-event UI preferences (key/value)
    # New settings without schema change
    # event_id NULL = global setting (applies to all events)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE user_setting (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL REFERENCES user(id),
        event_id    INTEGER REFERENCES event(id),  -- NULL = global
        key         TEXT    NOT NULL,   -- e.g. 'grid_columns', 'theme'
        value       TEXT    NOT NULL,
        UNIQUE(user_id, event_id, key)
    )""")

    # ------------------------------------------------------------------
    # USER PREFERENCE STORE — generic per-user key/value store
    # key:     dotted identifier, e.g. 'layout.cat_3', 'product.color.42'
    # profile: 'P' (portrait/narrow), 'L' (landscape/wide), '*' (any)
    # value:   JSON-serialised value (list, string, number, …)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE user_preference_store (
        user_id  INTEGER NOT NULL REFERENCES user(id),
        key      TEXT    NOT NULL,
        profile  TEXT    NOT NULL DEFAULT '*',
        value    TEXT    NOT NULL,
        PRIMARY KEY (user_id, key, profile)
    )""")

    # ------------------------------------------------------------------
    # STATS PERIOD — named time windows for the revenue statistics
    # Each Tagesabschluss closes the current period and opens a new one.
    # closed_at NULL = the period is still open / current.
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE stats_period (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id    INTEGER NOT NULL REFERENCES event(id),
        label       TEXT    NOT NULL,
        started_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        closed_at   TEXT,
        created_by  INTEGER REFERENCES user(id)
    )""")

    # ------------------------------------------------------------------
    # HELP REQUEST / NOTFALL SYSTEM
    # help_request: one row per active help call (status active|resolved)
    # help_response: emergency contacts react per request (one row per responder)
    # ------------------------------------------------------------------
    c.execute("""
    CREATE TABLE help_request (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id     INTEGER NOT NULL REFERENCES event(id),
        requester_id INTEGER NOT NULL REFERENCES user(id),
        status       TEXT    NOT NULL DEFAULT 'active',
        created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
    )""")

    c.execute("""
    CREATE TABLE help_response (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id   INTEGER NOT NULL REFERENCES help_request(id),
        responder_id INTEGER NOT NULL REFERENCES user(id),
        response     TEXT    NOT NULL,  -- 'on_way' | '5min' | 'cannot'
        created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(request_id, responder_id)
    )""")

    # ------------------------------------------------------------------
    # INDEXES — for frequent query patterns
    # ------------------------------------------------------------------
    c.execute("CREATE INDEX idx_sale_customer         ON sale(customer_id)")
    c.execute("CREATE INDEX idx_sale_event            ON sale(event_id)")
    c.execute("CREATE INDEX idx_sale_booked_at        ON sale(booked_at)")
    c.execute("CREATE INDEX idx_topup_customer        ON topup(customer_id)")
    c.execute("CREATE INDEX idx_customer_nfc          ON customer(nfc_uid)")
    c.execute("CREATE INDEX idx_user_permission       ON user_permission(user_id, event_id)")
    c.execute("CREATE INDEX idx_user_category_access  ON user_category_access(user_id, event_id)")
    c.execute("CREATE INDEX idx_product_category      ON product(category_id)")
    c.execute("CREATE INDEX idx_refresh_token         ON refresh_token(token_hash)")

    conn.commit()
    return conn


def seed_permissions(conn):
    """
    Populates the permission tree with all base nodes.
    Extend by adding new rows — no code update required.
    IDs use English dot-notation. Labels are German (displayed in UI).

    Design notes:
    - Booking / storno / article permissions are per-category (user_category_access),
      NOT here. This tree contains only global / structural permissions.
    - Balance view is always allowed for logged-in users — no permission node.
    - Einstellungen is always visible — no permission node.
    """
    c = conn.cursor()

    nodes = [
        # (id, parent_id, label, node_type, sort_order)

        # --- Guthaben (global balance operations) ---
        ("guthaben",            None,           "Guthaben",                 "group", 1),
        ("guthaben.topup",      "guthaben",     "Aufladen",                 "w",     1),
        ("guthaben.payout",     "guthaben",     "Auszahlen",                "w",     2),

        # --- Categories (structural management) ---
        # Booking/storno/article permissions live in user_category_access (per-category).
        # These nodes control who can create/rename/deactivate/delete categories.
        # A user with any of these permissions is treated as a "manager" and can see
        # all categories with full access.
        ("categories",              None,           "Kategorien",               "group", 2),
        ("categories.create",       "categories",   "Kategorie erstellen",      "w",     1),
        ("categories.edit",         "categories",   "Kategorie bearbeiten",     "w",     2),
        ("categories.deactivate",   "categories",   "Kategorie deaktivieren",   "w",     3),
        ("categories.delete",       "categories",   "Kategorie löschen",        "w",     4),

        # --- Statistics ---
        ("statistics",              None,               "Statistik & Finanzen",     "group", 3),
        ("statistics.revenue",      "statistics",       "Umsatz einsehen",          "r",     1),
        ("statistics.transactions", "statistics",       "Transaktionen einsehen",   "r",     2),
        ("statistics.export",       "statistics",       "Daten exportieren",        "r",     3),

        # --- User Management ---
        ("users",                   None,               "Benutzerverwaltung",       "group", 4),
        ("users.view",              "users",            "Benutzer anzeigen",        "r",     1),
        ("users.create",            "users",            "Benutzer erstellen",       "w",     2),
        ("users.edit",              "users",            "Benutzer bearbeiten",      "w",     3),
        ("users.deactivate",        "users",            "Benutzer deaktivieren",    "w",     4),
        ("users.delete",            "users",            "Benutzer löschen",         "w",     5),
        ("users.manage_permissions","users",            "Rechte vergeben",          "w",     6),

        # --- Notfall / Help ---
        ("help",                    None,               "Notfall",                  "group", 5),
        ("help.receive",            "help",             "Notfall-Kontakt",          "w",     1),
    ]

    c.executemany(
        "INSERT INTO permission_node (id, parent_id, label, node_type, sort_order) VALUES (?,?,?,?,?)",
        nodes
    )
    conn.commit()


def seed_default_data(conn):
    """
    Creates base data: tenant, event, admin user, role templates.
    Admin password is 'admin' — MUST be changed on first login.
    """
    import bcrypt

    c = conn.cursor()

    # Tenant (content in German — this is user-facing data)
    c.execute("INSERT INTO tenant (name, plan) VALUES (?, ?)", ("Lokal", "local"))
    tenant_id = c.lastrowid

    # Event (content in German)
    c.execute(
        "INSERT INTO event (tenant_id, name, active) VALUES (?, ?, 1)",
        (tenant_id, "Hauptveranstaltung")
    )
    event_id = c.lastrowid

    # Admin user — password 'admin', MUST be changed immediately
    pw_hash = bcrypt.hashpw(b"admin", bcrypt.gensalt()).decode()
    c.execute(
        "INSERT INTO user (tenant_id, username, password_hash, display_name) VALUES (?, ?, ?, ?)",
        (tenant_id, "admin", pw_hash, "Administrator")
    )
    admin_id = c.lastrowid

    # Grant ALL leaf permissions to admin on this event
    c.execute("SELECT id FROM permission_node WHERE node_type != 'group'")
    for (perm_id,) in c.fetchall():
        c.execute(
            "INSERT INTO user_permission (user_id, event_id, permission_id, granted_by) VALUES (?, ?, ?, ?)",
            (admin_id, event_id, perm_id, admin_id)
        )

    # Role templates (names are German — user-facing content)
    # Note: per-category booking/article permissions are set separately via
    # user_category_access and are not part of these global role templates.
    templates = [
        ("Standverkäufer", "Basis-Rechte für einen Stand (Buchen per Kategorie vergeben)", [
            "guthaben.topup",
        ]),
        ("Veranstaltungs-Verantwortlicher", "Erweiterte Rechte für Event-Management", [
            "guthaben.topup",
            "guthaben.payout",
            "categories.create",
            "categories.edit",
            "categories.deactivate",
            "categories.delete",
            "statistics.revenue",
            "statistics.transactions",
            "statistics.export",
            "users.view",
            "users.manage_permissions",
        ]),
    ]

    for (name, desc, perms) in templates:
        c.execute(
            "INSERT INTO role_template (tenant_id, name, description) VALUES (?, ?, ?)",
            (tenant_id, name, desc)
        )
        tmpl_id = c.lastrowid
        for p in perms:
            c.execute("INSERT INTO role_template_permission VALUES (?, ?)", (tmpl_id, p))

    # Initial stats period — covers everything from DB creation onwards.
    c.execute(
        "INSERT INTO stats_period (event_id, label, created_by) VALUES (?, ?, ?)",
        (event_id, "Start", admin_id)
    )

    conn.commit()
    print(f"Tenant ID:  {tenant_id}")
    print(f"Event ID:   {event_id}")
    print(f"Admin ID:   {admin_id}")
    print("WARNING: Admin password is 'admin' — change it immediately!")


if __name__ == "__main__":
    conn = init_db()
    seed_permissions(conn)
    seed_default_data(conn)
    conn.close()
    print(f"Database '{DB_PATH}' created successfully.")
