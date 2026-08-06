# Umfassendes Logging-System (Client + Server)

## Context

Die BLE-Reader-Web-Integration hat gezeigt, wie schmerzhaft Debugging ohne
brauchbare Logs ist (minifizierte Stacktraces, Rätselraten über mehrere
Rebuild-Zyklen). Der Nutzer will das grundsätzlich lösen: granular
konfigurierbares Logging auf allen Clients (Android-App, Web-App, perspektivisch
iOS/Desktop) und auf dem Server, mit stündlicher Rotation, automatischem Versand
der Client-Logs an den Server, und einer sauber einsehbaren, filterbaren
Log-Ansicht — als Grundlage, um künftige Features leichter debuggen zu können.

**Wichtiger Fund aus der Recherche:** Der Server hat bereits einen funktionierenden
stündlichen Rotations-Mechanismus (`backend/main.py`, `_TopOfHourHandler`,
7 Tage/168 Dateien Aufbewahrung) — aber **kein einziger Router ruft bisher
`logger.*()` auf**, und der Root-Logger hat nirgends ein explizites Level gesetzt
(fällt auf `WARNING` zurück — jeder `logger.info()`-Aufruf würde sonst still
verschluckt). Die Flutter-App ist komplett unberührt (kein Logging-Package,
kein globaler Error-Handler). Alle Architekturentscheidungen unten sind mit dem
Nutzer über mehrere Fragerunden abgestimmt.

**Bewusst außerhalb dieses Plans** (explizit vom Nutzer aufgeschoben bzw. als
Non-Goal benannt):
- Das Help/Notfall-WebSocket-System (`backend/routers/help.py`) — hat eine
  eigene, bekannte Zuverlässigkeitslücke (Connection-Registry nur nach
  `user_id`, nicht Gerät, kein Reconnect/Delivery-Ack; die wiederkehrenden
  `ConnectionClosedError: keepalive ping timeout` in den aktuellen Logs
  bestätigen das). Wird **nicht** angefasst — Remote-Log-Level läuft stattdessen
  über den bestehenden 10s-`/health`-Poll.
- Externe Tools (Grafana/Loki), Postgres-Migration — bewusst spätere
  Aufrüstpfade, für die das JSON-Lines-Format aber schon vorbereitet.

---

## Architektur-Entscheidungen (Zusammenfassung)

| Frage | Entscheidung |
|---|---|
| Speicherort | JSON-Lines-Dateien (bestehende stündliche Rotation erweitert), **keine** DB — vermeidet SQLite-`BEGIN EXCLUSIVE`-Lock-Konkurrenz mit Buchungen |
| Log-Level | `TRACE < DEBUG < INFO < WARNING < ERROR < FATAL` |
| Log-Ansicht | Neuer Screen in der App (kein externes Tool) |
| Server-Logging-Tiefe | Durchgängig in allen Routern (außer `help.py`) |
| Remote-Log-Level | Über bestehenden `/health`-Poll (alle 10s), nicht WebSocket |
| Trace-Korrelation | Ja, `trace_id` pro Request, client- und serverseitig in jeder zugehörigen Log-Zeile |
| PII | Uneingeschränkt loggen (internes Ops-Tool hinter neuer Permission) |
| Berechtigungen | Neu: `logs.view` (Log-Ansicht sehen), `logs.configure` (fremde Geräte-Level setzen) |
| Aufbewahrung | 7 Tage, wie bisher |

---

## Teil 1 — Backend

### Neue Dateien
- `backend/logging_config.py` — TRACE/FATAL-Level, JSON-Formatter, Context-Vars, `setup_logging()`
- `backend/middleware.py` — `TraceIdMiddleware` (reines ASGI, nicht `BaseHTTPMiddleware` — Letzteres hat bekannte Interaktionsprobleme mit `StreamingResponse`, und `stats.py`'s CSV-Export nutzt genau das)
- `backend/device_registry.py` — Hybrid in-memory (`last_seen`, alle 10s) + persistiert (`forced_level`, nur bei Änderung) — analog zum bestehenden `_HelpManager`-Dict-Muster, aber ohne dessen Overwrite-Problem, da hier nur Metadaten pro Gerät verwaltet werden, keine aktiven Verbindungen
- `backend/routers/logs.py` — Ingest/Query/Devices/Set-Level-Endpunkte

### Geänderte Dateien
- `backend/main.py` — `_setup_logging()` → `logging_config.setup_logging()`, `TraceIdMiddleware` registrieren, `logs.router` einbinden, `/health` erweitern, `permission_node`+`device_log_level`-Migration ergänzen (analog bestehendem `kiosk`/`kiosk.access`-Block in `_migrate()`)
- `backend/init_db.py` — `device_log_level`-Tabelle, `logs`/`logs.view`/`logs.configure` in `seed_permissions()`
- `backend/dependencies.py` — `get_current_user()` setzt zusätzlich einen `user_ctx`-Contextvar (1 Zeile); neue `get_current_user_optional()` für den Ingest-Endpunkt (muss auch für nicht eingeloggte Clients funktionieren, z.B. ein Login-Fehler-Log)
- `backend/config.py` — `LOG_LEVEL`-Env-Var (Default `INFO`)
- `backend/schemas.py` — neue Pydantic-Modelle (Ingest-Request/Response, Query-Response, `DeviceInfo`, `SetDeviceLevelRequest`)
- `backend/routers/{auth,sales,topup,users,products,stats}.py` — `logger = logging.getLogger(__name__)` + Log-Aufrufe (Muster unten, gilt für alle sechs)
- `backend/routers/help.py` — **nur** `logger = logging.getLogger(__name__)`, sonst nichts — bewusst nicht angefasst

Keine neue pip-Abhängigkeit — Stdlib (`logging`, `contextvars`, `json`) reicht.

### JSON-Log-Zeile (Schema)

Eine JSON-Zeile pro Eintrag, weiterhin über die bestehende `_TopOfHourHandler`-Rotation geschrieben:

```json
{"ts": "2026-08-06T14:32:10.123+00:00", "level": "ERROR", "logger": "routers.topup",
 "message": "Topup failed: database busy (nfc_uid=A1B2, amount=10.00, user=kim)",
 "trace_id": "b3f1k2-9x7q1a", "origin": "server", "device_id": "and-l3f2a1-8k2n9c",
 "user_id": 5, "username": "kim", "path": "/api/topup/", "method": "POST",
 "status_code": 503, "exception": null}
```

`origin`: `"server"` oder `"client"`. Bereits vorhandene Alt-Zeilen im Klartext-Format
werden beim Lesen einfach übersprungen (kein `json.loads()`-Erfolg), fallen nach
7 Tagen automatisch aus der Aufbewahrung — keine Migration nötig.

### Root-Logger-Level-Fix + Laufzeit-Konfigurierbarkeit

`logging_config.setup_logging()` setzt `root.setLevel(...)` explizit aus `LOG_LEVEL`
(Startup-Default) — behebt den gefundenen Bug. Laufzeit-Änderung (auch für den
Server selbst, ohne Neustart) läuft über **denselben** Mechanismus wie
Client-Geräte: `PUT /api/logs/devices/{device_id}/level` mit der reservierten
Geräte-ID `"__server__"` ruft zusätzlich live `logging.getLogger().setLevel(...)`
auf und persistiert es (übersteht Neustart). Ein Client-Level wird beim Ingest
**nicht** gegen das Server-Level gefiltert — das sind zwei unabhängige Regler
(Client filtert schon selbst vor dem Versand).

### Trace-ID/Device-ID-Middleware

`contextvars` für `trace_id`, `device_id`, `path`, `method`, `user` (User wird erst
in `dependencies.get_current_user()` gesetzt, da die Middleware vor der
FastAPI-Dependency-Auflösung läuft). Liest `X-Trace-Id`/`X-Device-Id`-Header
(generiert `trace_id` server-seitig falls nicht vorhanden — z.B. bei
Server-internen Aktionen), echot `X-Trace-Id` in der Response, und loggt **eine
Zeile pro Request** (Level nach Status-Code: <400 INFO, <500 WARNING, sonst
ERROR; `/health` auf TRACE gedrosselt statt hart gefiltert wie bisher — bleibt
bei Bedarf trotzdem sichtbar, wenn wer das Level hochdreht). Ein
`ContextFilter` (in `logging_config.py`) stempelt diese Felder automatisch auf
jeden `LogRecord`, der sie nicht explizit selbst mitbringt (der Ingest-Endpunkt
setzt sie z.B. explizit pro Eintrag).

Nebeneffekt: liefert erstmals ein echtes HTTP-Access-Log (uvicorns eigenes
`propagate=False` auf `"uvicorn"`/`"uvicorn.access"` verhindert bisher, dass
das in die Datei gelangt), und einen Sicherheitsnetz-Fang für unbehandelte
Exceptions (aktuell stille 500er werden zu geloggten FATAL-Zeilen mit
vollem Traceback).

### Geräte-Registry + `/health`-Erweiterung

`device_log_level`-Tabelle (`device_id` PK, `label`, `platform`, `forced_level`,
`updated_by`, `updated_at`) — nur bei tatsächlicher Level-Änderung beschrieben,
nicht bei jedem Poll (`last_seen` bleibt reines In-Memory-Dict, rekonstruiert
sich durch die laufenden Polls selbst). `/health` bleibt öffentlich/ohne Auth
(muss vor Login funktionieren), nimmt optional `device_id`/`platform`/`label`
als Query-Parameter entgegen und gibt `{"status": "ok", "log_level": <erzwungenes Level oder null>}` zurück.

### `backend/routers/logs.py`

- `POST /api/logs/ingest` — **keine Permission nötig** (muss vor Login gehen,
  z.B. ein Login-Fehler-Log). Nimmt ein Batch von Client-Log-Einträgen
  (gedeckelt, z.B. 200/Request), schreibt jeden über den normalen
  `logging`-Mechanismus (`logging.getLogger(f"client.{entry.logger}").log(...)`)
  — nutzt damit automatisch dieselbe Rotations-/Aufbewahrungs-Logik.
- `GET /api/logs/query` (`logs.view`) — Filter: `level`, `origin`, `device_id`,
  `trace_id`, `logger`, `q` (Volltext in `message`), `since`/`until`, `limit`/`offset`
  — Stil an `stats.py`s `get_transactions` angelehnt (`Query(default, ge=, le=)`),
  aber **dateibasiert statt SQL**: `since`/`until` bestimmen direkt die
  relevanten `kasse_YYYY-MM-DD_HH.log`-Dateinamen, jede Zeile wird geparst und
  gefiltert. Sortierung nach dem `ts`-Feld (nicht Dateireihenfolge — Client-Einträge
  können durch Versandverzögerung leicht verschoben ankommen). Response-Form
  bewusst `{items, has_more}` statt `{items, total}` — ein exaktes `COUNT(*)`
  würde das ganze Zeitfenster scannen müssen, auch für Seite 1.
- `GET /api/logs/devices` (`logs.configure`) — Liste bekannter Geräte
  (inkl. synthetischem `"Server"`-Eintrag für `__server__`).
- `PUT /api/logs/devices/{device_id}/level` (`logs.configure`) — setzt/löscht
  das erzwungene Level für ein Gerät (oder den Server, s.o.).

### Permission-Seeding (beide Stellen, exakt wie bestehender `kiosk`/`kiosk.access`-Block)

`init_db.py`s `seed_permissions()`-Liste **und** `main.py`s `_migrate()`
(`INSERT OR IGNORE`, damit bereits deployte DBs die Permission beim nächsten
Serverstart bekommen, ohne `init_db.py` neu laufen zu lassen):

```
("logs",           None,   "Protokolle",               "group", 8)
("logs.view",       "logs", "Protokolle einsehen",       "r",     1)
("logs.configure",  "logs", "Protokoll-Level verwalten",  "w",     2)
```

`seed_default_data()` vergibt automatisch alle Nicht-Gruppen-Permissions an
`admin` — keine weitere Änderung nötig. `GET /api/users/permission-tree` liefert
die neuen Knoten danach automatisch aus, **der bestehende
`edit_user_dialog.dart`-Berechtigungsbaum braucht keine Flutter-Änderung**, um
sie anzeigen/zuweisen zu können (Baum wird dynamisch vom Server bezogen,
siehe `lib/services/users_service.dart:72-80`).

### Router-Instrumentierung (Muster, gilt für alle sechs Router)

`logger = logging.getLogger(__name__)` pro Modul. **INFO** für erfolgreiche
Geschäftsvorfälle (mit vollem Kontext — Namen/Beträge, gemäß No-Redaction-Vorgabe),
**WARNING** für Permission-Verweigerungen und um destruktive Aktionen zu klammern,
**ERROR** für echte Fehlschläge.

Höchster Nutzwert (aus der Recherche identifiziert, exemplarisch statt
vollständig aufgelistet):
- `topup.py`: beide Endpunkte nutzen `get_db(exclusive=True)` ohne jede
  Fehlerbehandlung heute — `sqlite3.OperationalError` (DB busy) würde aktuell
  als nackter 500 durchschlagen. ERROR-Log mit Kontext (uid/betrag/user) davor.
  INFO auf jede erfolgreiche Auf-/Auszahlung.
- `stats.py`s `event_reset` — unwiderruflicher, tenant-weiter Balance-Reset,
  erfasst aktuell nicht mal die Anzahl betroffener Zeilen (`cursor.rowcount`
  ist trivial ergänzbar). WARNING vor und nach Ausführung, mit Zeilenzahl.
- `users.py`: Permission-/Kategorie-Änderungen sind sicherheitsrelevant — IMMER
  loggen wer wem was geändert hat (nie das Passwort/den Hash selbst).
- `products.py`s `_require_category_flag`-Helper deckt 4 Endpunkte mit einem
  gemeinsamen 403 ab — ein Log-Aufruf dort statt vierfach dupliziert.
- `auth.py`: INFO auf Login-Erfolg/Logout, WARNING auf Fehlversuche und
  Refresh-Token-Reuse nach Widerruf (echtes Sicherheitssignal).

---

## Teil 2 — Frontend (`nfc_kasse_app/`)

### Neue Dateien
- `lib/services/app_logger.dart` — statische Logging-Fassade + Puffer (kein
  Riverpod-/Dio-Bezug, daher überall aufrufbar, auch aus dem Dio-Interceptor
  selbst und noch vor `runApp()`)
- `lib/services/logs_service.dart` — HTTP-Aufrufe zu `/api/logs/*`
- `lib/models/log_models.dart` — `LogEntry`/`DeviceInfo`/Query-Ergebnis-Modelle
- `lib/utils/id_generator.dart` — `generateId([prefix])`, handgerollt
  (Zeitstempel+Zufallszahl, Base36) statt neuer `uuid`-Abhängigkeit — trace_id/
  device_id sind interne Korrelations-Tokens ohne Sicherheitsanspruch (der
  JWT bleibt die eigentliche Sicherheitsgrenze), Kollisionswahrscheinlichkeit
  bei dieser Größenordnung vernachlässigbar
- `lib/screens/log_viewer_screen.dart` — neuer Viewer

### Geänderte Dateien
- `lib/providers/providers.dart` — neue Sektion "Logging" (gleiches
  `State`/`Notifier`/`Provider`-Dreiergespann wie `HelpState`/`HelpNotifier`/
  `helpProvider`), `AppScreen.logs`
- `lib/services/api_client.dart` — Trace-/Device-ID-Header im `onRequest`,
  neuer `onResponse`-Hook, Fehler-Logging im `onError`
- `lib/main.dart` — globale Error-Handler (`FlutterError.onError`,
  `PlatformDispatcher.instance.onError`, `runZonedGuarded`), Device-ID/Log-Level
  laden+überschreiben wie bestehende Settings
- `lib/screens/settings_screen.dart` — neuer Tab: lokales Log-Level, Geräte-Label
- `lib/screens/main_shell.dart` + `lib/widgets/app_sidebar.dart` — Routing/Nav
  für den neuen Screen, sichtbar bei `logs.view`
- `lib/models/user_model.dart` — `canViewLogs`/`canConfigureLogs`-Getter
  (analog `canViewStats` etc.)

Keine neue `pubspec.yaml`-Abhängigkeit.

### `AppLogger` (Kernstück)

Statische Klasse mit `trace/debug/info/warning/error/fatal(message, {logger, traceId, error, stackTrace})`.
Schwellenwert-Filterung passiert **beim Aufruf**, nicht erst beim Anzeigen —
unterhalb des aktuellen Levels liegende Aufrufe werden gar nicht erst gepuffert
(spätere Level-Änderungen können bereits verworfene Details nicht rückwirkend
zurückholen — wer ein Gerät gezielt debuggen will, muss dessen Level *vorher*
hochdrehen, nicht erst beim Öffnen des Viewers). In-Memory-Puffer (gedeckelt,
FIFO), zusätzlich in `SharedPreferences` gespiegelt, damit ein gekillter Prozess
nichts verliert (`AppLogger.loadPersisted()` beim nächsten Start). Ein
`onSevereLog`-Callback (vom `LoggingNotifier` gesetzt) triggert bei ERROR/FATAL
einen entprellten Sofort-Versand statt bis zur nächsten Rotation zu warten.

### Riverpod "Logging"-Sektion

`LoggingState` (`remoteOverride`, `pendingCount`, `lastShipAt`/`lastShipFailed`),
`LoggingNotifier`: `_effective = remoteOverride ?? localLogLevelProvider` (Remote
gewinnt immer, solange aktiv — analog MDM-Verhalten: eine Admin-Vorgabe wird
nicht durch eine veraltete lokale Einstellung ausgehebelt; lokal bleibt trotzdem
jederzeit änderbar, wirkt sich nur erst aus, sobald die Remote-Vorgabe aufgehoben
wird). Rotations-Timer: **stündlich nativ, alle 45s auf Web** (Begründung unten).
`applyRemoteLevel(...)` wird vom `/health`-Poll aufgerufen.

### `connectionStatusProvider`-Erweiterung

Bestehender 10s-Poll (`lib/providers/providers.dart`) bekommt `device_id`/
`platform`/`label` als Query-Parameter und liest `log_level` aus der Antwort,
ruft `loggingProvider.notifier.applyRemoteLevel(...)`. Öffentliche Form
(`StreamProvider<bool>`) und bestehende Konsumenten (`_ConnectionIndicator`)
bleiben unverändert — die Level-Übernahme ist ein Nebeneffekt desselben Polls,
kein separat zu verdrahteter neuer Mechanismus.

### Log-Viewer-Screen

An `stats_screen.dart` angelehnt (`TabController`, `FutureProvider.autoDispose.family`,
`ListView.separated`, `hasPermission(...)`-Gating-Muster). Tab 1 "Protokoll":
Filterzeile (Min-Level, Origin, Device-ID, **Trace-ID-Suchfeld** — die
zentrale Ende-zu-Ende-Debugging-Funktion, entsprechend prominent platziert),
farbcodierte Zeilen nach Level. Tab 2 "Geräte" (nur mit `logs.configure`
sichtbar): Geräteliste inkl. synthetischem "Server"-Eintrag, Level-Picker pro
Zeile.

### Berechtigungsgrenze

| Aktion | Berechtigung |
|---|---|
| Eigenes Geräte-Log-Level lokal einstellen | keine — immer nur das eigene Gerät |
| Eigene gepufferte Logs an den Server senden | keine — muss auch vor Login gehen |
| Log-Viewer öffnen (Server- + alle Geräte-Logs sehen) | `logs.view` |
| Geräteliste sehen, fremdes Geräte-/Server-Level setzen | `logs.configure` |

### Globale Error-Handler (`main.dart`)

Bisher komplett fehlend. `runZonedGuarded` um den App-Start,
`FlutterError.onError` (ruft danach weiterhin `FlutterError.presentError`, um
bestehendes Rot-Bildschirm-/Konsolen-Verhalten zu erhalten),
`PlatformDispatcher.instance.onError` — alle drei loggen auf **FATAL** (zur
Abgrenzung von normal behandelten `AppLogger.error()`-Aufrufen in Try/Catch-Blöcken).
`loggingProvider` muss einmal früh gelesen werden (in `NfcKasseApp.build()`,
nicht erst nach Login), damit der Versand-Timer auch Login-Fehler noch erfasst.

### Web-Besonderheiten

Kein echtes Dateisystem auf Web — Puffer ist auf **beiden** Plattformen ein
In-Memory-`List`, nur zusätzlich in `SharedPreferences` gespiegelt (auf Web
ohnehin die einzige Option, `localStorage`-basiert, unkritisch bei
gedeckelter Puffergröße). Versand-Intervall bewusst kürzer auf Web (45s statt
stündlich) — ein Browser-Tab kann jederzeit ohne verlässlichen Lifecycle-Callback
geschlossen werden; `beforeunload`/`visibilitychange` sind nicht zuverlässig
genug, um Zustellung zu garantieren, also wird stattdessen einfach das
Zeitfenster unversendeter Logs klein gehalten. Zusätzlich Best-Effort-Sofortversand
bei `AppLifecycleState.hidden`/`paused` (`WidgetsBindingObserver`).

---

## Umsetzungsreihenfolge (mit Verifikation je Phase)

1. **Backend-Fundament**: `logging_config.py`, `middleware.py`, `main.py`-Verdrahtung,
   `dependencies.py`-Contextvar-Hook, Permission-/Tabellen-Migration.
   *Verifikation:* `init_db.py` frisch + bestehende DB neu starten funktionieren
   beide; ein beliebiger Endpunkt-Aufruf erzeugt eine JSON-Zeile mit `trace_id`
   in `backend/logs/kasse_*.log`; `/api/users/permission-tree` listet die neuen
   Knoten ohne Flutter-Änderung.
2. **Router-Instrumentierung**: alle sechs Router + triviale Zeile in `help.py`.
   *Verifikation:* Login-Fehlversuch, Aufladung, Buchung, Event-Reset,
   Berechtigungsänderung auslösen — erwartete Log-Zeilen mit erwarteten Levels
   prüfen; Verhalten/Responses bleiben unverändert (rein additiv).
3. **`logs.py`-Router + Geräte-Registry + `/health`-Erweiterung**.
   *Verifikation:* Testbatch an `/api/logs/ingest`, Query mit verschiedenen
   Filtern (403 ohne `logs.view` bestätigen), Geräte-Level setzen und über
   `/health?device_id=...` bestätigt sehen, `__server__`-Level ändert live
   die tatsächliche Root-Logger-Verbosity.
4. **Frontend `AppLogger` + Versand-Pipeline + globale Handler** (Puffer/Handler-Hälfte
   unabhängig von Phase 2/3, kann parallel starten; Versand-Hälfte braucht den
   Ingest-Endpunkt zur sinnvollen Prüfung).
   *Verifikation:* App starten, gezielten Fehler auslösen (falsches Passwort,
   Flugmodus); geshippter Batch kommt serverseitig an, **`trace_id` stimmt exakt
   mit der zugehörigen Server-Log-Zeile überein** — das ist der entscheidende
   Ende-zu-Ende-Nachweis.
5. **Remote-Level-Steuerung**: `connectionStatusProvider`-Erweiterung, lokales
   Level in den Einstellungen.
   *Verifikation:* Von einer zweiten (Admin-)Session aus ein laufendes Gerät auf
   ein anderes Level setzen, innerhalb von ~10s Wirkung im Gerät bestätigen.
6. **Log-Viewer-Screen** (rein additive UI auf bereits fließenden Daten).
   *Verifikation:* Gemischte Client-/Server-Einträge sichtbar, Trace-ID-Filter
   reproduziert das Szenario aus Phase 4 in der UI, Geräte-Tab funktioniert
   inklusive Level-Setzen aus der Oberfläche selbst.
