"""
Database access (PostgreSQL via psycopg 3 + connection pool).

get_db() hands out a thin wrapper that keeps the interface the routers were
written against (from the SQLite days): `?` placeholders, rows readable as row["col"]
and row[0], `cursor.lastrowid` (= the first column of an `INSERT …
RETURNING id`). Values come back as plain Python types: UUID keys as str,
NUMERIC as float, TIMESTAMPTZ as a UTC string "YYYY-MM-DD HH:MM:SS", and
Python bools are stored as 0/1 (flag columns are SMALLINT).
"""

import os
import threading
from contextlib import contextmanager
from typing import Generator

import psycopg
from psycopg.adapt import Dumper, Loader
from psycopg.pq import Format
from psycopg.types.numeric import FloatLoader
from psycopg_pool import ConnectionPool

# Dev default only — the service and the installer always set DATABASE_URL in config.env.
DATABASE_URL = os.environ.get("DATABASE_URL") or "postgresql://nfc_kasse_dev:nfc_kasse_dev@localhost:5432/nfc_kasse"

# All database errors (connection lost, constraint violated, ...) — callers
# catch this instead of the driver's class.
Error = psycopg.Error
OperationalError = psycopg.OperationalError
IntegrityError = psycopg.IntegrityError

# Advisory-lock key for whole-database operations (admin commands); tenant
# locks use a hash of the tenant id.
_GLOBAL_LOCK = 0


class _BoolAsInt(Dumper):
    oid = psycopg.adapters.types["int2"].oid

    def dump(self, obj):
        return b"1" if obj else b"0"


class _Text(Loader):
    format = Format.TEXT

    def load(self, data):
        return bytes(data).decode()


class _TimestampAsText(Loader):
    """'2026-11-18 21:05:28.123456+00' -> '2026-11-18 21:05:28' (session runs in UTC)."""

    format = Format.TEXT

    def load(self, data):
        return bytes(data[:19]).decode()


def _configure(conn: psycopg.Connection) -> None:
    conn.adapters.register_loader("numeric", FloatLoader)
    conn.adapters.register_loader("timestamptz", _TimestampAsText)
    conn.adapters.register_loader("timestamp", _TimestampAsText)
    conn.adapters.register_loader("uuid", _Text)  # ids are compared with request strings everywhere
    conn.adapters.register_dumper(bool, _BoolAsInt)


class Row(tuple):
    """sqlite3.Row look-alike: row[0], row["name"], keys(), dict(row)."""

    def __new__(cls, values, index):
        row = super().__new__(cls, values)
        row._index = index
        return row

    def __getitem__(self, key):
        if isinstance(key, str):
            return tuple.__getitem__(self, self._index[key])
        return tuple.__getitem__(self, key)

    def keys(self):
        return list(self._index)


def _row_factory(cursor):
    index = {d.name: i for i, d in enumerate(cursor.description or ())}
    return lambda values: Row(values, index)


def _to_pg(sql: str) -> str:
    """`?` -> `%s` outside string literals and `--` comments; a literal `%` becomes `%%`."""
    out, quote, i = [], None, 0
    while i < len(sql):
        ch = sql[i]
        if quote:
            if ch == quote:
                quote = None
            out.append("%%" if ch == "%" else ch)
        elif ch == "-" and sql.startswith("--", i):
            end = sql.find("\n", i)
            end = len(sql) if end == -1 else end
            out.append(sql[i:end].replace("%", "%%"))
            i = end
            continue
        elif ch in ("'", '"'):
            quote = ch
            out.append(ch)
        elif ch == "?":
            out.append("%s")
        elif ch == "%":
            out.append("%%")
        else:
            out.append(ch)
        i += 1
    return "".join(out)


class Cursor:
    def __init__(self, cur: psycopg.Cursor):
        self._cur = cur

    def fetchone(self):
        return self._cur.fetchone()

    def fetchall(self):
        return self._cur.fetchall()

    def __iter__(self):
        return iter(self._cur)

    @property
    def rowcount(self) -> int:
        return self._cur.rowcount

    @property
    def lastrowid(self):
        """Id of the row an `INSERT … RETURNING id` just created."""
        if self._cur.description is None:
            raise RuntimeError("lastrowid needs INSERT … RETURNING id")
        return self._cur.fetchone()[0]


class Connection:
    def __init__(self, conn: psycopg.Connection):
        self._conn = conn

    def execute(self, sql: str, params=()) -> Cursor:
        cur = self._conn.cursor(row_factory=_row_factory)
        cur.execute(_to_pg(sql), tuple(params))
        return Cursor(cur)

    def executemany(self, sql: str, seq) -> None:
        with self._conn.cursor() as cur:
            cur.executemany(_to_pg(sql), [tuple(p) for p in seq])

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()

    def close(self) -> None:
        self._conn.close()


def connect() -> Connection:
    """A single unpooled connection (command-line tools); caller commits and closes."""
    conn = psycopg.connect(DATABASE_URL, options="-c TimeZone=UTC")
    _configure(conn)
    return Connection(conn)


def use_config(data_dir) -> None:
    """Admin commands run before the service has loaded config.env: take
    DATABASE_URL from there if it is set."""
    from pathlib import Path

    from dotenv import dotenv_values

    global DATABASE_URL
    env_path = Path(data_dir) / "config.env"
    url = dotenv_values(env_path).get("DATABASE_URL") if env_path.exists() else None
    if url:
        DATABASE_URL = url


_pool: ConnectionPool | None = None
_pool_url: str | None = None
_pool_lock = threading.Lock()


def _get_pool() -> ConnectionPool:
    global _pool, _pool_url
    with _pool_lock:
        if _pool is None or _pool_url != DATABASE_URL:
            if _pool is not None:
                _pool.close()
            _pool = ConnectionPool(
                DATABASE_URL,
                min_size=1,
                max_size=10,
                kwargs={"options": "-c TimeZone=UTC"},
                configure=_configure,
                # Drops connections the server closed (PostgreSQL restarted) instead of failing a booking.
                check=ConnectionPool.check_connection,
                open=True,
            )
            _pool_url = DATABASE_URL
        return _pool


def close_pool() -> None:
    """Closes all pooled connections (tests, before dropping a database)."""
    global _pool, _pool_url
    with _pool_lock:
        if _pool is not None:
            _pool.close()
        _pool, _pool_url = None, None


@contextmanager
def get_db(exclusive: bool = False, tenant_id: str | None = None) -> Generator[Connection, None, None]:
    """
    One transaction: commits on success, rolls back on any exception.

    exclusive=True serialises writers that must not interleave (booking:
    balance check + deduction must be atomic). With `tenant_id` only that
    Veranstalter's writers wait for each other, other Veranstalter run in
    parallel; without it the whole database is locked (admin commands).
    """
    with _get_pool().connection() as conn:
        db = Connection(conn)
        if exclusive:
            if tenant_id is None:
                conn.execute("SELECT pg_advisory_xact_lock(%s)", (_GLOBAL_LOCK,))
            else:
                conn.execute("SELECT pg_advisory_xact_lock_shared(%s)", (_GLOBAL_LOCK,))
                # Lock keys are bigint: the tenant's UUID is hashed to one.
                conn.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 1))", (tenant_id,))
        # The pool's context manager commits on success and rolls back on an exception.
        yield db
