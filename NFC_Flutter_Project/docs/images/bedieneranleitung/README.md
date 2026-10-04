# Bilder für die Bedieneranleitung

Alle Bilder für die Bedieneranleitung an einem Ort, damit sie in Anleitung,
Website und Schulungsunterlagen wiederverwendet werden können.

```
bedieneranleitung/
├── app/                 Screenshots der Kassen-App (Weboberfläche, automatisch erzeugt)
│   ├── handy/           412 × 915 px Ansicht, 2-fache Auflösung
│   ├── tablet/          1280 × 800 px Ansicht, 1,5-fache Auflösung
│   └── pc/              1920 × 1080 px
│   └── dialoge/         Einzelne Dialoge, ausgeschnitten (Artikel anlegen, Optionen, Punkte, Pager)
├── zusatz/              Zusatzfunktionen mit Lizenz
│   ├── pager/           Pager-Spalte, Pager zuweisen, Fertig melden
│   └── leaderboard/     Kiosk-Teilnahme, Bestenliste auf dem Fernseher
├── browser/             Browser-Einstellungen (Flags, Richtlinien, Bluetooth-Dialog)
├── windows/             Verwaltungstool (von Kim), Setup und Dienste (noch zu liefern)
├── luci/                Router-Oberfläche LuCI (GL.iNet), noch zu liefern
├── android/             Android-Systemdialoge (von Kim zu liefern)
├── hardware/            Fotos von Leser, Chips, Drucker, Aufbau (von Kim zu liefern)
└── _werkzeuge/          Skripte, mit denen die App-Screenshots erzeugt wurden
```

Dateinamen sind in allen drei Gerätegrößen gleich, z. B. `app/handy/03_warenkorb_mit_chip.png`
und `app/tablet/03_warenkorb_mit_chip.png`.

## App-Screenshots (vorhanden)

Testdaten: Veranstaltung „Sommerfest 2026“, Chip-Pfand 3 €, Kategorien Bonkasse, Bar, Essen.
Server-Adresse in den Bildern: `http://nfc-kasse.lan:8000`.

| Datei | Zeigt | Abschnitt der Anleitung |
| --- | --- | --- |
| `01_anmeldung` | Anmeldeseite mit Server-URL | Erster Start: Anmelden |
| `02_kasse_leer` | Kassenansicht ohne Chip und Warenkorb | Täglicher Betrieb |
| `02b_menue_handy` | Geöffnetes Menü (nur Handy) | Täglicher Betrieb |
| `03_warenkorb_mit_chip` | Gefüllter Warenkorb, Chip gescannt, Rest Guthaben | Verkaufen |
| `04_aufladen_neuer_chip_pfand` | Neuer Chip: Aufladen 20 € mit Zeile „Chip Pfand“ | Neuer Chip und Chip-Pfand, Aufladen |
| `05_buchung_bestaetigt` | Grüne Meldung „Buchung bestätigt“ | Verkaufen |
| `06_storno_dialog` | Dialog „Buchung stornieren?“ | Letzte Buchung stornieren |
| `07_auszahlung` | Auszahlungs-Artikel mit Pfand-Rückgabe und Auszahlungsbetrag | Guthaben auszahlen |
| `08_optionen_auswahl` | Auswahl einer Option („Currywurst mit Pommes“) | Verkaufen, Artikel anlegen |
| `09_guthaben_reicht_nicht` | Rest Guthaben rot, Buchen grau | Verkaufen, Fehlerbehebung |
| `10_bearbeitungsmodus` | Kacheln im Bearbeitungsmodus | Ansicht anpassen |
| `10_bearbeitungsmodus_menue` | Menü mit aktivem Bearbeitungsmodus (nur Handy) | Ansicht anpassen |
| `11_neue_kategorie` | Dialog „Neue Kategorie“ | Kategorien anlegen |
| `12_hilfe_anfordern` | Dialog „Hilfe anfordern“ | Hilfe anfordern |
| `13_artikelverwaltung` | Artikelverwaltung mit allen Kategorien | Artikel anlegen |
| `14_artikel_neu_dialog` | Dialog „Neuer Artikel“ mit allen Feldern | Artikel anlegen |
| `15_benutzerliste` | Benutzerverwaltung | Mitarbeiter-Konten anlegen |
| `16_benutzer_bearbeiten` | Benutzer bearbeiten, globale Berechtigungen | Mitarbeiter-Konten anlegen |
| `16b_benutzer_bearbeiten_kategorien` | Benutzer bearbeiten, weiter unten gescrollt | Mitarbeiter-Konten anlegen |
| `17_statistik_uebersicht` | Statistik: Umsatz gesamt und je Kategorie | Statistik |
| `18_statistik_transaktionen` | Statistik: Transaktionsliste | Statistik |
| `19_statistik_chips` | Statistik: Chips mit Guthaben | Statistik |
| `20_tagesabschluss_dialog` | Dialog „Tagesabschluss“ | Statistik und Tagesabschluss |
| `21_neues_event_dialog` | Warnung „Neues Event starten“ | Statistik und Tagesabschluss |
| `22_einstellungen_ueber` | Einstellungen → Über, mit QR-Code zum App-Download | Android-App installieren |
| `23_einstellungen_design` | Einstellungen → Design | Ansicht anpassen |
| `24_einstellungen_nfc_lesegeraet` | Einstellungen → NFC-Lesegerät, noch kein Leser gekoppelt | Bluetooth-NFC-Leser koppeln |
| `25_einstellungen_protokoll` | Einstellungen → Protokoll | Protokolle |
| `26_protokolle` | Protokolle-Ansicht | Protokolle |
| `27_konto` | Kontoseite mit Abmelden | Schichtende |
| `28_kiosk_start` | Kiosk wartet auf Chip | Zusatzfunktionen: Kiosk |
| `28b_kiosk_guthaben` | Kiosk zeigt Guthaben und Buchungen | Zusatzfunktionen: Kiosk |
| `29_kundenanzeige_auswahl` | Kundenanzeige: Auswahl der Kasse (nur Tablet-Ordner) | Zusatzfunktionen |
| `30_kundenanzeige` | Kundenanzeige einer Kasse (nur Tablet-Ordner) | Zusatzfunktionen |
| `31_app_download` | Download-Seite für die Android-App (nur Tablet-Ordner) | Android-App installieren |
| `32_bondruck_warenkorb` | Warenkorb ohne Chip, Knopf „Drucken“ (nur Tablet-Ordner) | Bons an der Kasse drucken |
| `33_bons_gedruckt` | Meldung „3 Bons gedruckt“ (nur Tablet-Ordner) | Bons an der Kasse drucken |

## Dialoge und Zusatzfunktionen (vorhanden)

Aus der PC-Ansicht ausgeschnitten, damit sie in schmalen Spalten lesbar bleiben.
Testdaten mit Pager- und Leaderboard-Lizenz.

| Datei | Zeigt | Verwendet in |
| --- | --- | --- |
| `app/dialoge/artikel_neu.png` | Dialog „Neuer Artikel“, leer | Bedieneranleitung: Artikel anlegen |
| `app/dialoge/artikel_mit_optionen.png` | Artikel mit Optionen („mit Pommes“ usw.) | Bedieneranleitung: Artikel mit Optionen |
| `app/dialoge/artikel_leaderboard_punkte.png` | Feld „Leaderboard-Punkte“ | Zusatzanleitung: Leaderboard |
| `app/dialoge/artikel_pager_erforderlich.png` | Haken „Pager erforderlich“ | Zusatzanleitung: Pager |
| `zusatz/pager/01_kasse_mit_pagerliste.png` | Kasse mit Pager-Spalte | Zusatzanleitung: Pager |
| `zusatz/pager/02_pager_zuweisen.png` | Dialog „Pager zuweisen“ | Zusatzanleitung: Pager |
| `zusatz/pager/03_pagerliste_neuer_eintrag.png` | Pagerliste mit neuem Eintrag | Zusatzanleitung: Pager |
| `zusatz/pager/04_pager_fertig_bestaetigen.png` | Knopf „Wirklich fertig?“ | Zusatzanleitung: Pager |
| `zusatz/leaderboard/01_kiosk_name_und_teilnahme.png` | Kiosk, Chip-Einstellungen mit Name und Teilnahme | Zusatzanleitung: Leaderboard |
| `zusatz/leaderboard/02_bestenliste_tv.png` | Bestenliste `/leaderboard` | Zusatzanleitung: Leaderboard |
| `zusatz/netzwerk_uebersicht.png` (+ `.svg`) | Netzwerkplan: Router, Server-Laptop, Kassen, Drucker, Leser | Admin-Handbuch: Überblick |

## Verwaltungstool (von Kim geliefert, 2026-10-04)

| Datei | Zeigt |
| --- | --- |
| `windows/05_verwaltung_dashboard.png` | Dashboard, Dienst „Läuft“ |
| `windows/06_verwaltung_konfiguration.png` | Konfiguration oben: Netzwerk, Veranstaltung, Zusatz-Features |
| `windows/06b_verwaltung_konfiguration_lizenzen_web_drucker.png` | Konfiguration Mitte: Lizenzschlüssel, Web-Zugriff, Bondrucker |
| `windows/06c_verwaltung_konfiguration_bondrucker_inhalt.png` | Konfiguration unten: Bondrucker, Bon-Inhalt |
| `windows/07_verwaltung_bon_layout.png` | Seite Bon-Layout |
| `windows/07b_verwaltung_info.png` | Seite Info mit Installations-ID |

`browser/chrome_flags_unsichere_herkunft_EN.png` zeigt die Chrome-Einstellung
„Insecure origins treated as secure“, ausgefüllt und aktiviert. Sie stammt aus einem
englischen Chromium und ist ein Platzhalter, bis ein deutscher Screenshot vorliegt.

## Noch zu liefern (nur am echten Gerät möglich)

Bitte unter genau diesen Namen ablegen, dann passen die Verweise in der Anleitung.

| Datei | Was aufnehmen |
| --- | --- |
| `windows/01_smartscreen_warnung.png` | SmartScreen-Meldung beim Start von `NFC-Kasse-Setup.exe`, nach Klick auf „Weitere Informationen“ |
| `windows/02_setup_installationsmodus.png` | Setup-Seite „Installationsmodus“ |
| `windows/03_setup_fertig.png` | Letzte Setup-Seite mit Haken „NFC-Kasse jetzt öffnen“ |
| `windows/04_startmenue.png` | Startmenü-Ordner „NFC-Kasse“ mit allen Verknüpfungen |
| `windows/08_datenordner.png` | Explorer in `C:\ProgramData\NFC-Kasse\` |
| `windows/09_dienste.png` | `services.msc` mit Dienst „NFC-Kasse Backend“ (optional) |
| `windows/10_bluetooth_einstellungen.png` | Windows-Einstellungen → Bluetooth und Geräte |
| `browser/01_chrome_flags_de.png` | Wie der englische Platzhalter, aus deutschem Chrome |
| `browser/02_edge_flags.png` | Dasselbe in Edge (`edge://flags`) |
| `browser/03_edge_policy.png` | `edge://policy` mit „OverrideSecurityRestrictionsOnInsecureOrigin“ |
| `browser/04_bluetooth_auswahlfenster.png` | Browser-Dialog „… möchte sich koppeln“ mit dem NFC-Leser |
| `android/01_unbekannte_quellen.png` | Android-Abfrage „Installation aus unbekannten Quellen“ |
| `android/02_geraete_in_der_naehe.png` | Berechtigungsabfrage „Geräte in der Nähe“ |
| `android/03_nfc_einstellungen.png` | Android-Einstellung NFC ein |
| `android/04_app_leser_verbunden.png` | App, Einstellungen → NFC-Lesegerät mit „Verbunden · Akku …%“ |
| `android/05_app_kasse_nativ.png` | App auf dem Tablet in der Kassenansicht (mit NFC- bzw. Bluetooth-Symbol im Chip-Feld) |
| `luci/01_interfaces_lan.png` | LuCI, Network → Interfaces → lan → Edit, Reiter General Settings mit 192.168.1.1 |
| `luci/02_static_leases.png` | LuCI, Network → DHCP and DNS → Static Leases mit dem Eintrag nfc-kasse / 192.168.1.2 |
| `luci/03_hostnames.png` | LuCI, Network → DHCP and DNS → Hostnames mit nfc-kasse.lan / 192.168.1.2 |
| `hardware/01_nfc_leser.jpg` | Foto des Bluetooth-NFC-Lesers |
| `hardware/01b_nfc_leser_schalter_usbc.jpg` | Foto: Schiebeschalter und USB-C-Buchse des Lesers, Name auf der Rückseite |
| `hardware/02_chip_an_leser.jpg` | Foto: Armband wird an den Leser gehalten |
| `hardware/03_bondrucker.jpg` | Foto des Bondruckers |
| `hardware/04_bon_beispiel.jpg` | Foto eines gedruckten Bons |
| `hardware/05_aufbau.jpg` | Foto des Aufbaus: Server-PC, Access Point, Tablets |

## App-Screenshots neu erzeugen

Nach Änderungen an der Oberfläche lassen sich alle App-Bilder neu erzeugen. Benötigt
Python 3, die Pakete aus `backend/requirements.txt`, `playwright` und Chromium.

```bash
cd NFC_Flutter_Project/backend
export DB_PATH=/tmp/shots/kasse.db NFC_KASSE_LOG_DIR=/tmp/shots/logs
python init_db.py
EVENT_NAME="Sommerfest 2026" CHIP_DEPOSIT=3.00 python -m uvicorn main:app --port 8000 &
python ../docs/images/bedieneranleitung/_werkzeuge/seed.py      # Testdaten anlegen
cd ../docs/images/bedieneranleitung/_werkzeuge
for d in handy tablet pc; do python capture.py /tmp/shots $d; done   # Bilder nach /tmp/shots/out/<gerät>
```

Für die Bilder unter `app/dialoge/` und `zusatz/` müssen Pager und Leaderboard
freigeschaltet sein (`PAGER=true`, `LEADERBOARD=true` und gültige Lizenzschlüssel
für die `INSTALLATION_ID` des Testservers). Dann zusätzlich:

```bash
python ../docs/images/bedieneranleitung/_werkzeuge/seed_zusatz.py   # Punkte, Pager, Namen, Testbuchungen
cd ../docs/images/bedieneranleitung/_werkzeuge
python capture_dialoge.py /tmp/shots    # Artikel-Dialoge, ausgeschnitten
python capture_zusatz.py /tmp/shots     # Pager, Kiosk, Bestenliste
```

Die Rohbilder landen in `/tmp/shots/out/features/` und werden unter den Namen aus den
Tabellen oben abgelegt.

Die Bilder 32 und 33 zum Bondruck brauchen ein Konto mit dem Recht „Bon drucken“
(der Admin hat es) und funktionieren auch ohne angeschlossenen Drucker, weil die Bons
nur in die Warteschlange gelegt werden:

```bash
python capture_bondruck.py /tmp/shots/out/tablet
```

Die Skripte erwarten Chromium unter `/opt/pw-browsers/chromium-1194/` (Pfad in `lib.py`
anpassen) und lösen `nfc-kasse.lan` auf `127.0.0.1` auf.
