"""
Generates a feature license key for a customer installation.

Usage:
    python license_tool/generate_license.py

Asks for the customer's INSTALLATION_ID (from their config.env), then which
feature to license, and prints one config.env-ready line, e.g.:
    PAGER_LICENSE_KEY=eyJ2IjoxLCJ...

Requires private_key.pem next to this script — run generate_keypair.py once
first if it doesn't exist yet.
"""

import base64
import json
import sys
from pathlib import Path

from cryptography.hazmat.primitives.serialization import load_pem_private_key

PRIVATE_KEY_PATH = Path(__file__).parent / "private_key.pem"

# Menu number -> feature name (the name that ends up in the signed payload
# and must match exactly what backend/config.py checks, e.g. "pager" gates
# PAGER_ENABLED). Add a line here when a new licensable feature is added.
FEATURES = {
    "1": "pager",
    "2": "leaderboard",
}


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_license(private_key, installation_id: str, feature: str) -> str:
    payload = json.dumps(
        {"v": 1, "installation_id": installation_id, "feature": feature},
        separators=(",", ":"),
    ).encode("utf-8")
    signature = private_key.sign(payload)
    return f"{_b64(payload)}.{_b64(signature)}"


def _pause() -> None:
    """Keeps the console window open when the script was double-clicked
    rather than run from an already-open terminal — otherwise the window
    (and the printed license key with it) disappears the instant the
    script finishes."""
    print("\nBeliebige Taste zum Beenden drücken . . .")
    try:
        import msvcrt
        msvcrt.getch()
    except ImportError:
        input()


def _run() -> None:
    if not PRIVATE_KEY_PATH.exists():
        print(f"ERROR: {PRIVATE_KEY_PATH} not found.")
        print("Run: python license_tool/generate_keypair.py")
        sys.exit(1)

    installation_id = input("Installations-ID des Kunden: ").strip()
    if not installation_id:
        print("ERROR: Installations-ID darf nicht leer sein.")
        sys.exit(1)

    print()
    print("Welches Feature soll freigeschaltet werden?")
    for num, name in FEATURES.items():
        print(f"  [{num}] {name.capitalize()}")
    choice = input("Auswahl: ").strip()

    feature = FEATURES.get(choice)
    if feature is None:
        print(f"ERROR: Ungültige Auswahl '{choice}'.")
        sys.exit(1)

    private_key = load_pem_private_key(PRIVATE_KEY_PATH.read_bytes(), password=None)
    key = generate_license(private_key, installation_id, feature)
    env_name = f"{feature.upper()}_LICENSE_KEY"

    print()
    print(f"# Lizenz-Key für installation_id={installation_id}, Feature={feature}")
    print(f"{env_name}={key}")


def main() -> None:
    try:
        _run()
    finally:
        # Runs on the success path and on every sys.exit(1) error path above
        # (finally still fires while a SystemExit is propagating) — the
        # window stays open either way, showing the key or the error.
        _pause()


if __name__ == "__main__":
    main()
