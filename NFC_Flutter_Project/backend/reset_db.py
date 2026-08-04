"""
NFC-Kasse — Selektiver Datenbank-Reset
Dieses Skript setzt gezielt Teile der Datenbank zurück.
WICHTIG: Backend (start_backend.bat) muss gestoppt sein!
"""

import os
import sqlite3
import sys
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kasse.db")
BACKUP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backups")


def _hr():
    print("  " + "-" * 52)


def _header():
    os.system("cls")
    print()
    print("  ====================================================")
    print("    NFC-Kasse  —  Datenbank zurücksetzen")
    print("  ====================================================")
    print()


def _check_db():
    if not os.path.exists(DB_PATH):
        print(f"  FEHLER: kasse.db nicht gefunden unter:\n  {DB_PATH}")
        print()
        print("  Starte zuerst das Backend einmal, um die DB zu erstellen.")
        sys.exit(1)


def _backup():
    """Erstellt ein Backup von kasse.db vor dem Reset."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(BACKUP_DIR, f"kasse_vor_reset_{ts}.db")
    import shutil
    shutil.copy2(DB_PATH, dest)
    return dest


def _get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=OFF")   # Deaktiviert für Bulk-Deletes
    return conn


def _confirm(warnung: str) -> bool:
    print()
    print(f"  ⚠  {warnung}")
    print()
    antwort = input("     Fortfahren? Eingabe 'ja' zum Bestätigen: ").strip().lower()
    return antwort == "ja"


def _stats(conn) -> dict:
    lb_table = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='leaderboard_score'"
    ).fetchone()
    opt_in = conn.execute("SELECT COUNT(*) FROM leaderboard_score WHERE opt_in=1").fetchone()[0] \
        if lb_table else 0
    return {
        "chips":  conn.execute("SELECT COUNT(*) FROM customer").fetchone()[0],
        "sales":  conn.execute("SELECT COUNT(*) FROM sale").fetchone()[0],
        "topups": conn.execute("SELECT COUNT(*) FROM topup").fetchone()[0],
        "opt_in": opt_in,
    }


def _print_stats(conn):
    s = _stats(conn)
    print(f"     Chips gesamt:   {s['chips']}")
    print(f"     Buchungen:      {s['sales']}")
    print(f"     Aufladungen:    {s['topups']}")
    print(f"     Leaderboard:    {s['opt_in']} Teilnehmer")


# ---------------------------------------------------------------------------
# Reset-Funktionen
# ---------------------------------------------------------------------------

def reset_chips_komplett():
    """Löscht ALLE Chips, Buchungen und Aufladungen (kompletter Neustart)."""
    _header()
    print("  Option 1 — Chips komplett zurücksetzen")
    _hr()
    print()
    print("  Alle Chip-UIDs, Guthaben, Namen, Buchungen und")
    print("  Aufladungen werden unwiderruflich gelöscht.")
    print("  (Artikel, Kategorien und Benutzer bleiben erhalten.)")
    print()
    conn = _get_db()
    _print_stats(conn)
    conn.close()

    if not _confirm("ALLE Chips und Transaktionen werden gelöscht!"):
        return

    backup = _backup()
    conn = _get_db()
    conn.execute("DELETE FROM sale")
    conn.execute("DELETE FROM topup")
    conn.execute("DELETE FROM leaderboard_score")
    conn.execute("DELETE FROM customer")
    conn.commit()
    conn.close()
    print()
    print(f"  ✓ Fertig. Backup gespeichert: {os.path.basename(backup)}")


def reset_chip_guthaben():
    """Setzt alle Chip-Guthaben auf 0,00 € (Chips bleiben registriert)."""
    _header()
    print("  Option 2 — Chip Guthaben zurücksetzen")
    _hr()
    print()
    print("  Alle Chip-Guthaben werden auf 0,00 € gesetzt.")
    print("  Chip-UIDs, Namen und Buchungshistorie bleiben erhalten.")
    print()
    conn = _get_db()
    total_balance = conn.execute("SELECT COALESCE(SUM(balance),0) FROM customer").fetchone()[0]
    chip_count    = conn.execute("SELECT COUNT(*) FROM customer WHERE balance != 0").fetchone()[0]
    conn.close()
    print(f"     Chips mit Guthaben: {chip_count}")
    print(f"     Gesamtguthaben:     {total_balance:.2f} €")

    if not _confirm(f"Alle Guthaben werden auf 0,00 € gesetzt!"):
        return

    backup = _backup()
    conn = _get_db()
    conn.execute("UPDATE customer SET balance = 0.0")
    conn.commit()
    conn.close()
    print()
    print(f"  ✓ Fertig. Backup gespeichert: {os.path.basename(backup)}")


def reset_chip_punkte():
    """Setzt alle gespeicherten Leaderboard-Punkte auf 0 (Transaktionen bleiben erhalten)."""
    _header()
    print("  Option 3 — Chip Punkte (Leaderboard) zurücksetzen")
    _hr()
    print()
    print("  Alle Punkte in der leaderboard_score Tabelle werden")
    print("  auf 0 gesetzt. Buchungshistorie und Guthaben bleiben")
    print("  unverändert. Das Leaderboard startet neu bei 0.")
    print()
    conn = _get_db()
    opt_in = conn.execute("SELECT COUNT(*) FROM leaderboard_score WHERE opt_in=1").fetchone()[0]
    total  = conn.execute("SELECT COUNT(*) FROM leaderboard_score").fetchone()[0]
    conn.close()
    print(f"     Einträge in leaderboard_score: {total}")
    print(f"     Aktive Teilnehmer:             {opt_in}")

    if not _confirm("Leaderboard-Punkte werden auf 0 zurückgesetzt!"):
        return

    backup = _backup()
    conn = _get_db()
    conn.execute("UPDATE leaderboard_score SET points = 0, updated_at = datetime('now')")
    conn.commit()
    conn.close()
    print()
    print(f"  ✓ Fertig. Backup gespeichert: {os.path.basename(backup)}")


def reset_transaktionen():
    """Löscht alle Buchungen und Aufladungen (Chips + Guthaben bleiben)."""
    _header()
    print("  Option 4 — Transaktionen zurücksetzen")
    _hr()
    print()
    print("  Alle gebuchten Artikel und Aufladungen werden gelöscht.")
    print("  Chip-UIDs, Namen und Guthaben bleiben erhalten.")
    print("  Leaderboard-Punkte werden auf 0 gesetzt.")
    print()
    conn = _get_db()
    s = _stats(conn)
    conn.close()
    print(f"     Buchungen:   {s['sales']}")
    print(f"     Aufladungen: {s['topups']}")

    if not _confirm("Alle Buchungen und Aufladungen werden gelöscht!"):
        return

    backup = _backup()
    conn = _get_db()
    conn.execute("DELETE FROM sale")
    conn.execute("DELETE FROM topup")
    conn.execute("UPDATE leaderboard_score SET points = 0, updated_at = datetime('now')")
    conn.commit()
    conn.close()
    print()
    print(f"  ✓ Fertig. Backup gespeichert: {os.path.basename(backup)}")


def reset_leaderboard_teilnahme():
    """Setzt opt_in aller Chips auf 0 (niemand nimmt teil)."""
    _header()
    print("  Option 5 — Leaderboard-Teilnahme zurücksetzen")
    _hr()
    print()
    print("  Alle Chips werden vom Leaderboard abgemeldet.")
    print("  Punkte und Buchungshistorie bleiben erhalten.")
    print()
    conn = _get_db()
    opt_in = conn.execute("SELECT COUNT(*) FROM leaderboard_score WHERE opt_in=1").fetchone()[0]
    conn.close()
    print(f"     Aktive Teilnehmer: {opt_in}")

    if not _confirm("Alle Chips werden vom Leaderboard abgemeldet!"):
        return

    backup = _backup()
    conn = _get_db()
    conn.execute("UPDATE leaderboard_score SET opt_in = 0, updated_at = datetime('now')")
    conn.commit()
    conn.close()
    print()
    print(f"  ✓ Fertig. Backup gespeichert: {os.path.basename(backup)}")


# ---------------------------------------------------------------------------
# Hauptmenü
# ---------------------------------------------------------------------------

def main():
    _check_db()

    while True:
        _header()
        conn = _get_db()
        s = _stats(conn)
        conn.close()

        print(f"  Datenbank:  {DB_PATH}")
        print()
        print(f"  Aktueller Stand:")
        print(f"    Chips:          {s['chips']}")
        print(f"    Buchungen:      {s['sales']}")
        print(f"    Aufladungen:    {s['topups']}")
        print(f"    Leaderboard:    {s['opt_in']} Teilnehmer")
        print()
        _hr()
        print()
        print("  Was soll zurückgesetzt werden?")
        print()
        print("  [1]  Chips komplett          — Alle UIDs + Buchungen löschen")
        print("  [2]  Chip Guthaben           — Alle Guthaben auf 0,00 € setzen")
        print("  [3]  Chip Punkte             — Leaderboard-Punkte auf 0 setzen")
        print("       (Buchungen bleiben, Punkte starten neu)")
        print("  [4]  Transaktionen           — Alle Buchungen + Aufladungen löschen")
        print("  [5]  Leaderboard-Teilnahme   — Alle Chips austragen")
        print()
        print("  [0]  Beenden")
        print()

        wahl = input("  Auswahl: ").strip()
        print()

        if wahl == "0":
            print("  Abgebrochen. Keine Änderungen vorgenommen.")
            print()
            break
        elif wahl == "1":
            reset_chips_komplett()
        elif wahl == "2":
            reset_chip_guthaben()
        elif wahl == "3":
            reset_chip_punkte()
        elif wahl == "4":
            reset_transaktionen()
        elif wahl == "5":
            reset_leaderboard_teilnahme()
        else:
            print("  Ungültige Eingabe.")

        print()
        input("  Enter drücken um zum Menü zurückzukehren ...")


if __name__ == "__main__":
    main()
