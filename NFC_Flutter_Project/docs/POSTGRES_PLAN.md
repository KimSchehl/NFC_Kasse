# Plan: Umstieg auf PostgreSQL (Vorbereitung Cloud-SaaS)

Stand: 19. November 2026 · Phasen 1–6 fertig (Version 1.1.0, nicht committet). Nächster großer Schritt: Cloud-Betrieb (Version 1.2.0)

## Ziel

Das Backend läuft **nur noch auf PostgreSQL**, lokal wie später in der Cloud. SQLite fällt weg.

- **Lokal:** Der Installer bringt PostgreSQL mit und richtet es als eigenen Windows-Dienst ein. Für den Veranstalter vor Ort bleibt die Bedienung gleich.
- **Cloud (später):** dieselbe Software und dasselbe Schema, mit hunderten Veranstaltern in einer Datenbank.
- **Wechsel lokal ↔ Cloud:** Ein Veranstalter kann später per Funktion umziehen, ohne dass er exportieren und importieren muss. Dafür haben alle Datensätze weltweit eindeutige IDs (UUID). Der Umzug kopiert dann einfach alle Zeilen seines Veranstalters in die andere Datenbank.
- **Später, eigenes Projekt:** ein Import-Tool, das eine alte lokale `kasse.db` (SQLite) einmalig in PostgreSQL überführt.

## Entscheidungen (Kim, 17.11.2026)

| # | Thema | Entscheidung |
| --- | --- | --- |
| 0 | Datenbank | Nur PostgreSQL, auch lokal |
| 1 | Zugriff | Treiber `psycopg` (Version 3) mit Verbindungspool, SQL bleibt handgeschrieben. **Alembic** übernimmt die Schemaänderungen und ersetzt `user_version` und `migrations.py` |
| 2 | Schema | Wird einmal definiert, als Alembic-Basis-Migration. Die Altlasten fallen weg: `migrations.py`, `main._migrate()`, `migrate.py`, `tests/legacy_init_db_v2.py`, `test_v3_migration.py` |
| 3 | Tabelle `user` | wird zu `app_user` (`user` ist in PostgreSQL ein reserviertes Wort) |
| 4 | Sperre beim Buchen | `get_db(exclusive=True)` sperrt nur den eigenen Veranstalter (`pg_advisory_xact_lock`). Buchungen eines Veranstalters laufen nacheinander wie heute, verschiedene Veranstalter laufen parallel |
| 5 | Typen | Geld `NUMERIC(10,2)`, an den Code wird es weiter als `float` gegeben. Zeit `TIMESTAMPTZ` (UTC). Wahrheitswerte bleiben `SMALLINT` 0/1. API und App bleiben gleich |
| 6 | IDs | **UUID** (Version 7, zeitlich sortierbar) als Primärschlüssel aller Tabellen, lokal und in der Cloud. App und Admin-Tool behandeln IDs als Text |
| 6b | PostgreSQL-Version | **18** (hat `uuidv7()` eingebaut), lokal im Installer und auf dem Entwicklungs-PC |
| 6c | Umzug-Vorbereitung | Jede Veranstalter-Tabelle hat `tenant_id` und `updated_at` (per Trigger). Kein Live-Abgleich, deshalb kein Lösch-Protokoll (19.11.2026) |
| 7 | Mandantentrennung | Alles in einer Datenbank, getrennt über `tenant_id`. Jede Tabelle mit Veranstalter-Daten bekommt eine eigene `tenant_id`, auch `sale`, `topup`, `print_job` usw. Das braucht man für den Umzug und für Row-Level-Security in der Cloud |

## Was sich im Code ändert (Analyse)

| Stelle | Umfang | Änderung |
| --- | --- | --- |
| `database.py` | 1 Datei | psycopg-Pool; Zeilen bleiben über `row["spalte"]` zugreifbar; Platzhalter `?` werden zentral übersetzt, damit ~300 Abfragen unverändert bleiben; `DATABASE_URL` in `config.env` |
| `datetime('now')`, `datetime(x,'localtime')`, `strftime` | ~50 Stellen | `now()` bzw. Umrechnung in Python |
| `cursor.lastrowid` | 21 Stellen | entfällt, die UUID wird in Python erzeugt und mitgegeben |
| `INSERT OR IGNORE` / `OR REPLACE` | 28 Stellen | `ON CONFLICT …` |
| `sqlite3.OperationalError` | `topup.py`, `admin_cli.py` | psycopg-Fehlerklassen |
| Tabelle `user` | ~30 Abfragen + Tests | `app_user` |
| `GROUP BY` | 3 Abfragen | PostgreSQL ist strenger, die Tests zeigen, wo es hakt |
| Integer-IDs in Python (`int(...)`, Pfad-Parameter `{id}: int`) | Router, Schemas | `UUID` |
| Flutter-App | ~12 Model-Felder + Provider, Präferenz-Schlüssel `category.color.{id}`, `category.order` | `int id` → `String id` |
| Admin-Tool | Dart-Seiten, die IDs verwenden | `String`; Sicherungsseite auf `pg_dump`/`pg_restore` |
| `db_backup.py` | ganze Datei | `pg_dump`/`pg_restore` statt Dateikopie |
| Installer | Inno Setup, WinSW | PostgreSQL-Binärdateien mitliefern, beim ersten Start `initdb`, eigener Dienst, eigener Port (z. B. 5433 statt 5432, um Konflikte zu vermeiden), Datenbank-Passwort zufällig in `config.env` |
| Tests | conftest | Statt einer Temp-SQLite-Datei bekommt jeder Test eine frische Datenbank aus einer Vorlage (`CREATE DATABASE … TEMPLATE`). Dafür muss PostgreSQL auf dem Entwicklungs-PC installiert sein |

## Phasen

| # | Phase | Ergebnis |
| --- | --- | --- |
| 1 | **Machbarkeit Installer** (zuerst, größtes Risiko) | Die Installer-EXE enthält alles: PostgreSQL-18-Binärdateien, beim Setup `initdb` in `ProgramData`, eigener Dienst (`pg_ctl register` oder WinSW), Port 5433, zufälliges Passwort in `config.env`. Dienst startet auf dem Thin Client, RAM- und Platzbedarf gemessen, Deinstallation fragt, ob die Daten bleiben |
| 2 | Altlasten raus, `user` → `app_user` | Tests grün (noch auf SQLite) |
| 3 | DB-Schicht + Alembic-Basis-Schema | `database.py` auf psycopg, alle SQLite-Funktionen ersetzt; Tests grün auf PostgreSQL |
| 4 | UUID + `tenant_id` überall | Backend und Tests auf UUID |
| 5 | App + Admin-Tool | IDs als Text, Sicherung/Wiederherstellung über `pg_dump` |
| 6 | Doku | `CLAUDE.md`, `README.md`, Bedieneranleitung (Sicherungen) |

Kim baut und testet selbst (Flutter, PyInstaller, Inno Setup). Jede Phase ist für sich committbar. Ab Phase 3 läuft das Backend nur noch mit PostgreSQL.

## Cloud-Ausblick (nicht Teil dieses Umbaus)

**Konten.** Es gibt drei Ebenen:
1. **Plattform-Admin** (Kim): verwaltet Veranstalter, Lizenzen und Abos.
2. **Veranstalter-Konto** (Inhaber): meldet sich im Web-Portal mit E-Mail und Passwort an. Zwei-Faktor-Anmeldung per Authenticator-App (TOTP) ist Pflicht, Passkeys kommen später.
3. **Kassen-Benutzer** (heutige `app_user`): Benutzername und Passwort wie heute, ohne 2FA, weil das an der Kasse unpraktisch ist. Dafür wird jedes Gerät einmal per QR-Code aus dem Portal registriert. Damit weiß das Gerät, zu welchem Veranstalter es gehört (das löst den fehlenden Veranstalter-Wähler beim Login), und ein gestohlenes Passwort allein reicht nicht.

**Web-Portal.** Zum Beispiel `cloud.nfc-kasse.de` für das Portal (das, was heute das Admin-Tool lokal macht: Feste, Benutzer, Sicherungen, Abo) und `api.nfc-kasse.de` für die Geräte. Die heutigen Admin-CLI-Befehle werden dafür zu geschützten HTTP-Endpunkten für den Inhaber.

**Datenbank.** Dasselbe Schema wie lokal, dazu Tabellen für Inhaber-Konten, Geräte-Registrierung und Abos.

**Absicherung.**
- Die Datenbank ist **nie direkt aus dem Internet erreichbar**. Nur das Backend spricht mit ihr, im privaten Netz des Anbieters. Port 5432 bleibt nach außen zu.
- HTTPS überall (Reverse-Proxy, Let's Encrypt).
- Das Backend nutzt einen Datenbank-Benutzer mit minimalen Rechten. Row-Level-Security ist das zweite Netz: Selbst ein vergessener `tenant_id`-Filter liefert keine fremden Daten.
- Login-Sperre nach Fehlversuchen und Rate-Limits auf der API.
- Geheimnisse liegen in einem Secret-Store, nicht im Code. Updates kommen regelmäßig, Logs werden überwacht.
- Sicherungen sind verschlüsselt und liegen getrennt vom Server.
- DSGVO: Hosting in Deutschland oder der EU, mit Auftragsverarbeitungsvertrag beim Anbieter.

**Ausfallsicherheit.**
- PostgreSQL läuft mit einem Primärserver und zwei Standby-Servern in drei Rechenzentren (Zonen). Mindestens ein Standby wird *synchron* beschrieben, damit bei einem Ausfall keine Buchung verloren geht.
- Fällt der Primärserver aus, übernimmt ein Standby automatisch. Das dauert etwa 10 bis 30 Sekunden, nicht null. Die App wiederholt Anfragen in dieser Zeit.
- Gleichzeitiges Schreiben an drei Standorten (Multi-Master) ist bei Guthaben nicht sinnvoll, weil Konflikte Geld kosten.
- Zusätzlich gibt es Sicherungen mit Wiederherstellung auf jeden Zeitpunkt (PITR). Replikation kopiert auch Fehler, Sicherungen nicht.
- Empfehlung: ein **verwaltetes PostgreSQL mit HA-Option** bei einem deutschen oder EU-Anbieter, statt das selbst mit Patroni zu betreiben. Der Backend-Server läuft ebenfalls mehrfach hinter einem Load-Balancer.
- **Größtes reales Risiko ist das Internet am Festplatz**, nicht das Rechenzentrum. Eine reine Cloud-Kasse steht still, wenn das Netz weg ist. Wer davon abhängig ist, nimmt den Lokal-Betrieb.

**Betriebsarten (frei wählbar beim Kauf oder bei der Miete).**

| Art | Wo laufen die Tablets hin | Ohne Internet |
| --- | --- | --- |
| Lokal | lokaler Server (Laptop) im Fest-WLAN, wie heute | läuft |
| Cloud | direkt `api.nfc-kasse.de`, kein Server vor Ort | steht still |

**Wechsel zwischen lokal und Cloud (Entscheidung Kim, 19.11.2026): nur vor oder nach einem Fest, kein Live-Abgleich.**
- Ein Veranstalter zieht mit seinen kompletten Daten um, während bei ihm „Intern“ läuft (kein Fest). Der Umzug kopiert alle Zeilen mit seiner `tenant_id` von der einen in die andere Datenbank. Wegen der UUIDs gibt es dabei keine ID-Kollisionen.
- Während eines Fests gibt es genau eine Datenbank für diesen Veranstalter. Es gibt keinen Konflikt um Guthaben, weil nirgends parallel gebucht wird.
- Danach ist die Quelle für diesen Veranstalter gesperrt oder gelöscht, damit nicht versehentlich an zwei Orten weitergearbeitet wird.
- Den „Hybrid-Betrieb“ mit Sync-Dienst aus dem ersten Entwurf gibt es nicht. Das Lösch-Protokoll `sync_tombstone` ist deshalb wieder entfernt, `tenant_id` und `updated_at` bleiben (Umzug, Row-Level-Security).

**Infrastruktur für den Start: 1 Hetzner-Server + 2 Proxmox-Server.**
- Die drei Server sind per **WireGuard-VPN** verbunden. Die Datenbank lauscht nur im VPN.
- **Hetzner ist der Primärserver** (feste IP, gutes Netz). Darauf laufen API, Portal und PostgreSQL. Reverse-Proxy mit HTTPS (Caddy oder nginx).
- **Beide Proxmox-Server sind Standbys** mit Streaming-Replikation. Am Anfang sind sie **asynchron**: Synchron über eine Heim- oder Büroleitung würde jede Buchung um die Leitungslaufzeit bremsen, und bei Leitungsausfall würden Schreibzugriffe hängen. Lokal-Kunden sind vom Cloud-Server ohnehin unabhängig.
- **Sicherungen** mit pgBackRest (Wiederherstellung auf jeden Zeitpunkt) auf einen Proxmox-Server und zusätzlich auf eine Hetzner Storage Box.
- **Übernahme bei Ausfall** zunächst per Hand nach Checkliste (Standby hochstufen, DNS umstellen). Automatisch mit Patroni und etcd über alle drei Server erst, wenn zahlende Cloud-Kunden da sind. Voraussetzung dafür ist, dass die Proxmox-Standorte eine feste IP oder einen Tunnel haben, damit die API dort erreichbar ist.

## Risiken

- **PostgreSQL auf dem Thin Client:** RAM, Platz, Portkonflikte, Virenscanner, Updates der PostgreSQL-Hauptversion. Deshalb ist das Phase 1.
- **UUID-Umstellung** betrifft App, Admin-Tool und gespeicherte Präferenzen. Weil es keine Installationen gibt, ist jetzt der günstigste Zeitpunkt.
- **Zeitformat:** Storno-Fenster und Artikel-Sync hängen am Format der Zeitstempel. Die bestehenden Tests sichern das ab.

## Fortschritt

| Phase | Status | Notiz |
| --- | --- | --- |
| 2 | fertig (18.11.2026, nicht committet) | `migrations.py`, `migrate.py`, `main._migrate()`, v2-Legacy-Tests entfernt; Start legt nur noch die BAR-Chips an (frisches Schema nachweislich unverändert). Tabelle `user` → `app_user` (54 Stellen in Backend, Lösch-Tool, Tests). `SCHEMA_VERSION` 4, ältere Sicherungen/Datenbanken werden abgelehnt. 161 Tests grün (SQLite) |
| 3 | fertig (18.11.2026, nicht committet) | `database.py` auf psycopg-3-Pool (`DATABASE_URL`, Verbindungsprüfung beim Ausleihen), alte Schnittstelle bleibt (`?`, `row["x"]`, `lastrowid` über `lastval()`). Sperre: `pg_advisory_xact_lock` pro Veranstalter bzw. global für Admin-Befehle. Schema als Alembic-Revision `0001_baseline` (NUMERIC, TIMESTAMPTZ, SMALLINT-Flags); ungenutzte Tabellen `leaderboard_score`, `user_setting` entfallen. `init_db.setup()` migriert und füllt, läuft bei jedem Dienststart. Sicherungen über `pg_dump`/`pg_restore` (`*.dump`, Admin-Tool angepasst), Lösch- und Reset-Tool umgestellt, PyInstaller-Spec bündelt `alembic/`. Tests laufen gegen PostgreSQL (Vorlage-DB pro Lauf, Kopie pro Test): 161 grün |
| 1 | fertig, auf Kims Laptop getestet (19.11.2026, nicht committet): mitinstalliert (Dienst auf 5433, ~37 MB privater RAM, 144 MB Programme) und vorhandener Server (Admin legt selbst an) laufen | Installer bringt PostgreSQL 18 mit (`build_installer.bat` lädt die EDB-Binärdateien, nur bin/lib/share). Neue Setup-Seiten: Datenbank (mitinstallieren / vorhandener Server, Setup legt an / vorhandener Server, IT-Admin legt Benutzer + DB selbst an und bekommt die SQL-Befehle angezeigt, Modus `prepared`), Datenbank-Administrator (Root-Benutzer + Passwort, wiederholen, anzeigen) bzw. Zugang zum vorhandenen Server, Kassensystem-Benutzer. `NfcKasseBackend.exe db-setup` (`pg_setup.py`): initdb (UTF-8, deutsche ICU-Sortierung, Port 5433, nur localhost), Dienst `NfcKassePostgres`, Rolle + DB `nfc_kasse`, `DATABASE_URL`/`PG_BIN` in config.env, Schema. Update stoppt/startet den DB-Dienst, Deinstallation entfernt ihn, `pgdata` nur auf Wunsch. Dienst wartet beim Start bis 2 min auf die DB. Getestet: db-setup gegen Wegwerf-Server, Installer-Skript kompiliert (mit Platzhalter-Dateien), 163 Tests grün |
| 4+5 | fertig (19.11.2026, nicht committet) | Baseline: alle Schlüssel UUID (`uuidv7()`), `tenant_id` in allen Veranstalter-Tabellen (Trigger füllt sie aus der Elternzeile), `updated_at` per Trigger. Backend: IDs als Text, ungültige ID → 404, Sperre per Hash der Veranstalter-UUID. Setup lehnt eine vorhandene `nfc_kasse`-DB mit fremden Tabellen ab. App und Admin-Tool: IDs als `String` (Analyzer sauber). Tests: Backend 165 grün; App grün bis auf 7 alte Preisformat-Tests (unverändert, schlagen schon vorher fehl) |
| 6 | fertig | Doku (CLAUDE.md, Plan), Version 1.1.0 |
