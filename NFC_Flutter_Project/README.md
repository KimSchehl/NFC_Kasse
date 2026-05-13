# NFC-Kasse

Cashless NFC payment system for events. Staff use tablets or phones to scan guest wristbands and book products. The backend runs locally on a thin client; all devices connect via a local Wi-Fi access point.

---

## Project Structure

```
NFC_Flutter_Project/
├── README.md                       ← This file
├── TESTING.md                      ← How to run the test suites
│
├── docs/
│   ├── MANUAL_EN.md                ← Staff & admin user manual (English)
│   ├── MANUAL_DE.md                ← Staff & admin user manual (German)
│   ├── ROADMAP.md                  ← Planned future features
│   ├── database/
│   │   └── DATABASE_SCHEMA.md      ← Table definitions and design decisions
│   ├── backend/
│   │   ├── API_OVERVIEW.md         ← All API endpoints with request/response
│   │   └── ARCHITECTURE.md        ← FastAPI structure, JWT, transaction safety
│   ├── frontend/
│   │   ├── SCREENS.md              ← Flutter screens and layout
│   │   └── SERVICES.md             ← Services, API client, NFC, state management
│   └── usecases/
│       ├── UC01_PURCHASE_FLOW.md   ← Booking + cancel
│       ├── UC02_TOPUP.md           ← Balance top-up & payout
│       ├── UC03_USER_MANAGEMENT.md ← Create users, assign permissions
│       └── UC04_EVENT_SETUP.md     ← First install & event checklist
│
├── backend/                        ← FastAPI Python backend
│   ├── main.py                     ← App entry point, CORS, router registration
│   ├── database.py                 ← SQLite context manager (get_db)
│   ├── dependencies.py             ← JWT auth, bcrypt, require_permission factory
│   ├── schemas.py                  ← Pydantic request/response models
│   ├── init_db.py                  ← Schema creation + seed data
│   ├── migrate.py                  ← Schema migration helpers
│   ├── requirements.txt            ← Runtime dependencies
│   ├── requirements-test.txt       ← Test-only dependencies (pytest, httpx)
│   ├── pytest.ini                  ← pytest config
│   └── routers/
│       ├── auth.py                 ← Login, refresh, logout, /me
│       ├── products.py             ← Categories and products (CRUD)
│       ├── sales.py                ← Balance query, booking, cancel
│       ├── topup.py                ← Balance top-up and payout
│       ├── users.py                ← User management, permissions
│       └── stats.py                ← Revenue summary, transaction list, CSV export
│
└── nfc_kasse_app/                  ← Flutter app (Android / iOS / Web)
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── config/
        │   └── api_config.dart     ← Backend base URL
        ├── models/                 ← Data models (ProductModel, CustomerModel, …)
        ├── services/               ← API calls (SalesService, ProductService, …)
        ├── providers/              ← Riverpod providers + CartNotifier
        ├── screens/                ← Login, POS, Stats, Users, Settings, Account
        ├── widgets/                ← Reusable widgets (CartPanel, ProductGrid, …)
        └── utils/
            └── formatters.dart     ← formatPrice, formatTime, formatDate
```

---

## Quick Start

### Backend

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Create database + seed admin user (password: admin)
python init_db.py

# Start the server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Swagger UI (all endpoints testable in browser): **http://localhost:8000/docs**

> **Important:** Change the admin password immediately after first login.

### Flutter App

```bash
cd nfc_kasse_app

# Install packages
flutter pub get

# Run on a connected device or emulator
flutter run
```

The app connects to `http://10.0.2.2:8000` by default (Android emulator → host machine).
For a real device on the same network, update `lib/config/api_config.dart` with your server's local IP.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | FastAPI · Python 3.12 · Uvicorn |
| Database | SQLite (WAL mode) · PostgreSQL-ready schema |
| Auth | JWT · access token 24 h · refresh token 30 days · bcrypt |
| Frontend | Flutter 3 · Dart · Riverpod (state management) |
| NFC (mobile) | `nfc_manager` — Android & iOS native NFC |
| NFC (desktop/USB) | USB HID reader — keyboard emulation, auto-submit on Enter |
| HTTP client | `dio` with auto-refresh interceptor |
| Secure storage | `flutter_secure_storage` |

---

## Deployment

The system is designed for local network use at events:

| Device | Role |
|---|---|
| Fujitsu S920 Thin Client | Runs the Python backend, stores `kasse.db` |
| TP-Link Access Point | Wi-Fi "Kasse" — all tablets connect here |
| Android tablets / phones | Run the Flutter app, connect to `http://192.168.1.1:8000` |

---

## Language Convention

| Context | Language |
|---|---|
| Code (identifiers, table names, column names, comments, docs) | English |
| Content (product names, category names, UI labels, event names) | German |
