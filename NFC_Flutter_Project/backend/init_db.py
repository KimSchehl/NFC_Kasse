"""
NFC-Kasse — database setup.

The schema itself lives in the Alembic revisions (alembic/versions/,
baseline 0001 with the commented CREATE TABLEs); this file brings a database
to the newest revision and seeds a fresh one: permission tree, first
Veranstalter, admin user, role templates, BAR chip.

    python init_db.py      # uses DATABASE_URL (config.env / environment)
"""

import database
import schema


def setup() -> bool:
    """Migrates to the newest schema and seeds an empty database.
    Returns True when it seeded (fresh install)."""
    schema.upgrade()
    with database.get_db() as db:
        if db.execute("SELECT 1 FROM tenant LIMIT 1").fetchone():
            return False
        seed_permissions(db)
        seed_default_data(db)
    return True


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
        # No statistics.export: the CSV export for accounting lives in the
        # admin tool (admin_cli.py csv-export), which has no user login.

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

        # --- Bon-Druck (Thermodrucker für Barzahlungen ohne Chip) ---
        ("bon",                     None,               "Bon-Druck",                "group", 6),
        ("bon.drucken",             "bon",              "Bon drucken",              "w",     1),

        # --- Kundenterminal / Kiosk ---
        ("kiosk",                   None,               "Kundenterminal",           "group", 7),
        ("kiosk.access",            "kiosk",            "Kiosk-Modus",              "w",     1),

        # --- Protokolle / Logging ---
        ("logs",                    None,               "Protokolle",               "group", 8),
        ("logs.view",               "logs",             "Protokolle einsehen",      "r",     1),
        ("logs.configure",          "logs",             "Protokoll-Level verwalten","w",     2),

        # No permission for starting/ending a fest either — that's done in
        # the admin tool on the server (admin_cli.py), never from the app.
    ]

    conn.executemany(
        "INSERT INTO permission_node (id, parent_id, label, node_type, sort_order) VALUES (?,?,?,?,?)",
        nodes
    )


def seed_default_data(conn):
    """
    Creates base data: tenant, event, admin user, role templates.
    Admin password is 'admin' — MUST be changed on first login.
    """
    import bcrypt
    from config import BAR_CHIP_UID

    c = conn

    # Tenant (content in German — this is user-facing data)
    tenant_id = c.execute(
        "INSERT INTO tenant (name, plan, active) VALUES (?, ?, 1) RETURNING id", ("Lokal", "local")
    ).fetchone()[0]

    # Event (content in German). The running fest starts out active; the
    # permanent "Intern" event is always there, inactive while a fest runs.
    event_id = c.execute(
        "INSERT INTO event (tenant_id, name, active, chip_deposit) VALUES (?, ?, 1, ?) RETURNING id",
        # Name and Pfand of this first fest are changed live in the admin
        # tool (Konfiguration); every later fest gets them when started.
        (tenant_id, "Hauptveranstaltung", 0.0)
    ).fetchone()[0]
    c.execute(
        "INSERT INTO event (tenant_id, name, active, is_intern) VALUES (?, 'Intern', 0, 1)",
        (tenant_id,)
    )

    # Admin user — password 'admin', MUST be changed immediately
    pw_hash = bcrypt.hashpw(b"admin", bcrypt.gensalt()).decode()
    admin_id = c.execute(
        "INSERT INTO app_user (tenant_id, username, password_hash, display_name) VALUES (?, ?, ?, ?) RETURNING id",
        (tenant_id, "admin", pw_hash, "Administrator")
    ).fetchone()[0]

    # Grant ALL leaf permissions to admin -- except kiosk.access. Granting it
    # is harmless for an account with other rights (only a kiosk-*only*
    # account is routed to the kiosk screen, see UserModel.isKioskOnly), but
    # kiosk belongs on a dedicated terminal account, not on the admin.
    for (perm_id,) in c.execute(
        "SELECT id FROM permission_node WHERE node_type != 'group' AND (parent_id IS NULL OR parent_id != 'kiosk')"
    ).fetchall():
        c.execute(
            "INSERT INTO user_permission (user_id, permission_id, granted_by) VALUES (?, ?, ?)",
            (admin_id, perm_id, admin_id)
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
            "users.view",
            "users.manage_permissions",
        ]),
    ]

    for (name, desc, perms) in templates:
        tmpl_id = c.execute(
            "INSERT INTO role_template (tenant_id, name, description) VALUES (?, ?, ?) RETURNING id",
            (tenant_id, name, desc)
        ).fetchone()[0]
        for p in perms:
            c.execute("INSERT INTO role_template_permission VALUES (?, ?)", (tmpl_id, p))

    # Initial stats period — covers everything from DB creation onwards.
    c.execute(
        "INSERT INTO stats_period (event_id, label, created_by) VALUES (?, ?, ?)",
        (event_id, "Start", admin_id)
    )

    # Virtual BAR chip for cash sales without NFC — always is_available=0 (never a real guest).
    # Balance goes negative as bar sales accumulate. Hidden from the Chips tab.
    c.execute(
        "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (?, ?, 0.0, 0) ON CONFLICT DO NOTHING",
        (tenant_id, BAR_CHIP_UID),
    )



if __name__ == "__main__":
    if setup():
        print("Database created. WARNING: admin password is 'admin' — change it immediately!")
    else:
        print("Database schema is up to date.")
