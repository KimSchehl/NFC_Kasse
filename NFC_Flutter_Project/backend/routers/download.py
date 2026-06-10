"""
APK download page and file server.

Provides a mobile-friendly landing page at /download so staff can install
the app by scanning a QR code shown in the Settings screen — no USB needed.
No authentication required; the page is intentionally public on the LAN.
"""

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse, HTMLResponse

router = APIRouter(prefix="/download", tags=["download"])

_UPDATES_DIR = Path(__file__).parent.parent / "updates"


def _latest_apk() -> tuple[str | None, Path | None]:
    """Returns (filename, full_path) of the newest APK by modification time."""
    apks = list(_UPDATES_DIR.glob("*.apk"))
    if not apks:
        return None, None
    latest = max(apks, key=lambda p: p.stat().st_mtime)
    return latest.name, latest


@router.get("", response_class=HTMLResponse, include_in_schema=False)
def download_page():
    filename, path = _latest_apk()

    if not filename or path is None:
        return HTMLResponse(
            "<!DOCTYPE html><html><body style='font-family:sans-serif;padding:2rem'>"
            "<h2>Kein APK verfügbar</h2>"
            "<p>Bitte zuerst <code>build_and_deploy.bat</code> ausführen.</p>"
            "</body></html>",
            status_code=404,
        )

    size_mb = round(path.stat().st_size / (1024 * 1024), 1)
    version = filename.replace("nfc-kasse_", "").replace(".apk", "")

    html = f"""<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NFC-Kasse installieren</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #1a1a2e; color: #e0e0e0;
      min-height: 100vh; display: flex; align-items: center; justify-content: center;
      padding: 24px;
    }}
    .card {{
      background: #16213e; border-radius: 16px; padding: 32px 24px;
      max-width: 400px; width: 100%; text-align: center;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
    }}
    .icon {{ font-size: 52px; margin-bottom: 16px; }}
    h1 {{ font-size: 1.6rem; font-weight: 700; color: #fff; margin-bottom: 6px; }}
    .version {{ color: #90caf9; font-size: 0.9rem; margin-bottom: 28px; }}
    .btn {{
      display: block; width: 100%; padding: 16px;
      background: #1976d2; color: #fff; border: none; border-radius: 12px;
      font-size: 1.1rem; font-weight: 600; cursor: pointer;
      text-decoration: none; margin-bottom: 10px;
    }}
    .btn:active {{ background: #1565c0; }}
    .meta {{ color: #78909c; font-size: 0.78rem; margin-bottom: 28px; }}
    .hint {{
      background: #0d1b2e; border-radius: 10px; padding: 16px;
      text-align: left; font-size: 0.82rem; color: #b0bec5; line-height: 1.7;
    }}
    .hint strong {{ color: #cfd8dc; display: block; margin-bottom: 6px; }}
    .hint ol {{ padding-left: 18px; }}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">📱</div>
    <h1>NFC-Kasse</h1>
    <div class="version">Version {version} &nbsp;·&nbsp; {size_mb} MB</div>
    <a href="/download/apk/{filename}" class="btn">⬇&nbsp; APK herunterladen</a>
    <div class="meta">{filename}</div>
    <div class="hint">
      <strong>Installation auf Android:</strong>
      <ol>
        <li>APK herunterladen (oben)</li>
        <li>Datei in den Downloads öffnen</li>
        <li>Bei Abfrage <em>„Aus dieser Quelle erlauben"</em> aktivieren</li>
        <li>Installieren &amp; App starten</li>
      </ol>
    </div>
  </div>
</body>
</html>"""
    return HTMLResponse(html)


@router.get("/apk/{filename}", include_in_schema=False)
def download_apk(filename: str):
    # Security: strip any path separators, only serve .apk files from updates dir
    safe_name = Path(filename).name
    if not safe_name.endswith(".apk"):
        return HTMLResponse("Nicht gefunden", status_code=404)
    path = _UPDATES_DIR / safe_name
    if not path.is_file():
        return HTMLResponse("Nicht gefunden", status_code=404)
    return FileResponse(
        str(path),
        media_type="application/vnd.android.package-archive",
        filename=safe_name,
    )
