"""
Self-hosted OTA update endpoint.

The build_and_deploy.bat builds and drops the APK into backend/updates/
with the naming convention:  nfc-kasse_<major>.<minor>.<patch>.apk
e.g.  nfc-kasse_1.0.1.apk

The app on first start calls /update/latest, compares versions, and
if a newer build is available shows a one-tap update dialog.
"""

import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

router = APIRouter(prefix="/update", tags=["update"])

UPDATES_DIR = Path(__file__).parent.parent / "updates"

# Matches both plain semver files (1.0.1.apk) and the deploy-script output
# (nfc-kasse_1.0.1.apk).  The captured group is always the semver string.
_FILENAME_RE = re.compile(r"^(?:nfc-kasse_)?(\d+\.\d+\.\d+)$")

# Only alphanumeric, dots, dashes, underscores allowed → no path traversal
_SAFE_FILENAME = re.compile(r"^[\w.\-]+\.apk$")


def _semver_of(apk: Path) -> str | None:
    m = _FILENAME_RE.match(apk.stem)
    return m.group(1) if m else None


def _version_tuple(semver: str) -> tuple[int, ...]:
    return tuple(int(x) for x in semver.split("."))


def _latest_apk() -> Path | None:
    if not UPDATES_DIR.is_dir():
        return None
    candidates = [f for f in UPDATES_DIR.glob("*.apk") if _semver_of(f)]
    if not candidates:
        return None
    return max(candidates, key=lambda f: _version_tuple(_semver_of(f)))


@router.get("/latest")
def get_latest():
    """Return the latest available APK version and its download path."""
    apk = _latest_apk()
    if apk is None:
        raise HTTPException(status_code=404, detail="No update available")
    return {
        "version": _semver_of(apk),
        "filename": apk.name,
        "download_path": f"/update/download/{apk.name}",
    }


@router.get("/download/{filename}")
def download_apk(filename: str):
    """Serve the requested APK file."""
    if not _SAFE_FILENAME.match(filename):
        raise HTTPException(status_code=400, detail="Invalid filename")
    path = UPDATES_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(
        path=path,
        media_type="application/vnd.android.package-archive",
        filename=filename,
    )
