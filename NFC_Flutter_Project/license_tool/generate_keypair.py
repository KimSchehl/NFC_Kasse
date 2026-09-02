"""
One-time setup: generates the Ed25519 signing keypair for feature license
keys (PAGER, LEADERBOARD, ...).

Run once:
    python license_tool/generate_keypair.py

Writes private_key.pem next to this script (NEVER commit it — it's what
lets you sign valid license keys; anyone who has it can generate licenses
for any installation). Prints the PUBLIC key, which you paste into
backend/licensing.py's PUBLIC_KEY_B64 constant once — that's the only half
that ships with the software.

Refuses to overwrite an existing private_key.pem without --force, since
regenerating it invalidates every license key issued so far.
"""

import argparse
import base64
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

PRIVATE_KEY_PATH = Path(__file__).parent / "private_key.pem"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite an existing private_key.pem (invalidates all previously issued licenses)",
    )
    args = parser.parse_args()

    if PRIVATE_KEY_PATH.exists() and not args.force:
        print(f"ERROR: {PRIVATE_KEY_PATH} already exists.")
        print("Regenerating it would invalidate every license key issued so far.")
        print("Pass --force if you really mean to replace it.")
        raise SystemExit(1)

    private_key = Ed25519PrivateKey.generate()
    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    PRIVATE_KEY_PATH.write_bytes(private_bytes)

    public_bytes = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    public_b64 = base64.urlsafe_b64encode(public_bytes).rstrip(b"=").decode("ascii")

    print(f"Private key written to: {PRIVATE_KEY_PATH}")
    print("Keep it safe and never commit it — back it up somewhere durable.")
    print()
    print("Paste this into backend/licensing.py's PUBLIC_KEY_B64:")
    print()
    print(f'PUBLIC_KEY_B64 = "{public_b64}"')


if __name__ == "__main__":
    main()
