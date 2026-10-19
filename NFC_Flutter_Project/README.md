# NFC-Kasse

Cashless NFC payment system for events. Guests carry an NFC chip whose balance lives on the server; staff scan the chip on a tablet, phone or browser and book articles. Everything runs on a local network, no internet needed during an event.

## Where things are documented

Each topic has exactly one place. The code itself is the final word; the documents point into it instead of copying it.

| Topic | Single source |
|---|---|
| Architecture, permission model, conventions, dev commands | [`../CLAUDE.md`](../CLAUDE.md) |
| Database schema and design decisions | `backend/init_db.py` (commented `CREATE TABLE`s, permission tree in `seed_permissions()`), upgrades of existing databases in `backend/migrations.py` |
| HTTP API | Swagger UI of the running backend at `http://<server>:8000/docs` (generated from the routers) |
| Running the tests | [`TESTING.md`](TESTING.md) |
| Packaging (PyInstaller, Inno Setup) | [`packaging/README.md`](packaging/README.md) |
| Licence keys for add-ons | [`license_tool/README.md`](license_tool/README.md) |
| Veranstalter model (schema v3): design, decisions, progress | [`docs/VERANSTALTER_PLAN.md`](docs/VERANSTALTER_PLAN.md) |
| Logging design | [`docs/LOGGING_SYSTEM_PLAN.md`](docs/LOGGING_SYSTEM_PLAN.md) |
| Ideas for later | [`docs/ROADMAP.md`](docs/ROADMAP.md) |
| User manuals (German): operators, sysadmins, stand staff, add-ons | [`docs/anleitungen/`](docs/anleitungen/README.md) |
| Screenshots for the manuals and how to regenerate them | [`docs/images/bedieneranleitung/README.md`](docs/images/bedieneranleitung/README.md) |
| BLE NFC reader firmware | [`../nfc-ble-reader/README.md`](../nfc-ble-reader/README.md) |

## Project structure

```
NFC_Flutter_Project/
├── backend/            FastAPI + SQLite backend, Windows service, admin CLI (admin_cli.py)
├── nfc_kasse_app/      Flutter POS app (Android, web build served by the backend under /webapp)
├── nfc_kasse_admin/    Flutter Windows admin tool (service, Veranstalter, Feste, config, bon layout, backups)
├── license_tool/       Generates licence keys for Pager / Leaderboard
├── packaging/          Builds NfcKasseBackend.exe and NFC-Kasse-Setup.exe
├── docs/               Manuals (German), screenshots, logging plan, roadmap
├── start_backend.bat   Dev launcher for Windows
├── start_backend.sh    Dev launcher for Linux/macOS
└── build_and_deploy.bat  Build APK + web app, deploy to tablets / copy into backend/webapp
```

## Language convention

| Context | Language |
|---|---|
| Code, identifiers, table and column names, comments, developer docs | English |
| Everything a user sees (UI, article and category names, manuals) | German |
