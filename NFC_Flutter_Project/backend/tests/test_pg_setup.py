"""db-setup (installer) against a throwaway PostgreSQL cluster in tmp_path —
covers the "existing server" path. The "install" path additionally runs
initdb + registers a Windows service and is only tested by a real install."""

import json
import subprocess
from pathlib import Path

import pytest

import database
import db_backup
import pg_setup

PORT = 5439


@pytest.fixture
def cluster(tmp_path, monkeypatch):
    try:
        bin_dir = Path(db_backup._pg_tool("initdb")).parent
    except db_backup.BackupError:
        pytest.skip("PostgreSQL-Programme nicht gefunden")
    pwfile = tmp_path / "pw"
    pwfile.write_text("Root#Pass 1\n", encoding="utf-8")
    pgdata = tmp_path / "pgdata"
    subprocess.run(
        [str(bin_dir / "initdb"), "-D", str(pgdata), "-U", "kroot", f"--pwfile={pwfile}", "-E", "UTF8",
         "--locale=C", "--auth-local=scram-sha-256", "--auth-host=scram-sha-256", "-c", f"port={PORT}"],
        check=True, capture_output=True,
    )
    pg_ctl = str(bin_dir / "pg_ctl")
    # No captured pipes: the server process would inherit them and the call never returns.
    subprocess.run([pg_ctl, "-D", str(pgdata), "-l", str(tmp_path / "pg.log"), "-w", "start"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    monkeypatch.setattr(database, "DATABASE_URL", database.DATABASE_URL)  # restored after the test
    yield bin_dir
    database.close_pool()
    subprocess.run([pg_ctl, "-D", str(pgdata), "-m", "immediate", "-w", "stop"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _setup(tmp_path, capsys, **cfg) -> tuple[int, dict]:
    data_dir = tmp_path / "data"
    data_dir.mkdir(exist_ok=True)
    (data_dir / "config.env").write_text("SECRET_KEY=x\n", encoding="utf-8")
    (tmp_path / "in.json").write_text(json.dumps(cfg), encoding="utf-8")
    code = pg_setup.main(["--input", str(tmp_path / "in.json"), "--result", str(tmp_path / "result.txt")], data_dir)
    return code, json.loads(capsys.readouterr().out.strip().splitlines()[-1])


def test_existing_server_gets_role_database_and_schema(cluster, tmp_path, capsys):
    cfg = dict(mode="existing", pg_bin=str(cluster), host="localhost", port=PORT,
               superuser="kroot", superpassword="Root#Pass 1",
               kasse_user="kasse", kasse_password='K@sse%$ 99#"ü')
    code, out = _setup(tmp_path, capsys, **cfg)
    assert code == 0 and out["seeded"] is True, out

    env = (tmp_path / "data" / "config.env").read_text(encoding="utf-8")
    assert "SECRET_KEY=x" in env and f"PG_BIN={cluster}" in env
    database.use_config(tmp_path / "data")
    conn = database.connect()
    try:
        assert conn.execute("SELECT current_user").fetchone()[0] == "kasse"
        assert conn.execute("SELECT username FROM app_user").fetchone()[0] == "admin"
    finally:
        conn.close()

    # Running it again (installer re-run) changes nothing and seeds nothing.
    code, out = _setup(tmp_path, capsys, **cfg)
    assert code == 0 and out["seeded"] is False


def test_wrong_admin_password_is_reported(cluster, tmp_path, capsys):
    code, out = _setup(tmp_path, capsys, mode="existing", pg_bin=str(cluster), port=PORT,
                       superuser="kroot", superpassword="falsch", kasse_user="kasse", kasse_password="x" * 8)
    assert code == 1 and "abgelehnt" in out["error"]
    assert "abgelehnt" in (tmp_path / "result.txt").read_text(encoding="utf-8-sig")
    assert "DATABASE_URL" not in (tmp_path / "data" / "config.env").read_text(encoding="utf-8")


def test_prepared_mode_uses_the_admins_own_role_and_database(cluster, tmp_path, capsys):
    """The IT admin ran the installer's commands himself; Setup gets no admin login."""
    import psycopg

    with psycopg.connect(host="localhost", port=PORT, user="kroot", password="Root#Pass 1",
                         dbname="postgres", autocommit=True) as admin:
        admin.execute("CREATE ROLE kasse LOGIN PASSWORD 'selbst-angelegt'")
        code, out = _setup(tmp_path, capsys, mode="prepared", pg_bin=str(cluster), port=PORT,
                           kasse_user="kasse", kasse_password="selbst-angelegt")
        assert code == 1 and "gibt es" in out["error"]

        admin.execute("CREATE DATABASE nfc_kasse OWNER kasse ENCODING 'UTF8' TEMPLATE template0")
    code, out = _setup(tmp_path, capsys, mode="prepared", pg_bin=str(cluster), port=PORT,
                       kasse_user="kasse", kasse_password="selbst-angelegt")
    assert code == 0 and out["seeded"] is True, out


def test_existing_database_of_another_user_is_refused(cluster, tmp_path, capsys):
    import psycopg

    with psycopg.connect(host="localhost", port=PORT, user="kroot", password="Root#Pass 1",
                         dbname="postgres", autocommit=True) as admin:
        admin.execute("CREATE DATABASE nfc_kasse")
    with psycopg.connect(host="localhost", port=PORT, user="kroot", password="Root#Pass 1",
                         dbname="nfc_kasse", autocommit=True) as db:
        db.execute("CREATE TABLE fremd (x int)")
    code, out = _setup(tmp_path, capsys, mode="existing", pg_bin=str(cluster), port=PORT,
                       superuser="kroot", superpassword="Root#Pass 1", kasse_user="kasse", kasse_password="x" * 8)
    assert code == 1 and "gibt es auf diesem Server schon" in out["error"]
