"""
Copies only the single highest-semver .apk from backend/updates/ into a
throwaway staging folder that the PyInstaller spec bundles as `updates/`.

backend/updates/ accumulates every historical release build (routinely
gigabytes) but routers/update.py (semver-max) and routers/download.py
(mtime-max) only ever serve the single newest file at runtime — bundling the
whole history into every installer would be pure waste. Run this before
building the spec; it's idempotent (always wipes and recreates the seed dir).

Mirrors routers/update.py's own filename convention/semver parsing exactly
so "newest" means the same thing here as it does at runtime.
"""

import re
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
UPDATES_DIR = REPO_ROOT / "backend" / "updates"
SEED_DIR = Path(__file__).resolve().parent / "build" / "updates_seed"

_FILENAME_RE = re.compile(r"^(?:nfc-kasse_)?(\d+\.\d+\.\d+)$")


def _semver_of(apk: Path) -> str | None:
    m = _FILENAME_RE.match(apk.stem)
    return m.group(1) if m else None


def _version_tuple(semver: str) -> tuple[int, ...]:
    return tuple(int(x) for x in semver.split("."))


def stage() -> Path | None:
    if SEED_DIR.exists():
        shutil.rmtree(SEED_DIR)
    SEED_DIR.mkdir(parents=True, exist_ok=True)

    if not UPDATES_DIR.is_dir():
        print(f"No updates dir at {UPDATES_DIR} — seed folder will be empty.")
        return None

    candidates = [f for f in UPDATES_DIR.glob("*.apk") if _semver_of(f)]
    if not candidates:
        print(f"No versioned .apk found in {UPDATES_DIR} — seed folder will be empty.")
        return None

    newest = max(candidates, key=lambda f: _version_tuple(_semver_of(f)))
    dest = SEED_DIR / newest.name
    shutil.copy2(newest, dest)
    print(f"Staged {newest.name} ({dest.stat().st_size / 1_000_000:.1f} MB) -> {SEED_DIR}")
    return dest


if __name__ == "__main__":
    stage()
