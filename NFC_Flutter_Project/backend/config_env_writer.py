"""
Updates individual KEY=VALUE lines in config.env without disturbing anything
else in the file — comments, blank lines and every key not being changed all
stay exactly as they were, in their original order. A key that doesn't exist
yet is appended at the end.

Mirrors the admin tool's `ConfigEnvFile.save()` (nfc_kasse_admin/lib/services
— same preserve-everything-else behavior), just on the Python side. This is
the one place the backend itself needs to write config.env: importing the
printer/bon-text part of a Festvorlage (see routers/events.py).
"""

from pathlib import Path


def update_config_env(path: Path, updates: dict[str, str]) -> None:
    """Rewrites `path`, replacing the value of each key in `updates` in
    place (or appending it if absent). No-ops if `updates` is empty, so
    callers don't need to guard an empty dict themselves."""
    if not updates:
        return

    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    remaining = dict(updates)
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            key = stripped.split("=", 1)[0].strip()
            if key in remaining:
                out.append(f"{key}={remaining.pop(key)}")
                continue
        out.append(line)
    for key, value in remaining.items():
        out.append(f"{key}={value}")

    path.write_text("\n".join(out) + "\n", encoding="utf-8")
