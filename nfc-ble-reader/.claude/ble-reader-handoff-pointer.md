# BLE-NFC-Reader Integration — siehe Handoff-Doc im App-Repo

Ausführliche Zusammenfassung (behobene Root Causes, zwei offene Probleme,
geänderte Dateien in beiden Repos, praktische Hinweise) liegt in:

`NFC_Flutter_Project/.claude/ble-reader-handoff.md`

Enthält auch einen "System-Überblick"-Abschnitt (Hardware-Verkabelung, Firmware-
Architektur: BLE-Services/Advertising/Power-Management, App-Seite: BleReaderNotifier/
NfcInputField/Settings-Tab) — lohnt sich als Erstes zu lesen, bevor man sich den
Code selbst zusammensucht.

Kurzfassung Firmware-Seite (dieses Repo, `nfc-ble-reader/`):
- Pins in `src/main.cpp` an neue Verlötung angepasst, Battery-ADC-Code (P0.31)
  hinzugefügt und als korrekt verifiziert
- BLE-Advertising-Name-Fix (Scan-Response statt Advertising-Packet)
- `platformio.ini`: `[env:nicenano_0001]` mit `READER_SERIAL`-Build-Flag
- `tools/ble_dfu/ble_dfu.py`: Firmware-Pfad-Suche per Glob repariert,
  `--name`-Default korrigiert
- Serial-Diagnose-Logging für BLE-Connect/Disconnect/Pairing ergänzt
  (USB + `pio device monitor`, 115200 Baud)

Alles unstaged/uncommitted. Offene Probleme sind beide auf App-Seite
(`NFC_Flutter_Project`) — siehe Handoff-Doc dort für Details.
