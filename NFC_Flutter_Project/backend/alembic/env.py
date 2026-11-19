"""Alembic environment: runs the migrations in versions/ against
config "sqlalchemy.url" (set by schema.upgrade()). No SQLAlchemy models —
the migrations are plain SQL."""

from alembic import context
from sqlalchemy import create_engine

engine = create_engine(context.config.get_main_option("sqlalchemy.url"))
with engine.connect() as connection:
    context.configure(connection=connection, transaction_per_migration=True)
    with context.begin_transaction():
        context.run_migrations()
engine.dispose()
