import os
import sqlite3
from contextlib import contextmanager
from typing import Generator

DB_PATH = os.environ.get("DB_PATH", "kasse.db")


@contextmanager
def get_db(exclusive: bool = False) -> Generator[sqlite3.Connection, None, None]:
    """
    Context manager for database access.
    Commits on success, rolls back on any exception.

    Use exclusive=True for write operations that must prevent concurrent
    modifications (e.g. booking: balance check + deduction must be atomic).
    """
    # timeout=10 (seconds SQLite will wait/retry on a locked db before
    # raising) rather than the sqlite3 module's own 5s default -- with
    # several tablets booking concurrently, each briefly taking the
    # exclusive write lock, 5s occasionally wasn't enough and surfaced as a
    # bare "database is locked" (observed taking down the print worker
    # thread entirely, since it wasn't guarded against it — see
    # routers/printer.py's _print_worker()).
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    if exclusive:
        conn.execute("BEGIN EXCLUSIVE")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
