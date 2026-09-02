"""
Generates feature license keys for a customer installation.

Usage:
    python license_tool/generate_license.py <installation_id> <feature> [<feature> ...]

Example:
    python license_tool/generate_license.py 3f2a9c1e-... pager leaderboard

Prints one config.env-ready line per feature, e.g.:
    PAGER_LICENSE_KEY=eyJ2IjoxLCJ...
    LEADERBOARD_LICENSE_KEY=eyJ2IjoxLCJ...

`feature` can be any name — there's no fixed list to maintain here. It must
match exactly what backend/config.py checks for that feature (currently
"pager" and "leaderboard").

Requires private_key.pem next to this script — run generate_keypair.py once
first if it doesn't exist yet.
"""

import argparse
import base64
import json
import sys
from pathlib import Path

from cryptography.hazmat.primitives.serialization import load_pem_private_key

PRIVATE_KEY_PATH = Path(__file__).parent / "private_key.pem"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_license(private_key, installation_id: str, feature: str) -> str:
    payload = json.dumps(
        {"v": 1, "installation_id": installation_id, "feature": feature},
        separators=(",", ":"),
    ).encode("utf-8")
    signature = private_key.sign(payload)
    return f"{_b64(payload)}.{_b64(signature)}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("installation_id", help="The customer's INSTALLATION_ID (from their config.env)")
    parser.add_argument("features", nargs="+", help="One or more feature names to license, e.g. pager leaderboard")
    args = parser.parse_args()

    if not PRIVATE_KEY_PATH.exists():
        print(f"ERROR: {PRIVATE_KEY_PATH} not found.")
        print("Run: python license_tool/generate_keypair.py")
        sys.exit(1)

    private_key = load_pem_private_key(PRIVATE_KEY_PATH.read_bytes(), password=None)

    print(f"# License keys for installation_id={args.installation_id}")
    for feature in args.features:
        key = generate_license(private_key, args.installation_id, feature)
        env_name = f"{feature.upper()}_LICENSE_KEY"
        print(f"{env_name}={key}")


if __name__ == "__main__":
    main()
