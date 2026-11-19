"""
Schema migrations (Alembic, plain-SQL revisions in alembic/versions/).

upgrade() brings a database to the newest revision; it is idempotent and
runs on every service start. New schema change = new revision file:
    cd backend && python -m alembic -c alembic.ini revision -m "what changed"
"""

import sys
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory

import database


def _script_location() -> Path:
    # PyInstaller unpacks bundled data next to the modules (sys._MEIPASS).
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
    return base / "alembic"


def _config(url: str | None = None) -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", str(_script_location()))
    url = url or database.DATABASE_URL
    cfg.set_main_option("sqlalchemy.url", url.replace("postgresql://", "postgresql+psycopg://", 1).replace("%", "%%"))
    return cfg


def upgrade(url: str | None = None) -> None:
    command.upgrade(_config(url), "head")


def head() -> str:
    return ScriptDirectory.from_config(_config()).get_current_head()


def known(revision: str) -> bool:
    """False for a revision of a newer program version."""
    try:
        return ScriptDirectory.from_config(_config()).get_revision(revision) is not None
    except Exception:  # alembic raises for unknown ids
        return False


def current(db) -> str | None:
    """Revision of the database behind `db` (None = no schema yet)."""
    row = db.execute(
        "SELECT to_regclass('alembic_version') IS NOT NULL"
    ).fetchone()
    if not row[0]:
        return None
    row = db.execute("SELECT version_num FROM alembic_version").fetchone()
    return row[0] if row else None
