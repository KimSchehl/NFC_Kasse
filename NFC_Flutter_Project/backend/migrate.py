"""
Run once against an existing database to add new columns without reinitializing.
Safe to run multiple times — skips columns that already exist.

Usage:
    python migrate.py
"""
import sqlite3
import os

DB_PATH = os.environ.get("DB_PATH", "kasse.db")


def _add_column_if_missing(conn: sqlite3.Connection, table: str, column: str, definition: str):
    existing = [row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    if column not in existing:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")
        print(f"  + {table}.{column}")
    else:
        print(f"  . {table}.{column} already exists — skipped")


def migrate():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=ON")
    print(f"Migrating '{DB_PATH}' ...")

    _add_column_if_missing(conn, "product", "color", "TEXT DEFAULT NULL")
    _add_column_if_missing(conn, "product", "exclude_from_stats", "INTEGER NOT NULL DEFAULT 0")

    # stats_period table (new in this migration)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS stats_period (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id    INTEGER NOT NULL REFERENCES event(id),
        label       TEXT    NOT NULL,
        started_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        closed_at   TEXT,
        created_by  INTEGER REFERENCES user(id)
    )""")
    print("  + stats_period table (created or already existed)")

    # Seed an initial period for event 1 if none exists yet.
    row = conn.execute("SELECT COUNT(*) FROM stats_period WHERE event_id=1").fetchone()
    if row[0] == 0:
        conn.execute(
            "INSERT INTO stats_period (event_id, label, created_by) VALUES (1, 'Start', 1)"
        )
        print("  + stats_period: initial 'Start' period seeded")
    else:
        print("  . stats_period: periods already exist — skipped seed")

    conn.commit()
    conn.close()
    print("Done.")


if __name__ == "__main__":
    migrate()
