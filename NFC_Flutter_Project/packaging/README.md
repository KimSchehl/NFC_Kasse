# NFC-Kasse Backend — Release Installer

Builds `NFC-Kasse-Setup.exe`: a Windows installer that registers the backend
as a Windows service (auto-starts at boot, no console window, restarts on
crash) and installs a Desktop/Start Menu shortcut to the web app. This is
the production deployment path — `start_backend.bat`/`.sh` in the repo root
remain unchanged for local development.

## One-time setup (build machine only)

```
pip install -r backend\requirements-service.txt
pip install pyinstaller
winget install -e --id JRSoftware.InnoSetup
```

WinSW itself does not need manual installation — `build_installer.bat`
downloads and SHA256-verifies it automatically on first build.

## Building a release

Before building, make sure `backend/webapp/` (Flutter web release build) and
`backend/updates/` (at least one `nfc-kasse_X.Y.Z.apk`) are up to date —
run `build_and_deploy.bat` from the repo root first if not.

```
packaging\build_installer.bat
```

Output: `packaging\innosetup\dist\NFC-Kasse-Setup.exe`.

Bump `AppVersion` in `packaging\innosetup\nfc_kasse_installer.iss` before
cutting a new release — Windows uses it to decide whether "Programs and
Features" shows an update or a duplicate entry.

## What the installer does

- Installs program files (backend exe, web app, WinSW) to
  `C:\Program Files\NFC-Kasse\`.
- Creates `C:\ProgramData\NFC-Kasse\` for everything that changes at
  runtime (`kasse.db`, `config.env`, `logs\`, `backups\`) — protected from
  removal on uninstall (`uninsneveruninstall` in the `.iss`).
- Registers and starts the `NfcKasseBackend` Windows service (auto-start,
  restarts on failure).
- Adds a Windows Firewall inbound rule so LAN tablets can reach it.
- Adds Desktop + Start Menu shortcuts ("NFC-Kasse öffnen", "Dienst
  starten"/"Dienst stoppen").
- On first run, `backend/service_main.py` generates `config.env` with a
  real random `SECRET_KEY` and initializes `kasse.db`. On every
  subsequent start it takes a WAL-safe backup (rotated, 5 newest kept).

Re-running the installer over an existing install upgrades in place: the
service is stopped before files are replaced, then restarted — `kasse.db`
and `config.env` are never touched (the installer never lists
`C:\ProgramData` as a copy destination in the first place).

## Operating an installed instance

- **Edit config** (event name, chip deposit, feature flags, printer
  settings): `C:\ProgramData\NFC-Kasse\config.env`, then "Dienst stoppen" +
  "Dienst starten" from the Start Menu (or `services.msc`).
- **Logs**: `C:\ProgramData\NFC-Kasse\logs\*.log` (app, JSON lines,
  hourly rotation) and `C:\ProgramData\NFC-Kasse\logs\winsw\` (raw
  stdout/stderr — the fallback if something goes wrong before the app's
  own logging is set up, e.g. a hand-broken `config.env`).
- **`reset_db.py` / `migrate.py`** (dev/ops tools, not bundled into the
  installer) still work against a production install — set `DB_PATH`
  first:
  ```
  set DB_PATH=C:\ProgramData\NFC-Kasse\kasse.db
  python backend\reset_db.py
  ```

## Verified (2026-09-02, on this machine)

Full chain tested end-to-end: unfrozen `service_main.py` → frozen exe
standalone (health, webapp, `/update/latest`, `/download`, login round-trip
exercising bcrypt + python-jose/cryptography, full APK download) → WinSW
install/start/stop/uninstall with the real service (stdio capture into
WinSW's own log confirmed, no crash) → full installer install/upgrade/
uninstall, confirming: service auto-starts, firewall rule works, data
(`kasse.db` row counts, `config.env`'s `SECRET_KEY`) survives an upgrade
untouched, and uninstall removes the service/firewall rule/Program Files
while leaving `C:\ProgramData\NFC-Kasse\` fully intact.

**Not verified in this environment** (sandboxed shell, not running as
SYSTEM/elevated interactively):
- Crash-restart (`<onfailure>`) — couldn't force-kill the SYSTEM-owned
  service process to trigger it directly. The mechanism itself
  (`ChangeServiceConfig2` recovery actions) is standard Windows service
  behavior WinSW just configures declaratively, not something WinSW
  implements itself, so this is a low-risk gap — but worth a real check
  (Task Manager → End Task on `NfcKasseBackend.exe`, confirm it comes back
  within ~10s) before relying on it in production.
- Reboot survival — not testable within a single session. Confirm once,
  after any real deployment, that a full machine restart brings the
  service back up without manual intervention.

## Known follow-ups (deliberately out of scope for v1)

- **Code-signing.** Without a certificate, first run on a fresh machine
  will likely trigger Windows SmartScreen's "unrecognized app" warning
  ("More info" → "Run anyway" to proceed). Needs a paid certificate to
  remove.
- **Backend self-update.** Re-running the installer is the update
  mechanism for now. The existing OTA system (`routers/update.py`) only
  ever updates the Android app, not this backend.
