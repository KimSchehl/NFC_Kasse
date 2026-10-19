"""
Fest starten/beenden — via admin_cli.py, the commands the admin tool runs on
the server. data_dir is tmp_path throughout, so safety backups, bon.yaml and
config.env all land there and never touch the repo or a real installation.
"""
import json
from pathlib import Path

import admin_cli
import database
from tests.conftest import add_category, add_product


def _cli(capsys, data_dir, *argv):
    code = admin_cli.main(list(argv), data_dir, db_path=Path(database.DB_PATH))
    out = capsys.readouterr().out.strip().splitlines()[-1]
    return code, json.loads(out)


def _intern_id(conn):
    return conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]


def _active_id(conn):
    return conn.execute("SELECT id FROM event WHERE active = 1").fetchone()[0]


def _switch_to_intern(conn):
    intern_id = _intern_id(conn)
    conn.execute("UPDATE event SET active = 0 WHERE active = 1")
    conn.execute("UPDATE event SET active = 1 WHERE id = ?", (intern_id,))


def test_cannot_start_a_fest_while_one_is_already_running(db, tmp_path, capsys):
    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Herbstfest")
    assert code == 1
    assert out["ok"] is False
    assert "läuft bereits" in out["error"]
    # Refused before the safety backup — nothing to roll back, nothing written.
    assert not list((tmp_path / "backups").glob("vor-festwechsel_*.db"))


def test_cannot_end_a_fest_while_intern_is_running(db, tmp_path, capsys):
    with database.get_db() as conn:
        _switch_to_intern(conn)
    code, out = _cli(capsys, tmp_path, "event-end")
    assert code == 1
    assert "kein Fest" in out["error"]


def test_refuses_to_run_without_a_database(tmp_path, capsys):
    missing = tmp_path / "kasse.db"
    code = admin_cli.main(["events"], tmp_path, db_path=missing)
    out = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert code == 1
    assert "nicht gefunden" in out["error"]
    assert not missing.exists(), "must not create an empty kasse.db"


def test_start_switches_active_event_and_takes_a_safety_backup(db, tmp_path, capsys):
    with database.get_db() as conn:
        before = _intern_id(conn)
        _switch_to_intern(conn)

    code, out = _cli(
        capsys, tmp_path, "event-start", "--name", "Herbstfest", "--deposit", "5", "--date", "2026-10-03"
    )
    assert code == 0, out
    event = out["event"]
    assert event["name"] == "Herbstfest"
    assert event["active"] is True
    assert event["is_intern"] is False
    assert event["chip_deposit"] == 5.0
    assert out["needs_restart"] is False

    with database.get_db() as conn:
        assert _active_id(conn) == event["id"]
        assert conn.execute("SELECT active FROM event WHERE id=?", (before,)).fetchone()[0] == 0
        period = conn.execute("SELECT label, closed_at FROM stats_period WHERE event_id=?", (event["id"],)).fetchone()
        assert period["label"] == "Start" and period["closed_at"] is None

    assert (tmp_path / "backups" / out["safety_backup"]).exists()


def test_start_copies_the_selection_and_rights_stay(
    client, auth_headers, other_user_auth_headers, db, tmp_path, capsys
):
    with database.get_db() as conn:
        source_event = _active_id(conn)
        cat_id = add_category(conn, "Getränke")
        bier = add_product(conn, cat_id, "Bier", 2.5, stock=7)
        cola = add_product(conn, cat_id, "Cola", 2.0)
        conn.execute("DELETE FROM event_product WHERE event_id=? AND product_id=?", (source_event, cola))
        other_id = conn.execute("SELECT id FROM user WHERE username='other_operator'").fetchone()[0]
        conn.execute("INSERT INTO user_category_access (user_id, category_id, can_book) VALUES (?, ?, 1)", (other_id, cat_id))
        _switch_to_intern(conn)

    code, out = _cli(
        capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Herbstfest", "--keep-stock", "--source-event", str(source_event)
    )
    assert code == 0, out
    new_event_id = out["event"]["id"]

    with database.get_db() as conn:
        # Same category and article rows — nothing is copied, only switched on.
        assert [r[0] for r in conn.execute("SELECT category_id FROM event_category WHERE event_id=?", (new_event_id,))] == [cat_id]
        assert [r[0] for r in conn.execute("SELECT product_id FROM event_product WHERE event_id=?", (new_event_id,))] == [bier]
        assert conn.execute("SELECT stock FROM product WHERE id=?", (bier,)).fetchone()[0] == 7
        assert conn.execute("SELECT COUNT(*) FROM product").fetchone()[0] == 2
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available) VALUES (1, 'EVTEST01', 10.0, 0)"
        )

    # The non-manager other_operator books in the new fest with the right
    # granted once — rights belong to the user, not to a fest.
    booking = client.post(
        "/api/sales/", json={"nfc_uid": "EVTEST01", "product_ids": [bier]}, headers=other_user_auth_headers,
    )
    assert booking.status_code == 201, booking.text
    # Cola wasn't switched on in the source fest, so it isn't in the new one either.
    cola_booking = client.post(
        "/api/sales/", json={"nfc_uid": "EVTEST01", "product_ids": [cola]}, headers=auth_headers,
    )
    assert cola_booking.status_code == 409


def test_start_resets_stock_by_default_and_can_pick_categories(db, tmp_path, capsys):
    with database.get_db() as conn:
        source_event = _active_id(conn)
        drinks = add_category(conn, "Getränke")
        bier = add_product(conn, drinks, "Bier", 2.5, stock=7)
        food = add_category(conn, "Essen")
        add_product(conn, food, "Wurst", 4.0)
        # Not switched on anywhere yet: picked explicitly, it comes with all its articles.
        dessert = conn.execute("INSERT INTO category (tenant_id, name) VALUES (1, 'Nachtisch')").lastrowid
        eis = conn.execute("INSERT INTO product (category_id, name, price) VALUES (?, 'Eis', 2.0)", (dessert,)).lastrowid
        _switch_to_intern(conn)

    code, out = _cli(
        capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Herbstfest", "--source-event", str(source_event),
        "--categories", f"{drinks},{dessert}",
    )
    assert code == 0, out
    new_event_id = out["event"]["id"]
    with database.get_db() as conn:
        cats = {r[0] for r in conn.execute("SELECT category_id FROM event_category WHERE event_id=?", (new_event_id,))}
        prods = {r[0] for r in conn.execute("SELECT product_id FROM event_product WHERE event_id=?", (new_event_id,))}
        assert cats == {drinks, dessert}
        assert prods == {bier, eis}
        assert conn.execute("SELECT stock FROM product WHERE id=?", (bier,)).fetchone()[0] is None


def test_empty_start_switches_nothing_on(db, tmp_path, capsys):
    with database.get_db() as conn:
        add_product(conn, add_category(conn, "Getränke"), "Bier", 2.5)
        _switch_to_intern(conn)
    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Leer")
    assert code == 0, out
    with database.get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM event_category WHERE event_id=?", (out["event"]["id"],)).fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM category").fetchone()[0] == 1  # still there, just not shown


def test_end_archives_the_fest_and_switches_back_to_intern(db, tmp_path, capsys):
    with database.get_db() as conn:
        fest_id = _active_id(conn)
        intern_id = _intern_id(conn)
        conn.execute(
            "INSERT INTO pager_order (event_id, created_by, item_summary, pager_number, status) "
            "VALUES (?, 1, 'Pizza', 7, 'open')",
            (fest_id,),
        )

    code, out = _cli(capsys, tmp_path, "event-end")
    assert code == 0, out
    assert out["event"]["id"] == fest_id
    assert out["event"]["ended_at"] is not None

    with database.get_db() as conn:
        assert _active_id(conn) == intern_id
        assert conn.execute("SELECT active FROM event WHERE id=?", (fest_id,)).fetchone()[0] == 0
        pager = conn.execute("SELECT status FROM pager_order WHERE event_id=?", (fest_id,)).fetchone()
        assert pager["status"] == "done"
        open_periods = conn.execute(
            "SELECT COUNT(*) FROM stats_period WHERE event_id=? AND closed_at IS NULL", (fest_id,)
        ).fetchone()[0]
        assert open_periods == 0


def test_events_overview_lists_periods_and_end_warnings(db, tmp_path, capsys):
    with database.get_db() as conn:
        fest_id = _active_id(conn)
        conn.execute(
            "INSERT INTO print_job (event_id, username, event_name, product_name, price) "
            "VALUES (?, 'admin', 'Fest', 'Bier', 3.0)",
            (fest_id,),
        )
        conn.execute("INSERT INTO customer (tenant_id, nfc_uid, balance) VALUES (1, 'REST01', 4.5)")

    code, out = _cli(capsys, tmp_path, "events")
    assert code == 0, out
    assert out["active_event_id"] == fest_id
    assert out["open_print_jobs"] == 1
    assert out["chips_with_balance"] == 1
    assert out["chips_balance_total"] == 4.5
    fest = next(e for e in out["events"] if e["id"] == fest_id)
    assert [p["label"] for p in fest["periods"]] == ["Start"]
    assert out["events"][0]["is_intern"] is True  # Intern always listed first


def test_overview_reports_the_last_till_activity(client, auth_headers, product_id, customer_with_balance, db, tmp_path, capsys):
    code, out = _cli(capsys, tmp_path, "events")
    assert out["last_activity_at"] is None
    assert out["seconds_since_last_activity"] is None

    resp = client.post("/api/topup/", json={"nfc_uid": customer_with_balance, "amount": 5}, headers=auth_headers)
    assert resp.status_code == 201, resp.text
    code, out = _cli(capsys, tmp_path, "events")
    assert out["last_activity_at"] is not None
    assert 0 <= out["seconds_since_last_activity"] < 60


def test_stale_device_booking_old_articles_gets_event_changed(
    client, auth_headers, product_id, customer_with_balance, db, tmp_path, capsys
):
    # product_id belongs to the running fest; ending it makes it "old".
    assert _cli(capsys, tmp_path, "event-end")[0] == 0

    resp = client.post(
        "/api/sales/", json={"nfc_uid": customer_with_balance, "product_ids": [product_id]}, headers=auth_headers
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["code"] == "event_changed"
    assert "nicht mehr aktiv" in resp.json()["detail"]

    resp = client.post("/api/print/bon", json={"items": [{"product_id": product_id, "quantity": 1}]}, headers=auth_headers)
    assert resp.status_code == 409, resp.text
    assert resp.json()["code"] == "event_changed"

    with database.get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM sale").fetchone()[0] == 0


def test_write_racing_a_fest_switch_is_rejected_not_booked_into_the_old_fest(
    client, auth_headers, product_id, customer_with_balance, db, tmp_path, capsys
):
    """The request resolved the active event (the fest) before the switch
    committed; it only gets the write lock afterwards. Simulated by pinning
    get_active_event to the fest's row while the DB already says Intern."""
    from dependencies import get_active_event
    from main import app

    with database.get_db() as conn:
        fest = dict(conn.execute("SELECT * FROM event WHERE active = 1").fetchone())
    assert _cli(capsys, tmp_path, "event-end")[0] == 0

    app.dependency_overrides[get_active_event] = lambda: fest
    try:
        booking = client.post(
            "/api/sales/", json={"nfc_uid": customer_with_balance, "product_ids": [product_id]}, headers=auth_headers
        )
        topup = client.post("/api/topup/", json={"nfc_uid": customer_with_balance, "amount": 5}, headers=auth_headers)
        payout = client.post(f"/api/topup/payout/{customer_with_balance}", headers=auth_headers)
        close = client.post("/api/stats/periods/close", json={"label": "Mittag"}, headers=auth_headers)
    finally:
        app.dependency_overrides.pop(get_active_event, None)

    for resp in (booking, topup, payout, close):
        assert resp.status_code == 409, resp.text
        assert resp.json()["code"] == "event_changed"

    with database.get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM sale WHERE event_id=?", (fest["id"],)).fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM topup WHERE event_id=?", (fest["id"],)).fetchone()[0] == 0
        assert conn.execute(
            "SELECT COUNT(*) FROM stats_period WHERE event_id=? AND closed_at IS NULL", (fest["id"],)
        ).fetchone()[0] == 0
        assert conn.execute(
            "SELECT balance FROM customer WHERE nfc_uid=?", (customer_with_balance,)
        ).fetchone()[0] == 20.0


def test_health_reports_the_active_event(client, db, tmp_path, capsys):
    with database.get_db() as conn:
        fest_id = _active_id(conn)
        intern_id = _intern_id(conn)
    assert client.get("/health").json()["active_events"] == [fest_id]

    _cli(capsys, tmp_path, "event-end")
    assert client.get("/health").json()["active_events"] == [intern_id]


def test_tagesabschluss_is_blocked_while_intern_is_running(client, auth_headers, db):
    with database.get_db() as conn:
        _switch_to_intern(conn)
    resp = client.post("/api/stats/periods/close", json={"label": "Mittag"}, headers=auth_headers)
    assert resp.status_code == 400, resp.text
    assert "Fest" in resp.json()["detail"]


def test_me_reports_the_active_events_name_and_intern_flag(client, auth_headers, db):
    resp = client.get("/api/auth/me", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["event_is_intern"] is False
    assert isinstance(data["event_name"], str) and data["event_name"]

    with database.get_db() as conn:
        _switch_to_intern(conn)
    resp = client.get("/api/auth/me", headers=auth_headers)
    assert resp.json()["event_name"] == "Intern"
    assert resp.json()["event_is_intern"] is True


def test_migration_removes_retired_permissions_from_existing_installs(db):
    from migrations import run_migrations

    with database.get_db() as conn:
        conn.executemany(
            "INSERT INTO permission_node (id, parent_id, label, node_type, sort_order) VALUES (?, ?, ?, ?, ?)",
            [
                ("statistics.export", "statistics", "Daten exportieren", "r", 3),
                ("event", None, "Veranstaltung", "group", 9),
                ("event.manage", "event", "Fest starten/beenden", "w", 1),
            ],
        )
        for perm in ("statistics.export", "event.manage"):
            conn.execute("INSERT INTO user_permission (user_id, permission_id) VALUES (1, ?)", (perm,))
        template_id = conn.execute("SELECT id FROM role_template LIMIT 1").fetchone()[0]
        conn.execute("INSERT INTO role_template_permission VALUES (?, 'statistics.export')", (template_id,))

        run_migrations(conn, bar_chip_uid="BAR")

        retired = ("statistics.export", "event", "event.manage")
        assert conn.execute(
            "SELECT COUNT(*) FROM permission_node WHERE id IN (?, ?, ?)", retired
        ).fetchone()[0] == 0
        assert conn.execute(
            "SELECT COUNT(*) FROM user_permission WHERE permission_id IN (?, ?, ?)", retired
        ).fetchone()[0] == 0
        assert conn.execute(
            "SELECT COUNT(*) FROM role_template_permission WHERE permission_id IN (?, ?, ?)", retired
        ).fetchone()[0] == 0
        # Everything else the admin had is untouched.
        assert conn.execute(
            "SELECT 1 FROM user_permission WHERE user_id=1 AND permission_id='statistics.revenue'"
        ).fetchone()


def test_retired_permissions_are_gone(client, auth_headers, db):
    with database.get_db() as conn:
        nodes = {r[0] for r in conn.execute("SELECT id FROM permission_node")}
    assert not nodes & {"statistics.export", "event", "event.manage"}
    perms = client.get("/api/auth/me", headers=auth_headers).json()["permissions"]
    assert "statistics.export" not in perms
    assert "event.manage" not in perms


def test_start_needs_a_deposit(db, tmp_path, capsys):
    import pytest

    with database.get_db() as conn:
        _switch_to_intern(conn)
    with pytest.raises(SystemExit):
        admin_cli.main(["event-start", "--name", "Ohne Pfand"], tmp_path, db_path=Path(database.DB_PATH))


def test_update_changes_name_and_deposit_of_the_running_fest_live(
    client, auth_headers, db, tmp_path, capsys
):
    code, out = _cli(capsys, tmp_path, "event-update", "--name", "Weinfest", "--deposit", "2.5")
    assert code == 0, out
    assert out["event"]["name"] == "Weinfest" and out["event"]["chip_deposit"] == 2.5
    # No restart: the next request already sees it.
    assert client.get("/api/auth/me", headers=auth_headers).json()["event_name"] == "Weinfest"
    assert client.get("/api/sales/balance/NEWCHIP1", headers=auth_headers).json()["chip_deposit"] == 2.5


def test_update_keeps_the_deposit_already_paid_for_a_chip(client, auth_headers, db, tmp_path, capsys):
    with database.get_db() as conn:
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, deposit_paid) VALUES (1, 'OLDCHIP', 5, 0, 3.0)"
        )
    assert _cli(capsys, tmp_path, "event-update", "--deposit", "1")[0] == 0
    assert client.get("/api/sales/balance/OLDCHIP", headers=auth_headers).json()["chip_deposit"] == 3.0


def test_intern_keeps_its_name_but_its_deposit_can_change(db, tmp_path, capsys):
    with database.get_db() as conn:
        _switch_to_intern(conn)
    code, out = _cli(capsys, tmp_path, "event-update", "--name", "Anders")
    assert code == 1 and "Name nicht ändern" in out["error"]
    code, out = _cli(capsys, tmp_path, "event-update", "--deposit", "2")
    assert code == 0 and out["event"]["chip_deposit"] == 2.0
