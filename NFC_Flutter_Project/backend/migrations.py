"""
Schema-Migrationen für bestehende Datenbanken.

run_migrations() läuft bei jedem Start. Fehlende Spalten und Tabellen werden
ergänzt, und die Datenübernahme läuft genau einmal: sie wird über
PRAGMA user_version gesteuert, das beim Anlegen der Datenbank direkt auf die
aktuelle Version gesetzt wird.

migrate_v3() läuft danach, mit eigener Verbindung: v3 baut Tabellen um
(Rechte, Kategorien und Artikel gehören dem Veranstalter statt dem Fest),
und das geht in SQLite nur mit ausgeschalteten Fremdschlüsseln — die sich
innerhalb einer laufenden Transaktion nicht umschalten lassen.
"""

import json
import sqlite3
from pathlib import Path

import db_backup

# Rechte für Aufgaben, die ins Admin-Tool umgezogen sind (CSV-Export, Fest
# starten/beenden). Das Admin-Tool hat keinen Login, also bedeuten sie
# nichts mehr — und würden sonst als wirkungslose Häkchen in der
# Rechtevergabe der App stehen bleiben.
_RETIRED_PERMISSIONS = ("statistics.export", "event.manage", "event")


def _add_column(db: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    existing = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
    if column not in existing:
        db.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def _backfill_v2(db: sqlite3.Connection, bar_chip_uid: str) -> None:
    db.execute("""
        UPDATE sale SET points = COALESCE(
            (SELECT b.points FROM product p JOIN product b ON b.id = p.group_id WHERE p.id = sale.product_id),
            (SELECT p.points FROM product p WHERE p.id = sale.product_id),
            0)
    """)
    db.execute(
        """
        UPDATE customer SET deposit_paid = (SELECT chip_deposit FROM event WHERE active = 1)
        WHERE is_available = 0 AND nfc_uid != ?
        """,
        (bar_chip_uid,),
    )
    db.execute("""
        INSERT OR IGNORE INTO leaderboard_entry (event_id, customer_id, opt_in)
        SELECT (SELECT id FROM event WHERE active = 1), customer_id, opt_in
        FROM leaderboard_score WHERE opt_in = 1
    """)


def run_migrations(
    db: sqlite3.Connection,
    *,
    bar_chip_uid: str,
) -> None:
    _add_column(db, "event", "date", "TEXT")
    _add_column(db, "event", "chip_deposit", "REAL NOT NULL DEFAULT 0")
    _add_column(db, "event", "is_intern", "INTEGER NOT NULL DEFAULT 0")
    _add_column(db, "event", "started_at", "TEXT")
    _add_column(db, "event", "ended_at", "TEXT")
    _add_column(db, "customer", "deposit_paid", "REAL NOT NULL DEFAULT 0")
    _add_column(db, "sale", "points", "INTEGER NOT NULL DEFAULT 0")
    _add_column(db, "tenant", "catalog_rev", "INTEGER NOT NULL DEFAULT 0")

    db.execute("""
        CREATE TABLE IF NOT EXISTS leaderboard_entry (
            event_id    INTEGER NOT NULL REFERENCES event(id),
            customer_id INTEGER NOT NULL REFERENCES customer(id),
            opt_in      INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (event_id, customer_id)
        )
    """)
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS one_active_event_per_tenant "
        "ON event(tenant_id) WHERE active = 1"
    )
    db.execute("""
        INSERT INTO event (tenant_id, name, active, is_intern)
        SELECT t.id, 'Intern', 0, 1 FROM tenant t
        WHERE NOT EXISTS (SELECT 1 FROM event e WHERE e.tenant_id = t.id AND e.is_intern = 1)
    """)

    # Bei jedem Start, kostet nichts: nach dem ersten Mal gibt es nichts mehr zu löschen.
    ph = ",".join("?" * len(_RETIRED_PERMISSIONS))
    db.execute(f"DELETE FROM user_permission WHERE permission_id IN ({ph})", _RETIRED_PERMISSIONS)
    db.execute(f"DELETE FROM role_template_permission WHERE permission_id IN ({ph})", _RETIRED_PERMISSIONS)
    db.execute(f"DELETE FROM permission_node WHERE id IN ({ph})", _RETIRED_PERMISSIONS)

    if db.execute("PRAGMA user_version").fetchone()[0] < 2:
        _backfill_v2(db, bar_chip_uid)
        db.execute("PRAGMA user_version = 2")


# ---------------------------------------------------------------------------
# v3: Rechte, Kategorien und Artikel gehören dem Veranstalter (tenant)
# ---------------------------------------------------------------------------

def migrate_v3(db_path: str | Path) -> None:
    """
    Hebt eine v2-Datenbank auf v3. Läuft nach run_migrations() (das v2
    sicherstellt) und tut nichts, wenn die Datenbank schon v3 ist.

    Legt vorher eine Sicherung „vor-update“ an. Alles läuft in einer
    Transaktion: Schlägt etwas fehl, bleibt die Datenbank unverändert v2 und
    der Dienst startet nicht — besser als halb umgebaute Daten.
    """
    db_path = Path(db_path)
    conn = sqlite3.connect(db_path, timeout=10, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        if conn.execute("PRAGMA user_version").fetchone()[0] >= 3:
            return
        db_backup.create_backup(db_path, db_path.parent / "backups", prefix="vor-update", label="v3")
        conn.execute("PRAGMA foreign_keys=OFF")
        conn.execute("BEGIN IMMEDIATE")
        try:
            # (table, parent) pairs, not row ids: rebuilt tables renumber their rows.
            before = {(r[0], r[2]) for r in conn.execute("PRAGMA foreign_key_check")}
            _upgrade_to_v3(conn)
            new_problems = {(r[0], r[2]) for r in conn.execute("PRAGMA foreign_key_check")} - before
            if new_problems:
                raise RuntimeError(f"v3-Migration: Fremdschlüssel verletzt: {sorted(new_problems)[:5]}")
            conn.execute("PRAGMA user_version = 3")
            conn.execute("COMMIT")
        except BaseException:
            conn.execute("ROLLBACK")
            raise
    finally:
        conn.close()


def _merge_groups(items: list[dict], key, preferred) -> dict[int, int]:
    """
    Maps every item id to the id it is merged into (itself if kept).

    Items with the same key are the same thing from different events
    (copied at each fest start). One canonical item per key survives:
    `preferred(item)` first (the running event's), else the highest id.
    Only one item per event is merged in — two same-named items of one and
    the same event were deliberately separate and stay separate.
    """
    groups: dict = {}
    for it in items:
        groups.setdefault(key(it), []).append(it)
    mapping: dict[int, int] = {}
    for members in groups.values():
        canon = max(members, key=lambda it: (preferred(it), it["id"]))
        merged_events = {canon["event_id"]}
        mapping[canon["id"]] = canon["id"]
        for it in sorted(members, key=lambda it: (it["sort_order"], it["id"])):
            if it["id"] == canon["id"]:
                continue
            if it["event_id"] in merged_events:
                mapping[it["id"]] = it["id"]
            else:
                mapping[it["id"]] = canon["id"]
                merged_events.add(it["event_id"])
    return mapping


def _upgrade_to_v3(db: sqlite3.Connection) -> None:
    _add_column(db, "tenant", "active", "INTEGER NOT NULL DEFAULT 0")
    db.execute("UPDATE tenant SET active = 1 WHERE id = (SELECT MIN(id) FROM tenant)")

    active_event = {
        r["tenant_id"]: r["id"] for r in db.execute("SELECT id, tenant_id FROM event WHERE active = 1")
    }
    intern_event = {
        r["tenant_id"]: r["id"] for r in db.execute("SELECT id, tenant_id FROM event WHERE is_intern = 1")
    }
    running = set(active_event.values())

    # --- Kategorien zusammenführen -------------------------------------
    categories = [dict(r) for r in db.execute(
        """
        SELECT c.id, c.event_id, c.name, c.sort_order, c.deleted,
               COALESCE(e.tenant_id, (SELECT MIN(id) FROM tenant)) AS tenant_id
        FROM category c LEFT JOIN event e ON e.id = c.event_id
        """
    )]
    live_cats = [c for c in categories if not c["deleted"]]
    cat_map = _merge_groups(
        live_cats,
        key=lambda c: (c["tenant_id"], c["name"].strip()),
        preferred=lambda c: c["event_id"] in running,
    )
    for c in categories:
        cat_map.setdefault(c["id"], c["id"])
    tenant_of_cat = {c["id"]: c["tenant_id"] for c in categories}

    # --- Artikel zusammenführen ----------------------------------------
    products = [dict(r) for r in db.execute(
        """
        SELECT p.id, p.category_id, p.group_id, p.name, p.sort_order, p.deleted, c.event_id,
               c.deleted AS category_deleted
        FROM product p JOIN category c ON c.id = p.category_id
        """
    )]
    live = [p for p in products if not p["deleted"] and not p["category_deleted"]]
    prod_map = _merge_groups(
        [p for p in live if p["group_id"] is None],
        key=lambda p: (cat_map[p["category_id"]], p["name"].strip()),
        preferred=lambda p: p["event_id"] in running,
    )
    prod_map.update(_merge_groups(
        [p for p in live if p["group_id"] is not None],
        key=lambda p: (prod_map.get(p["group_id"], p["group_id"]), p["name"].strip()),
        preferred=lambda p: p["event_id"] in running,
    ))
    for p in products:
        prod_map.setdefault(p["id"], p["id"])

    # --- Aktivierung pro Fest: was jedes Fest vorher hatte ---------------
    db.execute("""
        CREATE TABLE event_category (
            event_id    INTEGER NOT NULL REFERENCES event(id),
            category_id INTEGER NOT NULL REFERENCES category(id),
            PRIMARY KEY (event_id, category_id)
        )
    """)
    db.execute("""
        CREATE TABLE event_product (
            event_id    INTEGER NOT NULL REFERENCES event(id),
            product_id  INTEGER NOT NULL REFERENCES product(id),
            PRIMARY KEY (event_id, product_id)
        )
    """)
    db.executemany(
        "INSERT OR IGNORE INTO event_category (event_id, category_id) VALUES (?, ?)",
        [(c["event_id"], cat_map[c["id"]]) for c in live_cats if c["event_id"] is not None],
    )
    db.executemany(
        "INSERT OR IGNORE INTO event_product (event_id, product_id) VALUES (?, ?)",
        [(p["event_id"], prod_map[p["id"]]) for p in live if p["group_id"] is None and p["event_id"] is not None],
    )

    # --- Verweise umhängen, Doppelte löschen ------------------------------
    moved_products = [(new, old) for old, new in prod_map.items() if new != old]
    db.executemany("UPDATE sale SET product_id = ? WHERE product_id = ?", moved_products)
    db.executemany("UPDATE product SET group_id = ? WHERE group_id = ?", moved_products)
    moved_cats = [(new, old) for old, new in cat_map.items() if new != old]
    db.executemany("UPDATE product SET category_id = ? WHERE category_id = ?", moved_cats)
    _remap_preferences(db, cat_map, prod_map)
    db.executemany("DELETE FROM product WHERE id = ?", [(old,) for _, old in moved_products])

    # --- user_category_access ohne event_id, Häkchen per ODER --------------
    flags = (
        "can_book", "can_storno_5min", "can_storno_unlimited",
        "can_create_article", "can_edit_article", "can_deactivate_article", "can_delete_article",
    )
    merged_access: dict[tuple[int, int], dict] = {}
    for r in db.execute("SELECT * FROM user_category_access"):
        k = (r["user_id"], cat_map.get(r["category_id"], r["category_id"]))
        acc = merged_access.setdefault(k, {f: 0 for f in flags} | {"granted_by": r["granted_by"]})
        for f in flags:
            acc[f] = acc[f] or r[f]
    db.execute("DROP TABLE user_category_access")
    db.execute(f"""
        CREATE TABLE user_category_access (
            id                      INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id                 INTEGER NOT NULL REFERENCES user(id),
            category_id             INTEGER NOT NULL REFERENCES category(id),
            {", ".join(f"{f} INTEGER NOT NULL DEFAULT 0" for f in flags)},
            granted_by              INTEGER REFERENCES user(id),
            granted_at              TEXT    NOT NULL DEFAULT (datetime('now')),
            UNIQUE(user_id, category_id)
        )
    """)
    db.executemany(
        f"INSERT INTO user_category_access (user_id, category_id, {', '.join(flags)}, granted_by) "
        f"VALUES (?, ?, {', '.join('?' * len(flags))}, ?)",
        [(u, c, *(acc[f] for f in flags), acc["granted_by"]) for (u, c), acc in merged_access.items()],
    )

    # --- user_permission ohne event_id ---------------------------------
    # Pro Benutzer die Rechte des laufenden Betriebs; wer dort keine hat,
    # behält die aus „Intern“, sonst die aus seinem letzten Fest.
    rows_by_user: dict[int, dict[int, list]] = {}
    for r in db.execute(
        "SELECT up.*, u.tenant_id FROM user_permission up JOIN user u ON u.id = up.user_id"
    ):
        rows_by_user.setdefault(r["user_id"], {}).setdefault(r["event_id"], []).append(dict(r))
    kept = []
    for by_event in rows_by_user.values():
        tenant = next(iter(by_event.values()))[0]["tenant_id"]
        for source in (active_event.get(tenant), intern_event.get(tenant), max(by_event)):
            if source in by_event:
                kept.extend(by_event[source])
                break
    db.execute("DROP TABLE user_permission")
    db.execute("""
        CREATE TABLE user_permission (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id         INTEGER NOT NULL REFERENCES user(id),
            permission_id   TEXT    NOT NULL REFERENCES permission_node(id),
            granted_by      INTEGER REFERENCES user(id),
            granted_at      TEXT    NOT NULL DEFAULT (datetime('now')),
            UNIQUE(user_id, permission_id)
        )
    """)
    db.executemany(
        "INSERT OR IGNORE INTO user_permission (user_id, permission_id, granted_by, granted_at) VALUES (?, ?, ?, ?)",
        [(r["user_id"], r["permission_id"], r["granted_by"], r["granted_at"]) for r in kept],
    )

    # --- category neu: tenant_id statt event_id --------------------------
    survivors = [c for c in categories if cat_map[c["id"]] == c["id"]]
    db.execute("""
        CREATE TABLE category_v3 (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            tenant_id   INTEGER NOT NULL REFERENCES tenant(id),
            name        TEXT    NOT NULL,
            sort_order  INTEGER NOT NULL DEFAULT 0,
            deleted     INTEGER NOT NULL DEFAULT 0
        )
    """)
    db.executemany(
        "INSERT INTO category_v3 (id, tenant_id, name, sort_order, deleted) VALUES (?, ?, ?, ?, ?)",
        [(c["id"], tenant_of_cat[c["id"]], c["name"], c["sort_order"], c["deleted"]) for c in survivors],
    )
    db.execute("DROP TABLE category")
    db.execute("ALTER TABLE category_v3 RENAME TO category")

    db.execute("CREATE INDEX IF NOT EXISTS idx_category_tenant ON category(tenant_id)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_event_product_product ON event_product(product_id)")


def _remap_preferences(db: sqlite3.Connection, cat_map: dict[int, int], prod_map: dict[int, int]) -> None:
    """The app stores per-user layouts as 'layout.cat_<category id>' (value:
    list of product ids, null = empty slot) and colour overrides as
    'product.color.<product id>'. Point them at the merged ids; where the
    merged id already has its own entry, that one wins."""
    rows = [dict(r) for r in db.execute("SELECT * FROM user_preference_store")]
    existing = {(r["user_id"], r["key"], r["profile"]) for r in rows}
    for r in rows:
        key, value = r["key"], r["value"]
        new_key = key
        if key.startswith("layout.cat_") and key[len("layout.cat_"):].isdigit():
            new_key = f"layout.cat_{cat_map.get(int(key[len('layout.cat_'):]), int(key[len('layout.cat_'):]))}"
            try:
                slots = json.loads(value)
            except ValueError:
                slots = None
            if isinstance(slots, list):
                seen, mapped = set(), []
                for pid in slots:
                    pid = prod_map.get(pid, pid) if isinstance(pid, int) else pid
                    if pid is not None and pid in seen:
                        pid = None
                    seen.add(pid)
                    mapped.append(pid)
                value = json.dumps(mapped)
        elif key.startswith("product.color.") and key[len("product.color."):].isdigit():
            old_id = int(key[len("product.color."):])
            new_key = f"product.color.{prod_map.get(old_id, old_id)}"
        if new_key == key and value == r["value"]:
            continue
        db.execute(
            "DELETE FROM user_preference_store WHERE user_id=? AND key=? AND profile=?",
            (r["user_id"], key, r["profile"]),
        )
        if new_key != key and (r["user_id"], new_key, r["profile"]) in existing:
            continue
        db.execute(
            "INSERT INTO user_preference_store (user_id, key, profile, value) VALUES (?, ?, ?, ?)",
            (r["user_id"], new_key, r["profile"], value),
        )
        existing.add((r["user_id"], new_key, r["profile"]))
