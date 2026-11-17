# Plan: PostgreSQL-Unterstützung (Vorbereitung Cloud-SaaS)

Stand: 17. November 2026 · Vorschlag, noch nichts umgesetzt

## Ziel

Das Backend läuft auf **beiden** Datenbanken mit demselben Code:

- **SQLite** bleibt für die lokale Windows-Installation (Installer, Dienst, Sicherungen, Verwaltungstool). Für Veranstalter vor Ort ändert sich nichts.
- **PostgreSQL** kommt dazu, für den späteren Cloud-Betrieb mit hunderten Veranstaltern in einer Datenbank.

Welche Datenbank genutzt wird, entscheidet eine Einstellung in `config.env`, z. B. `DATABASE_URL=postgresql://…`. Ohne sie bleibt alles beim heutigen `kasse.db`.

Nicht Teil dieses Plans: Cloud-Login mit Veranstalter-Auswahl, Hosting, Abrechnung, Hybrid-Login in der App (siehe `ROADMAP.md`).

## Ausgangslage (Analyse)

Das Backend benutzt `sqlite3` direkt mit handgeschriebenem SQL, ohne ORM. Alle Zugriffe laufen über `database.get_db()` (rund 100 Aufrufe, 21 davon mit `exclusive=True`). Die Mandantentrennung über `tenant_id` aus dem Token ist bereits gebaut.

Was heute nur auf SQLite läuft:

| Stelle | Umfang | Lösung |
| --- | --- | --- |
| Platzhalter `?` | ~300 Abfragen | bleiben, die DB-Schicht übersetzt sie für PostgreSQL |
| `datetime('now')` in SQL und als Spalten-Default | ~45 Stellen | Zeit kommt aus Python als Parameter (UTC); Defaults im Schema dialektneutral |
| `datetime(x,'localtime')`, `strftime('%s', …)` | 4 Stellen (`event_lifecycle.py`) | in Python rechnen |
| `cursor.lastrowid` | 21 Stellen | `INSERT … RETURNING id` (SQLite 3.50 kann das auch) |
| `INSERT OR IGNORE` / `INSERT OR REPLACE` | 28 Stellen | `ON CONFLICT … DO NOTHING / DO UPDATE` (beide DBs) |
| `BEGIN EXCLUSIVE` | `get_db(exclusive=True)` | siehe Entscheidung 4 |
| `PRAGMA`, `sqlite_master`, `AUTOINCREMENT` | Schema, Migrationen, Backup | nur noch im SQLite-Zweig bzw. im Schema-Modul |
| Tabelle `user` | ~30 Abfragen + Tests | `user` ist in PostgreSQL ein reserviertes Wort, siehe Entscheidung 3 |
| `except sqlite3.OperationalError` | `topup.py`, `admin_cli.py` | allgemeine Fehlerklasse der DB-Schicht |
| `GROUP BY` | 3 Abfragen (`stats.py`, `leaderboard.py`) | PostgreSQL ist strenger; die Testsuite auf PostgreSQL findet das |
| Geld als `REAL`, Zeit als `TEXT`, Wahrheitswerte als `INTEGER` | ganzes Schema | siehe Entscheidung 5 |

Altlasten, die weg können, weil es keine älteren Installationen gibt: `migrations.py` (v2 → v3), `main._migrate()` (`ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` beim Start), `migrate.py`, `tests/legacy_init_db_v2.py`, `test_v3_migration.py`. Das spart einen zweiten Schema-Weg, der sonst für beide Datenbanken gepflegt werden müsste.

SQLite-only bleiben dürfen: `db_backup.py` (Dateisicherung), Wiederherstellung und die Sicherungsseite im Verwaltungstool. In der Cloud sichert der PostgreSQL-Anbieter bzw. `pg_dump`.

## Entscheidungen für Kim

### 1. Datenbank-Schicht

- **A (Empfehlung): SQLAlchemy Core + Alembic, SQL bleibt handgeschrieben.** `get_db()` liefert weiter ein Objekt mit `execute()`/`fetchone()`/Zeilen mit `row["spalte"]`, darunter steckt eine SQLAlchemy-Engine (Verbindungspool für die Cloud, Dialekte, ausgereifter PostgreSQL-Treiber psycopg 3). Die Router ändern sich kaum.
- B: eigener dünner Adapter direkt auf `sqlite3` / `psycopg`. Weniger Abhängigkeiten, aber Pool, Migrationen und Dialektunterschiede baut man selbst nach.
- C: ORM-Umbau aller Router. Sauber, aber faktisch ein Neuschreiben von 10 000 Zeilen Backend. Nicht empfohlen.

### 2. Schema und Migrationen

- **Empfehlung:** Das Schema wird **einmal** als SQLAlchemy-`Table`-Definitionen beschrieben (neues Modul `schema.py`, ersetzt die `CREATE TABLE`-Texte in `init_db.py`). Daraus entstehen beide Datenbanken. Künftige Änderungen laufen über **Alembic**-Migrationen (für SQLite im „batch mode“). Startpunkt ist eine Basis-Migration „v4“, alle Altlasten oben fallen weg.
- `init_db.py` bleibt der Einstieg (legt Schema an, füllt Rechte-Baum, Admin, Intern-Fest, BAR-Chip), aber ohne eigenes DDL.
- `CLAUDE.md` wird angepasst: Schema-Quelle ist dann `schema.py` + `alembic/versions/`.

### 3. Tabelle `user`

- **Empfehlung: umbenennen in `app_user`.** Einmal suchen-und-ersetzen in Backend und Tests, danach nie wieder Anführungszeichen-Fallen.
- Alternative: überall `"user"` in Anführungszeichen schreiben. Funktioniert in beiden DBs, wird aber bei jeder neuen Abfrage vergessen.

### 4. Sperren bei Buchungen (heute `BEGIN EXCLUSIVE`)

`BEGIN EXCLUSIVE` sperrt die ganze Datenbank. In der Cloud würde ein Bezahlvorgang bei Veranstalter A die Kassen aller anderen Veranstalter blockieren.

- **Empfehlung:** `get_db(exclusive=True)` bleibt als Aufruf gleich. Auf SQLite weiter `BEGIN EXCLUSIVE` (lokal ist das richtig und bewährt). Auf PostgreSQL sperrt es nur den eigenen Veranstalter (`pg_advisory_xact_lock(tenant_id)`): alle Buchungen eines Veranstalters laufen nacheinander wie heute, verschiedene Veranstalter parallel. Dafür bekommt `get_db` die `tenant_id` mitgegeben.
- Später möglich, wenn ein einzelner großer Veranstalter zu viele gleichzeitige Buchungen hat: Zeilensperren (`SELECT … FOR UPDATE` auf Chip und Lagerbestand). Das ist feiner, aber jede Buchungsstelle muss einzeln geprüft werden. Nicht jetzt.

### 5. Datentypen

- **Geld:** heute `REAL` (Euro als Kommazahl). **Empfehlung:** in PostgreSQL `NUMERIC(10,2)`, die DB-Schicht gibt weiter `float` an den Code zurück, API und App bleiben gleich. Ein Umstieg auf ganze Cent wäre die sauberste Lösung, betrifft aber auch App und Admin-Tool und ist ein eigenes Thema.
- **Zeit:** heute `TEXT` mit UTC. **Empfehlung:** PostgreSQL `TIMESTAMPTZ`, SQLite bleibt Text. Die DB-Schicht liefert in beiden Fällen dasselbe Format (`"YYYY-MM-DD HH:MM:SS"`, UTC), damit Storno-Zeitfenster, Artikel-Sync und CSV-Export unverändert funktionieren.
- **Wahrheitswerte:** **Empfehlung:** bleiben `INTEGER` 0/1 (in PostgreSQL `SMALLINT`). `BOOLEAN` würde jede Abfrage mit `= 1` brechen und bringt keinen Nutzen.

### 6. Mandantentrennung in PostgreSQL

- **Empfehlung (jetzt):** eine Datenbank, ein Schema, Trennung über `tenant_id` wie bereits gebaut. Die Tests prüfen weiter, dass Veranstalter sich nicht sehen.
- **Später (Cloud-Phase):** PostgreSQL Row-Level-Security als zweites Sicherheitsnetz (`SET app.tenant_id` pro Anfrage, Richtlinie pro Tabelle). Dafür bräuchten Tabellen ohne eigene `tenant_id` (z. B. `sale`, `topup`, `print_job`, die über `event_id` dranhängen) eine eigene Spalte. Nicht jetzt, aber das Schema wird so angelegt, dass es nachrüstbar ist.
- Schema- oder Datenbank-pro-Veranstalter: bei hunderten Veranstaltern nicht sinnvoll (Migrationen hundertfach).

### 7. Tests

- **Empfehlung:** dieselbe pytest-Suite läuft gegen beide Datenbanken. Standard bleibt SQLite (schnell, ohne Installation). Mit `TEST_DATABASE_URL=postgresql://…` laufen die Tests gegen PostgreSQL. Auf diesem PC ist weder PostgreSQL noch Docker installiert. Kim müsste eins davon einrichten (PostgreSQL 16 für Windows reicht), sonst kann ich die PostgreSQL-Seite nicht prüfen.

## Phasen

| # | Phase | Ergebnis |
| --- | --- | --- |
| 1 | Altlasten entfernen | `migrations.py`, `main._migrate()`, `migrate.py`, Legacy-Tests weg; `user` → `app_user`; Tests grün auf SQLite |
| 2 | Dialektneutrales SQL | `datetime('now')`, `lastrowid`, `INSERT OR …`, `localtime`/`strftime` ersetzt; Tests grün auf SQLite. Danach läuft nichts mehr nur auf SQLite außer Schema, Backup und Sperre |
| 3 | DB-Schicht | `database.py` auf SQLAlchemy-Engine, `DATABASE_URL`, Sperre je Dialekt, eine Fehlerklasse statt `sqlite3.OperationalError`; Tests grün auf SQLite |
| 4 | Schema + Alembic | `schema.py`, Basis-Migration, `init_db.py` ohne DDL; Installer/PyInstaller bekommen Alembic + Migrationsdateien mit |
| 5 | PostgreSQL-Lauf | Tests gegen PostgreSQL, Abweichungen (GROUP BY, Typen) beheben; `CLAUDE.md`/`README.md` aktualisieren |

Jede Phase hält die lokale Installation lauffähig und ist für sich committbar. Phase 1 und 2 sind auch ohne PostgreSQL nützlich und risikoarm.

## Risiken

- **Installer:** SQLAlchemy, Alembic und psycopg landen im PyInstaller-Paket (einige MB mehr). psycopg wird lokal nicht gebraucht und kann im lokalen Paket fehlen.
- **Zeitformat:** Wenn die DB-Schicht Zeiten nicht exakt wie heute formatiert, brechen Storno-Fenster und Artikel-Sync still. Dafür gibt es Tests, die bleiben Pflicht.
- **`GROUP BY`/Typen in PostgreSQL** zeigen sich erst im PostgreSQL-Testlauf (Phase 5).

## Fortschritt

| Phase | Status | Notiz |
| --- | --- | --- |
| 1–5 | offen | wartet auf Kims Entscheidungen |
