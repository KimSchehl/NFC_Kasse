# NFC-Kasse — Projekt-Übergabe & Kontext-Dokument
> Dieses Dokument für Claude Code in VS Code: Lies es komplett bevor du irgendetwas tust.
> Erstellt aus einer detaillierten Planungssession. Stand: Mai 2026.

---

## 1. Was ist dieses Projekt?

Eine **NFC-basierte Kassensoftware** für Veranstaltungen (Feste, Weinfeste, Events).
Gäste erhalten NFC-Armbänder/Chips — ihr Guthaben liegt auf dem Server, der Chip ist nur Identifikator.
Standverkäufer scannen den Chip → Betrag wird vom Guthaben abgezogen.

**Zielplattformen:**
- Flutter App: Android + iOS (NFC nativ via `nfc_manager` Package)
- Flutter Web: Windows/Browser (NFC via USB HID-Reader — Reader tippt UID wie Tastatur)
- Lokaler Server: Fujitsu S920 Thin Client + TP-Link Access Point (eigenes Kassen-WLAN)

**NFC-Tags:** MIFARE Classic — es wird NUR die UID gelesen. Guthaben IMMER server-seitig.

---

## 2. Tech-Stack (Entschieden)

| Schicht | Technologie | Begründung |
|---|---|---|
| Frontend | Flutter + Dart | Android, iOS, Web aus einer Codebase |
| Backend | FastAPI (Python) | Bereits vorhanden, gut strukturiert |
| Datenbank | SQLite (Phase 1) | Lokal, einfach, später PostgreSQL möglich |
| Auth | JWT (Access + Refresh Token) | Kein Cookie-Session wie bisher |
| Passwort | passlib + bcrypt | Bisher Klartext — MUSS ersetzt werden |
| NFC Mobile | flutter: nfc_manager | MIFARE Classic UID lesen |
| NFC Desktop | USB HID Input | Reader = Tastatur-Emulation, kein Extra-Code |
| Token Storage | flutter_secure_storage | Keychain (iOS) / Keystore (Android) |

---

## 3. Projektstruktur (Ziel)

```
nfc-kasse/
├── docs/
│   ├── PROJECT_HANDOVER.md     ← diese Datei
│   └── ROADMAP.md              ← Zukunftsideen
├── backend/
│   ├── init_db.py              ✅ FERTIG — Datenbankschema + Seed
│   ├── database.py             ← TODO: zentrale DB-Connection
│   ├── dependencies.py         ← TODO: get_current_user, check_permission
│   ├── main.py                 ← TODO: FastAPI App-Einstieg
│   └── routers/
│       ├── auth.py             ← TODO: Login, Refresh, Logout
│       ├── users.py            ← TODO: User CRUD + Rechtevergabe
│       ├── products.py         ← TODO: Produkte + Kategorien
│       ├── sales.py            ← TODO: Buchungen + Storno
│       ├── topup.py            ← TODO: Guthaben aufladen
│       └── stats.py            ← TODO: Statistiken
└── frontend/
    └── nfc_kasse_app/          ← TODO: Flutter Projekt
        └── lib/
            ├── main.dart
            ├── services/
            │   ├── api_service.dart
            │   ├── auth_service.dart
            │   └── nfc_service.dart
            └── screens/
                ├── login_screen.dart
                ├── pos_screen.dart
                └── settings_screen.dart
```

---

## 4. Datenbank — Schema (FERTIG, in init_db.py)

### Tabellen-Übersicht

| Tabelle | Zweck |
|---|---|
| `tenant` | Mandant — lokal immer id=1, plan='local' |
| `event` | Veranstaltung — lokal immer id=1, active=1 |
| `user` | Kassenpersonal (KEIN Gast-Login in der App) |
| `permission_node` | Der erweiterbare Berechtigungs-Baum (Daten, kein Code) |
| `role_template` | Wiederverwendbare Rollen-Vorlagen (z.B. "Standverkäufer") |
| `role_template_permission` | Welche Permissions hat eine Vorlage |
| `user_permission` | Individuelle Permissions pro User pro Event |
| `category` | Produktkategorien (z.B. "Getränke", "Speisen") |
| `product` | Produkte mit Preis, sort_order, active/deleted-Flag |
| `customer` | Gäste mit NFC-UID und Guthaben (balance) |
| `sale` | Jede Buchung — unveränderlich, mit price_at_sale! |
| `topup` | Guthaben-Aufladungen — separat von Käufen |
| `refresh_token` | JWT Refresh Tokens (gehashed, widerrufbar) |
| `user_setting` | Lokale UI-Einstellungen als Key/Value pro User |

### Kritische Design-Entscheidungen
- **`sale.price_at_sale`**: Pflichtfeld — Preis wird zum Buchungszeitpunkt gespeichert.
  Preisänderungen dürfen die Transaktionshistorie NICHT verfälschen.
- **Soft-Delete**: `deleted`-Flag auf `product` und `category` — historische Buchungen bleiben gültig.
- **`active`-Flag**: Produkte können deaktiviert werden ohne sie zu löschen.
- **Storno**: `sale.cancelled=1` + `cancelled_by` + `cancelled_at` — Original bleibt erhalten (Audit-Trail).
- **`tenant_id`** überall vorhanden — Cloud/Multi-Tenant später ohne Schema-Änderung möglich.
- **`PRAGMA journal_mode=WAL`**: Mehrere gleichzeitige Lesezugriffe möglich.

---

## 5. Berechtigungs-System (Permission Tree)

### Konzept
- Kein hardcodiertes Rollen-System ("admin", "seller" als Enum)
- Jede Permission ist ein Knoten in `permission_node` (Baum-Struktur)
- Jeder User bekommt individuell angekreuzte Permissions in `user_permission`
- Neue Permissions (FiBu, Lieferant, ...) = neue SQL-Zeilen, KEIN Code-Update nötig
- Rollen-Vorlagen (`role_template`) für schnelles Anlegen neuer User

### Aktuelle Permission-Knoten (bereits in DB)
```
kasse
  kasse.verkauf
    kasse.verkauf.buchen           [w]
    kasse.verkauf.storno_5min      [w]
    kasse.verkauf.storno_unlim     [w]
  kasse.guthaben
    kasse.guthaben.anzeigen        [r]
    kasse.guthaben.aufladen        [w]
    kasse.guthaben.auszahlen       [w]
produkte
  produkte.anzeigen                [r]
  produkte.erstellen               [w]
  produkte.bearbeiten              [w]
  produkte.preis                   [w]
  produkte.deaktivieren            [w]
  produkte.aktivieren              [w]
  produkte.loeschen                [w]
kategorien
  kategorien.anzeigen              [r]
  kategorien.erstellen             [w]
  kategorien.bearbeiten            [w]
  kategorien.loeschen              [w]
statistik
  statistik.umsatz                 [r]
  statistik.transaktionen          [r]
  statistik.export                 [r]
benutzer
  benutzer.anzeigen                [r]
  benutzer.erstellen               [w]
  benutzer.bearbeiten              [w]
  benutzer.loeschen                [w]
  benutzer.rechte                  [w]
einstellungen
  einstellungen.lokal              [rw]
  einstellungen.event              [rw]
  einstellungen.system             [rw]
```

### Rollen-Vorlagen (bereits in DB)
- **Standverkäufer**: buchen, storno_5min, guthaben anzeigen, produkte/kategorien anzeigen, lokale Einstellungen
- **Veranstaltungs-Verantwortlicher**: alle Kasse-Rechte, Preise ändern, Statistik, event-Einstellungen, Benutzerverwaltung anzeigen

### Backend-Prüfung (wie es implementiert werden soll)
```python
# In dependencies.py:
def require_permission(permission_id: str):
    def checker(current_user = Depends(get_current_user), event_id: int = ...):
        hat_recht = db.execute("""
            SELECT 1 FROM user_permission
            WHERE user_id=? AND event_id=? AND permission_id=?
        """, (current_user.id, event_id, permission_id)).fetchone()
        if not hat_recht:
            raise HTTPException(403, "Keine Berechtigung")
    return checker

# Verwendung in Router:
@router.post("/sale")
def create_sale(..., _=Depends(require_permission("kasse.verkauf.buchen"))):
    ...
```

---

## 6. JWT Auth — Konzept

### Ablauf
1. POST `/api/auth/login` mit `{username, password}`
2. Server prüft Passwort mit `passlib.verify`
3. Server erstellt **Access Token** (15-60 min) + **Refresh Token** (30 Tage)
4. Refresh Token wird **gehasht** in `refresh_token`-Tabelle gespeichert
5. Flutter speichert beide Tokens in `flutter_secure_storage`
6. Jede API-Anfrage: `Authorization: Bearer <access_token>`
7. Access Token abgelaufen → Flutter ruft `/api/auth/refresh` auf → neues Token-Paar
8. Logout → Refresh Token in DB als `revoked=1` markieren

### Wichtige Pakete
- **Backend**: `python-jose[cryptography]`, `passlib[bcrypt]`
- **Flutter**: `flutter_secure_storage`, `dio` (HTTP mit Interceptor für auto-refresh)

### Fehler aus altem Code die NICHT wiederholt werden dürfen
- ❌ Passwörter im Klartext speichern
- ❌ Admin-Check über `username.startsWith('admin')` im Frontend
- ❌ `sqlite3.connect("kasse.db")` hardcoded überall verteilt
- ❌ `allow_origins=["*"]` in Produktion
- ❌ Keine Pydantic-Modelle auf Endpunkten
- ❌ Hilfsfunktionen copy-paste in jedem Router

---

## 7. Alte Codebasis (Referenz)

Das Repo `https://github.com/KimSchehl/nfc-kasse.git` enthält den alten Stand:
- Plain HTML/CSS/JS Frontend als Static Files über FastAPI
- FastAPI Backend mit Routern: auth, user, products, categories, transactions, finances, settings
- SQLite Datenbank
- Docker Setup vorhanden (Dockerfile)
- Cookie-basierte Sessions (wird durch JWT ersetzt)
- Web NFC API (NDEFReader) im alten Frontend — funktioniert nur Android Chrome

**Was vom alten Code übernommen werden kann (Logik, nicht Code):**
- Router-Struktur nach Modulen
- `BEGIN EXCLUSIVE` bei Buchungen (Transaktionssicherheit)
- Docker-Setup als Basis

---

## 8. Deployment (Lokal)

- **Server**: Fujitsu S920 Thin Client
- **Netzwerk**: TP-Link Access Point, eigenes Kassen-WLAN (SSID: Kasse)
- **Backend-URL**: z.B. `http://192.168.1.1:8000` im lokalen Netz
- **Flutter**: Backend-URL als Konfiguration, nicht hardcoded

---

## 9. Nächste Schritte (Reihenfolge)

### Phase 1 — Backend (als nächstes)
1. `backend/database.py` — zentrale DB-Connection mit Context Manager
2. `backend/dependencies.py` — `get_current_user()`, `require_permission()`
3. `backend/routers/auth.py` — Login, Refresh, Logout Endpunkte
4. `backend/main.py` — FastAPI App zusammenbauen, CORS konfigurieren
5. `backend/routers/products.py` — Produkte + Kategorien CRUD
6. `backend/routers/sales.py` — Buchung + Storno (mit 5-min-Check)
7. `backend/routers/topup.py` — Guthaben aufladen
8. `backend/routers/users.py` — User CRUD + Rechtevergabe
9. `backend/routers/stats.py` — Umsatz, Transaktionen

### Phase 2 — Flutter
1. Flutter Projekt anlegen (`flutter create nfc_kasse_app`)
2. `services/api_service.dart` mit `dio` + Interceptor für Token-Refresh
3. `services/auth_service.dart` mit `flutter_secure_storage`
4. `screens/login_screen.dart`
5. `screens/pos_screen.dart` — Produktgrid + NFC-Scan + Warenkorb
6. `services/nfc_service.dart` mit `nfc_manager`
7. `screens/settings_screen.dart` — Permission-Tree UI

---

## 10. Offene Fragen / Entscheidungen

- [ ] Flutter Backend-URL: Config-Datei oder `.env`?
- [ ] Soll es einen "Kiosk-Modus" geben (Tablet läuft dauerhaft, kein Sperrbildschirm)?
- [ ] Welche Sprache in der App? Nur Deutsch oder mehrsprachig vorbereiten?
- [ ] Soll der Storno-Timer (5 min) server-seitig oder client-seitig geprüft werden?
  → Empfehlung: **server-seitig** (manipulationssicher)

