# Delete Tool

**Developer test tool only.** Never ship it or hand it to a customer: for
traceability a customer must not delete Veranstalter or Feste. It is
deliberately not mentioned in CLAUDE.md, the project README or the manuals.

Deletes a whole **Veranstalter** (users, rights, categories, articles, chips,
every Fest and Intern) or a single **ended Fest** (its sales, top-ups,
Tagesabschluss periods, pagers, bons, leaderboard opt-ins) from the server's
database. Not part of the installer and not reachable over HTTP — run it on
the server by hand.

## Usage

Double-click `loeschen.bat` (or `loeschen.bat --data-dir "D:\path\NFC-Kasse"`).
On first run it asks for admin rights, installs Python 3.13 via winget if
missing and creates its own `.venv` with `questionary` (arrow-key menus).
Default data folder (its `config.env` holds `DATABASE_URL`): `C:\ProgramData\NFC-Kasse`.

1. If the `NfcKasseBackend` service runs, the tool offers to stop it and
   starts it again on exit (devices are offline meanwhile).
2. Choose *Einzelnes Fest* or *Veranstalter komplett*, then the entry.
3. Read the summary, type the exact name, confirm once more.
4. A backup `backups\vor-loeschen_<time>_<name>.db` is written first; restore
   it in the admin tool if something went wrong. These backups are never
   pruned automatically.

## Rules

- The running Fest and Intern cannot be deleted (end the Fest in the admin
  tool first).
- The active Veranstalter and the last remaining one cannot be deleted
  (switch Veranstalter in the admin tool first).
- Deleting a Fest leaves chip balances and Pfand untouched — they belong to
  the Veranstalter. Deleting a Veranstalter warns about open balances.
- Everything runs in one exclusive transaction that ends with
  `PRAGMA foreign_key_check`; any leftover reference rolls it back.

Logic: `purge.py` (tested in `backend/tests/test_delete_tool.py`), menus:
`delete_tool.py`. After a schema change that adds a table referencing
`event`, `user`, `customer`, `category` or `product`, add it to `purge.py`
— the foreign key check (and `test_delete_tool.py`) will fail otherwise.
