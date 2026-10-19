"""
Festvorlage export/import and the accounting CSV export — via admin_cli.py.
data_dir is tmp_path throughout, so bon.yaml/config.env reads and writes
never touch the repo-tracked backend/bon.yaml or a real installation.
"""
import csv
import json
from pathlib import Path

import pytest
import yaml

import admin_cli
import database
from tests.conftest import add_category, add_product


def _cli(capsys, data_dir, *argv):
    code = admin_cli.main(list(argv), data_dir, db_path=Path(database.DB_PATH))
    out = capsys.readouterr().out.strip().splitlines()[-1]
    return code, json.loads(out)


def _active_id(conn):
    return conn.execute("SELECT id FROM event WHERE active = 1").fetchone()[0]


def _intern_id(conn):
    return conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]


def _switch_to_intern(conn):
    intern_id = conn.execute("SELECT id FROM event WHERE is_intern = 1").fetchone()[0]
    conn.execute("UPDATE event SET active = 0 WHERE active = 1")
    conn.execute("UPDATE event SET active = 1 WHERE id = ?", (intern_id,))


def test_export_unknown_event_fails(db, tmp_path, capsys):
    code, out = _cli(capsys, tmp_path, "preset-export", "999999", str(tmp_path / "x.json"))
    assert code == 1
    assert "nicht gefunden" in out["error"]


def test_export_writes_categories_products_and_settings(db, tmp_path, capsys):
    (tmp_path / "bon.yaml").write_text("footer:\n  blank_lines: 5\n", encoding="utf-8")
    (tmp_path / "config.env").write_text(
        "# Kommentar\nSECRET_KEY=geheim\nPRINTER_TYPE=network\nBON_FOOTER_TEXT=Danke!\n", encoding="utf-8"
    )
    with database.get_db() as conn:
        event_id = _active_id(conn)
        conn.execute("UPDATE event SET chip_deposit = 3.5 WHERE id = ?", (event_id,))
        cat_id = add_category(conn, "Getränke")
        base_id = add_product(conn, cat_id, "Bier", 3.0)
        add_product(conn, cat_id, "0,5l", 0, group_id=base_id)
        # Not switched on in this fest, so not part of its Festvorlage.
        add_product(conn, add_category(conn, "Anderswo", event_id=_intern_id(conn)), "Kaffee", 1.0,
                    event_id=_intern_id(conn))

    target = tmp_path / "vorlage.json"
    code, out = _cli(capsys, tmp_path, "preset-export", str(event_id), str(target))
    assert code == 0, out
    assert out["categories"] == 1 and out["products"] == 2

    preset = json.loads(target.read_text(encoding="utf-8"))
    assert preset["chip_deposit"] == 3.5
    cat_ref = preset["categories"][0]["ref"]
    by_name = {p["name"]: p for p in preset["products"]}
    assert by_name["Bier"]["category_ref"] == cat_ref
    assert by_name["Bier"]["group_ref"] is None
    assert by_name["0,5l"]["group_ref"] == by_name["Bier"]["ref"]
    assert preset["bon_layout"] == {"footer": {"blank_lines": 5}}
    assert preset["printer"] == {"PRINTER_TYPE": "network"}
    assert preset["bon_text"] == {"BON_FOOTER_TEXT": "Danke!"}
    # Never part of a Festvorlage.
    assert "geheim" not in target.read_text(encoding="utf-8")


def _shown_products(conn, event_id):
    return [dict(r) for r in conn.execute(
        "SELECT p.id, p.name, p.price, p.stock FROM product p "
        "JOIN event_product ep ON ep.product_id = p.id WHERE ep.event_id = ? ORDER BY p.id",
        (event_id,),
    )]


def test_export_then_import_into_the_same_veranstalter_reuses_the_articles(db, tmp_path, capsys):
    with database.get_db() as conn:
        source_event = _active_id(conn)
        pizza = add_product(conn, add_category(conn, "Essen"), "Pizza", 6.0, stock=42)
        _switch_to_intern(conn)

    file = tmp_path / "vorlage.json"
    assert _cli(capsys, tmp_path, "preset-export", str(source_event), str(file))[0] == 0

    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Aus Datei", "--keep-stock", "--preset", str(file))
    assert code == 0, out
    assert out["needs_restart"] is False  # no settings flags were given

    with database.get_db() as conn:
        # Matched by name: the existing article is switched on, not duplicated.
        assert _shown_products(conn, out["event"]["id"]) == [{"id": pizza, "name": "Pizza", "price": 6.0, "stock": 42}]
        assert conn.execute("SELECT COUNT(*) FROM product").fetchone()[0] == 1


def test_import_creates_what_the_veranstalter_does_not_have_yet(db, tmp_path, capsys):
    file = tmp_path / "vorlage.json"
    file.write_text(json.dumps({
        "categories": [{"ref": 0, "name": "Essen"}],
        "products": [
            {"ref": 0, "category_ref": 0, "name": "Currywurst", "price": 4.5, "stock": 30},
            {"ref": 1, "category_ref": 0, "name": "mit Pommes", "price": 7.0, "group_ref": 0},
        ],
    }), encoding="utf-8")
    with database.get_db() as conn:
        _switch_to_intern(conn)

    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Neu", "--reset-stock", "--preset", str(file))
    assert code == 0, out
    with database.get_db() as conn:
        shown = _shown_products(conn, out["event"]["id"])
        assert [(p["name"], p["stock"]) for p in shown] == [("Currywurst", None)]
        option = conn.execute("SELECT group_id FROM product WHERE name = 'mit Pommes'").fetchone()[0]
        assert option == shown[0]["id"]


def test_import_without_articles_starts_empty(db, tmp_path, capsys):
    file = tmp_path / "vorlage.json"
    file.write_text(json.dumps({
        "categories": [{"ref": 0, "name": "Essen"}],
        "products": [{"ref": 0, "category_ref": 0, "name": "Pizza", "price": 6.0}],
    }), encoding="utf-8")
    with database.get_db() as conn:
        _switch_to_intern(conn)

    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Leer", "--preset", str(file), "--no-articles")
    assert code == 0, out
    with database.get_db() as conn:
        count = conn.execute("SELECT COUNT(*) FROM event_category WHERE event_id=?", (out["event"]["id"],)).fetchone()[0]
    assert count == 0


def test_start_rejects_both_source_event_and_preset(db, tmp_path):
    with pytest.raises(SystemExit):  # argparse: mutually exclusive options
        admin_cli.main(
            ["event-start", "--deposit", "0", "--name", "X", "--source-event", "1", "--preset", "x.json"],
            tmp_path,
            db_path=Path(database.DB_PATH),
        )


def test_invalid_preset_file_is_refused_before_anything_changes(db, tmp_path, capsys):
    file = tmp_path / "kaputt.json"
    file.write_text("{ das ist kein json", encoding="utf-8")
    with database.get_db() as conn:
        _switch_to_intern(conn)
        before = _active_id(conn)

    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "X", "--preset", str(file))
    assert code == 1
    assert "keine gültige Festvorlage" in out["error"]
    with database.get_db() as conn:
        assert _active_id(conn) == before


def test_import_can_apply_bon_layout_printer_and_text(db, tmp_path, capsys):
    (tmp_path / "config.env").write_text(
        "# bleibt stehen\nSECRET_KEY=geheim\nPRINTER_TYPE=serial\n", encoding="utf-8"
    )
    file = tmp_path / "vorlage.json"
    file.write_text(json.dumps({
        "bon_layout": {"footer": {"blank_lines": 7}},
        "printer": {"PRINTER_TYPE": "network", "PRINTER_HOST": "10.0.0.5", "SECRET_KEY": "eingeschmuggelt"},
        "bon_text": {"BON_FOOTER_TEXT": "Danke für den Besuch!"},
    }), encoding="utf-8")
    with database.get_db() as conn:
        _switch_to_intern(conn)

    code, out = _cli(
        capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Mit Einstellungen", "--preset", str(file),
        "--bon-layout", "--printer", "--bon-text",
    )
    assert code == 0, out
    assert out["needs_restart"] is True

    assert yaml.safe_load((tmp_path / "bon.yaml").read_text(encoding="utf-8"))["footer"]["blank_lines"] == 7
    config_env = (tmp_path / "config.env").read_text(encoding="utf-8")
    assert "# bleibt stehen" in config_env
    assert "PRINTER_TYPE=network" in config_env
    assert "PRINTER_TYPE=serial" not in config_env
    assert "PRINTER_HOST=10.0.0.5" in config_env
    assert "BON_FOOTER_TEXT=Danke für den Besuch!" in config_env
    # Only known printer/bon keys are ever written, whatever the file contains.
    assert "SECRET_KEY=geheim" in config_env
    assert "eingeschmuggelt" not in config_env


def test_import_without_settings_flags_does_not_write_any_files(db, tmp_path, capsys):
    file = tmp_path / "vorlage.json"
    file.write_text(json.dumps({
        "bon_layout": {"footer": {"blank_lines": 7}},
        "printer": {"PRINTER_TYPE": "network"},
    }), encoding="utf-8")
    with database.get_db() as conn:
        _switch_to_intern(conn)

    code, out = _cli(capsys, tmp_path, "event-start", "--deposit", "0", "--name", "Nur Artikel", "--preset", str(file))
    assert code == 0, out
    assert out["needs_restart"] is False
    assert not (tmp_path / "bon.yaml").exists()
    assert not (tmp_path / "config.env").exists()


def _csv_sections(path):
    """The export as {section title: rows}; the bookings block has no title row."""
    rows = list(csv.reader(path.read_text(encoding="utf-8-sig").splitlines(), delimiter=";"))
    sections, current = {"Buchungen": []}, "Buchungen"
    for i, row in enumerate(rows):
        if not row:
            continue
        if len(row) == 1 and i > 0 and not rows[i - 1]:
            current = row[0]
            sections[current] = []
        else:
            sections[current].append(row)
    return sections


@pytest.fixture
def accounting_fest(client, auth_headers, db):
    """
    One fest with every kind of money movement:
    - chip G1: one booking with Aufladung 10 €, 2× Bier, Pfand hin + zurück
      (chip deposit 2 € taken), then one Bier storniert, then paid out via
      the Auszahlungs-Artikel (5 € Guthaben + 2 € Chip-Pfand = 7 €)
    - chip G2: 20 € via the Aufladen function, then paid out via the payout function
    - 1 Bier bar über Bon-Druck
    - chips G3 (4,50 € left, 2 € Pfand) and G4 (−1,50 €) only exist, no activity
    """
    with database.get_db() as conn:
        event_id = _active_id(conn)
        conn.execute("UPDATE event SET chip_deposit = 2.0 WHERE id = ?", (event_id,))
        drinks = add_category(conn, "Getränke")
        till = add_category(conn, "Kasse")
        conn.execute("UPDATE category SET sort_order = 1 WHERE id = ?", (till,))

        def product(cat, name, price, sort, **flags):
            return add_product(conn, cat, name, price, sort_order=sort, **flags)

        ids = {
            "bier": product(drinks, "Bier", 3.0, 0),
            "aufladen": product(till, "Aufladen 10", -10.0, 0, exclude_from_stats=1),
            "pfand": product(till, "Pfand Becher", 2.0, 1, is_pfand=1, exclude_from_stats=1),
            "pfand_zurueck": product(till, "Pfand zurück", -2.0, 2, is_pfand=1, exclude_from_stats=1),
            "auszahlen": product(till, "Auszahlen", 0.0, 3, is_payout=1),
        }
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, deposit_paid) VALUES (1, 'G3', 4.5, 0, 2.0)"
        )
        conn.execute(
            "INSERT INTO customer (tenant_id, nfc_uid, balance, is_available, deposit_paid) VALUES (1, 'G4', -1.5, 0, 0)"
        )

    def ok(resp, status=201):
        assert resp.status_code == status, resp.text
        return resp.json()

    booking = ok(client.post("/api/sales/", json={"nfc_uid": "G1", "product_ids": [
        ids["aufladen"], ids["bier"], ids["bier"], ids["pfand"], ids["pfand_zurueck"],
    ]}, headers=auth_headers))
    ok(client.post(f"/api/sales/{booking['sale_ids'][1]}/cancel", headers=auth_headers), 200)
    with database.get_db() as conn:
        # Past the 2-second double-booking guard for the payout below.
        conn.execute("UPDATE sale SET booked_at = datetime(booked_at, '-1 minute')")
    payout = ok(client.post("/api/sales/", json={"nfc_uid": "G1", "product_ids": [ids["auszahlen"]]}, headers=auth_headers))
    assert payout["chip_deposit_refunded"] == 2.0

    ok(client.post("/api/topup/", json={"nfc_uid": "G2", "amount": 20}, headers=auth_headers))
    ok(client.post("/api/topup/payout/G2", headers=auth_headers), 200)
    ok(client.post("/api/print/bon", json={"items": [{"product_id": ids["bier"], "quantity": 1}]}, headers=auth_headers), 200)
    return event_id


def test_csv_export_bookings_articles_and_summary(client, auth_headers, accounting_fest, tmp_path, capsys):
    target = tmp_path / "buchungen.csv"
    code, out = _cli(capsys, tmp_path, "csv-export", str(accounting_fest), str(target))
    assert code == 0, out
    assert out["rows"] == 7  # 5 in G1's booking + G1's payout + 1 bar

    # German Excel: ';', decimal comma, CRLF, BOM.
    raw = target.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    assert b"\r\n" in raw

    sections = _csv_sections(target)
    bookings = sections["Buchungen"]
    assert bookings[0] == ["Nr", "Zeitpunkt", "Chip", "Warengruppe", "Artikel", "Art",
                           "Betrag", "Kassierer", "Storniert", "Storniert am"]
    assert len(bookings) == 1 + 7
    bier_rows = [r for r in bookings[1:] if r[4] == "Bier"]
    assert sorted(r[8] for r in bier_rows) == ["ja", "nein", "nein"]
    assert any(r[2] == "Bar (Bon-Druck)" for r in bier_rows)
    assert all(r[6] == "3,00" for r in bier_rows)
    assert all(r[1].count(".") == 2 for r in bookings[1:])  # TT.MM.JJJJ HH:MM:SS

    articles = {r[1]: r for r in sections["Verkaufte Artikel"][1:]}
    assert sections["Verkaufte Artikel"][0] == ["Warengruppe", "Artikel", "Art", "Anzahl", "Storniert", "Betrag"]
    assert articles["Bier"] == ["Getränke", "Bier", "Verkauf", "2", "1", "6,00"]
    assert articles["Aufladen 10"][2:] == ["Aufladung", "1", "0", "-10,00"]
    assert articles["Pfand Becher"][2:] == ["Pfand", "1", "0", "2,00"]
    assert articles["Pfand zurück"][2:] == ["Pfand", "1", "0", "-2,00"]
    assert articles["Auszahlen"][2:] == ["Auszahlung", "1", "0", "7,00"]
    assert [r[1] for r in sections["Verkaufte Artikel"][1:]][0] == "Bier"  # Warengruppe order

    summary = dict(sections["Gesamtstatistik"][1:])
    assert summary["Gesamtumsatz"] == "6,00"
    assert summary["Verkaufte Artikel (Stück)"] == "2"
    assert summary["davon bar über Bon-Druck"] == "3,00"
    assert summary["davon über Chips"] == "3,00"
    assert summary["Stornierte Buchungen"] == "1"
    assert summary["Stornierter Betrag"] == "3,00"
    assert summary["Aufgeladen"] == "30,00"  # 10 per Artikel + 20 per Funktion, Pfand-Rückgabe nicht
    assert summary["Ausgezahlt"] == "27,00"  # 7 per Artikel (inkl. Chip-Pfand) + 20 per Funktion
    assert summary["Pfand-Artikel (Saldo)"] == "0,00"
    assert summary["Benutzte Chips"] == "2"  # G1, G2 — BAR zählt nicht
    assert summary["Chips beim Gast (Stand jetzt)"] == "2"  # G3, G4
    assert summary["Chips mit Restguthaben (Stand jetzt)"] == "1"
    assert summary["Restguthaben auf Chips (Stand jetzt)"] == "4,50"
    assert summary["Chips im Minus (Stand jetzt)"] == "1"
    assert summary["Betrag im Minus (Stand jetzt)"] == "-1,50"
    assert summary["Chip-Pfand hinterlegt (Stand jetzt)"] == "2,00"
    assert summary["Zeitraum"].startswith("gesamtes Fest")

    # The app's Chips tab shows the same "Aufgeladen" — a negative Pfand
    # article is not money taken in.
    chip_summary = client.get("/api/customers/summary", headers=auth_headers).json()
    assert chip_summary["total_topup"] == 30.0


def test_csv_export_single_period_limits_bookings_but_not_chip_state(
    client, auth_headers, accounting_fest, tmp_path, capsys
):
    with database.get_db() as conn:
        conn.execute(
            "UPDATE stats_period SET closed_at = datetime('now', '+1 second') WHERE event_id=?", (accounting_fest,)
        )
        later = conn.execute(
            "INSERT INTO stats_period (event_id, label, started_at) VALUES (?, 'Tag 2', datetime('now', '+2 seconds'))",
            (accounting_fest,),
        ).lastrowid

    target = tmp_path / "tag2.csv"
    code, out = _cli(capsys, tmp_path, "csv-export", str(accounting_fest), str(target), "--period", str(later))
    assert code == 0, out
    assert out["rows"] == 0

    sections = _csv_sections(target)
    assert len(sections["Buchungen"]) == 1  # header only
    assert sections["Verkaufte Artikel"][1:] == []
    summary = dict(sections["Gesamtstatistik"][1:])
    assert summary["Zeitraum"].startswith("Tag 2 (")
    assert summary["Gesamtumsatz"] == "0,00"
    assert summary["Aufgeladen"] == "0,00"
    assert summary["Benutzte Chips"] == "0"
    assert "Pfand-Artikel (Saldo)" not in summary
    # Live chip state is independent of the selected range.
    assert summary["Restguthaben auf Chips (Stand jetzt)"] == "4,50"
