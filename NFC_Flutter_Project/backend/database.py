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
    conn = sqlite3.connect(DB_PATH)
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
