"""
Database setup run by the installer: NfcKasseBackend.exe db-setup --input DATEI

The input file (JSON, written by Inno Setup into its own temp folder and
deleted right after) holds the passwords, so they never appear on a command
line:

    {"mode": "install",  "pg_bin": "...\\pgsql\\bin",
     "superuser": "...", "superpassword": "...",
     "kasse_user": "...", "kasse_password": "..."}
    {"mode": "existing", "pg_bin": "...", "host": "localhost", "port": 5432,
     "superuser": "...", "superpassword": "...",
     "kasse_user": "...", "kasse_password": "..."}
    {"mode": "prepared", "pg_bin": "...", "host": "...", "port": 5432,
     "kasse_user": "...", "kasse_password": "..."}

install:  initdb into <data_dir>\\pgdata (UTF-8, German ICU collation, only
          localhost, port 5433), Windows service NfcKassePostgres, start it.
existing: use the PostgreSQL server the user named.
install/existing: create (or update the password of) the kasse role and
          the database nfc_kasse owned by it.
prepared: the server's admin created role and database by hand (the
          installer shows the commands, PREPARE_SQL), no admin login here;
          only the kasse user's own login is checked.
All:      write DATABASE_URL and PG_BIN into config.env, migrate and seed
          the schema. Re-running is harmless.

Output is one JSON line with "ok": true/false, like every admin command.
"""

import argparse
import json
import subprocess
import time
from pathlib import Path
from urllib.parse import quote

import psycopg
from psycopg import sql

import database
import db_backup
from config_env_writer import update_config_env

SERVICE = "NfcKassePostgres"
PORT = 5433  # not 5432: leaves the default port to any other PostgreSQL on this PC
DB_NAME = "nfc_kasse"
NETWORK_SERVICE_SID = "*S-1-5-20"  # account pg_ctl register runs the service as; SID is language-independent


class SetupError(Exception):
    pass


def _run(args: list[str], what: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        raise SetupError(f"{what} fehlgeschlagen: {(result.stderr or result.stdout).strip()}")
    return result.stdout


def _service_exists() -> bool:
    return subprocess.run(["sc", "query", SERVICE], capture_output=True).returncode == 0


def _connect(host: str, port: int, user: str, password: str, timeout: int = 0,
             dbname: str = "postgres") -> psycopg.Connection:
    """Connects (default: the maintenance database); retries for `timeout`
    seconds (a freshly started service needs a moment)."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            return psycopg.connect(
                host=host, port=port, user=user, password=password, dbname=dbname,
                autocommit=True, connect_timeout=5,
            )
        except psycopg.OperationalError as exc:
            if exc.sqlstate == "28P01" or "password authentication failed" in str(exc):
                raise SetupError(f"Anmeldung als „{user}“ abgelehnt: Benutzername oder Passwort falsch.") from exc
            if exc.sqlstate == "3D000" or f'database "{dbname}" does not exist' in str(exc):
                raise SetupError(f"Die Datenbank „{dbname}“ gibt es auf {host}:{port} nicht.") from exc
            if time.monotonic() >= deadline:
                raise SetupError(f"PostgreSQL unter {host}:{port} nicht erreichbar: {exc}") from exc
            time.sleep(1)


def _install_server(pg_bin: Path, data_dir: Path, superuser: str, superpassword: str) -> None:
    pgdata = data_dir / "pgdata"
    if not (pgdata / "PG_VERSION").exists():
        pwfile = data_dir / "pg-init.tmp"
        pwfile.write_text(superpassword + "\n", encoding="utf-8")
        try:
            _run([
                str(pg_bin / "initdb.exe"), "-D", str(pgdata), "-U", superuser, f"--pwfile={pwfile}",
                "-E", "UTF8", "--locale=C", "--locale-provider=icu", "--icu-locale=de-DE",
                "--auth-local=scram-sha-256", "--auth-host=scram-sha-256",
                "-c", f"port={PORT}", "-c", "listen_addresses=localhost",
            ], "Datenbank anlegen (initdb)")
        finally:
            pwfile.unlink(missing_ok=True)
        _run(["icacls", str(pgdata), "/grant", f"{NETWORK_SERVICE_SID}:(OI)(CI)F", "/T", "/Q"],
             "Zugriffsrechte für den Datenbankdienst setzen")
    if not _service_exists():
        _run([str(pg_bin / "pg_ctl.exe"), "register", "-N", SERVICE, "-D", str(pgdata), "-S", "auto"],
             "Datenbankdienst registrieren")
    subprocess.run(["sc", "start", SERVICE], capture_output=True)  # "already running" is fine


def _ensure_role_and_database(conn: psycopg.Connection, user: str, password: str, connect_db) -> None:
    """`connect_db()` opens the existing nfc_kasse database as the admin."""
    role = sql.Identifier(user)
    db_exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,)).fetchone()
    if db_exists:
        # Handing a database with someone else's tables to the kasse user
        # would only fail later (no rights on them) -- or take over data.
        with connect_db() as db:
            foreign = db.execute(
                "SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tableowner <> %s", (user,)
            ).fetchone()[0]
        if foreign:
            raise SetupError(
                f"Die Datenbank „{DB_NAME}“ gibt es auf diesem Server schon, mit Tabellen eines anderen "
                f"Benutzers. Bitte den Benutzer angeben, dem sie gehört (Weg „Administrator legt selbst an“), "
                f"oder die Datenbank vorher entfernen."
            )
    exists = conn.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (user,)).fetchone()
    verb = "ALTER" if exists else "CREATE"
    conn.execute(sql.SQL(verb + " ROLE {} LOGIN PASSWORD {}").format(role, sql.Literal(password)))
    if db_exists:
        conn.execute(sql.SQL("ALTER DATABASE {} OWNER TO {}").format(sql.Identifier(DB_NAME), role))
    else:
        conn.execute(sql.SQL("CREATE DATABASE {} OWNER {} ENCODING 'UTF8' TEMPLATE template0").format(
            sql.Identifier(DB_NAME), role))


def setup(cfg: dict, data_dir: Path) -> dict:
    mode = cfg.get("mode")
    if mode not in ("install", "existing", "prepared"):
        raise SetupError(f"Unbekannter Modus: {mode}")
    required = ("kasse_user", "kasse_password") + (() if mode == "prepared" else ("superuser", "superpassword"))
    for key in required:
        if not cfg.get(key):
            raise SetupError(f"Angabe fehlt: {key}")
    pg_bin = Path(cfg["pg_bin"])

    if mode == "install":
        _install_server(pg_bin, data_dir, cfg["superuser"], cfg["superpassword"])
        host, port = "localhost", PORT
    else:
        host, port = cfg.get("host") or "localhost", int(cfg.get("port") or 5432)

    if mode == "prepared":
        with _connect(host, port, cfg["kasse_user"], cfg["kasse_password"], dbname=DB_NAME) as conn:
            if not conn.execute("SELECT has_database_privilege(current_database(), 'CREATE')").fetchone()[0]:
                raise SetupError(
                    f"„{cfg['kasse_user']}“ darf in der Datenbank „{DB_NAME}“ nichts anlegen. "
                    f"Die Datenbank muss diesem Benutzer gehören (OWNER)."
                )
    else:
        with _connect(host, port, cfg["superuser"], cfg["superpassword"], timeout=60 if mode == "install" else 0) as conn:
            _ensure_role_and_database(
                conn, cfg["kasse_user"], cfg["kasse_password"],
                lambda: _connect(host, port, cfg["superuser"], cfg["superpassword"], dbname=DB_NAME),
            )

    url = f"postgresql://{quote(cfg['kasse_user'], safe='')}:{quote(cfg['kasse_password'], safe='')}@{host}:{port}/{DB_NAME}"
    update_config_env(data_dir / "config.env", {"DATABASE_URL": url, "PG_BIN": str(pg_bin)})

    database.DATABASE_URL = url
    import init_db

    seeded = init_db.setup()
    database.close_pool()
    return {"mode": mode, "host": host, "port": port, "database": DB_NAME, "seeded": seeded}


def main(argv: list[str], data_dir: Path) -> int:
    parser = argparse.ArgumentParser(prog="NfcKasseBackend db-setup")
    parser.add_argument("--input", required=True, type=Path)
    # Plain-text error message for the installer (UTF-8 with BOM, which Inno
    # Setup reads correctly — unlike the escaped JSON line on stdout).
    parser.add_argument("--result", type=Path, default=None)
    args = parser.parse_args(argv)
    try:
        cfg = json.loads(args.input.read_text(encoding="utf-8-sig"))
        result = setup(cfg, data_dir)
    except (SetupError, OSError, ValueError, database.Error) as exc:
        if args.result:
            args.result.write_text(str(exc), encoding="utf-8-sig")
        db_backup._emit({"ok": False, "error": str(exc)})
        return db_backup.EXIT_ERROR
    if args.result:
        args.result.write_text("ok", encoding="utf-8-sig")
    db_backup._emit({"ok": True, **result})
    return db_backup.EXIT_OK
