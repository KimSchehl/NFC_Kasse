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

    conn.commit()
    conn.close()
    print("Done.")


if __name__ == "__main__":
    migrate()
