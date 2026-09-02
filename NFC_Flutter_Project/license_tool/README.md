# License Tool

Generates feature license keys (PAGER, LEADERBOARD, ...) for customer
installations. Lives outside `backend/` on purpose — it's never bundled
into the frozen backend build (`packaging/pyinstaller/nfc_kasse_backend.spec`
only points at `backend/service_main.py`), and it holds the private signing
key, which must never reach a customer's machine.

## One-time setup

```
pip install cryptography   # already installed if you've set up backend/requirements.txt
python license_tool/generate_keypair.py
```

Writes `private_key.pem` next to this README (gitignored — **never commit
it**, back it up somewhere durable instead; losing it means you can never
issue a valid license again, and leaking it means anyone can forge one) and
prints the matching public key. That public key is already baked into
`backend/licensing.py`'s `PUBLIC_KEY_B64` constant — you only need to run
this again (with `--force`) if you deliberately want to invalidate every
license issued so far and start over.

## Issuing a license

1. Ask the customer for their `INSTALLATION_ID` (a line in their
   `config.env`, generated automatically on first install).
2. Run:
   ```
   python license_tool/generate_license.py <installation_id> pager leaderboard
   ```
   (list whichever features they bought — any name works, it just has to
   match what `backend/config.py` checks for, currently `pager` and
   `leaderboard`.)
3. Send them the printed `..._LICENSE_KEY=...` lines. They paste those into
   their `config.env` alongside the matching `PAGER=true`/`LEADERBOARD=true`
   flags, then restart the service — both the flag and a valid key for that
   exact `INSTALLATION_ID` are required for a feature to actually turn on.

A license is permanently tied to one `installation_id` — it does nothing on
any other installation, and stops working entirely if that installation's
`INSTALLATION_ID` in `config.env` is ever changed (it isn't meant to be;
only regenerated automatically on first install, alongside `SECRET_KEY`).

## How it works

Each key is `base64url(payload) + "." + base64url(signature)`, where
`payload` is `{"v": 1, "installation_id": "...", "feature": "..."}` and
`signature` is an Ed25519 signature over the payload bytes. Verification
(`backend/licensing.py`) only ever needs the *public* key, so it's safe to
ship with every install — forging a key requires the private key, which
never leaves this folder.
