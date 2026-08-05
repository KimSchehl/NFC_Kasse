# BLE-NFC-Reader Integration — Handoff (Stand: 2026-08-05)

Ziel des Threads: den batteriebetriebenen nRF52840-NFC-Reader (Repo `nfc-ble-reader`,
Nachbarordner von `NFC_Flutter_Project`) per Bluetooth LE auch in der **Web-Version**
der Kasse (`backend/webapp`, im Browser auf einem Windows-11-Laptop) nutzbar machen —
zusätzlich zur nativen Android-App, wo es schon lief.

Kein einziger der unten genannten Codestände ist bisher committet — alles sind
Working-Tree-Änderungen in zwei Repos (`nfc-ble-reader`, `NFC_Flutter_Project`).

## Status: RESOLVED (2026-08-06). Beide unten genannten Probleme sind behoben, siehe
## Abschnitt "RESOLVED" am Ende dieser Datei statt "OFFENE PROBLEME".
## Dauerhafte Architektur-Notizen (Web-Reconnect-Einschränkung, Health-Check-Design)
## stehen jetzt in der Root-`CLAUDE.md` unter "BLE NFC reader" — diese Datei bleibt
## als historischer Debugging-Log stehen, ist aber nicht mehr die aktuelle Quelle.

---

## System-Überblick (damit man sich nicht alles zusammensuchen muss)

### Hardware

- **Board:** nice!nano-Klon (nRF52840, Pro-Micro-Formfaktor), lokal via
  `nfc-ble-reader/boards/nicenano.json` + `boards/variants/nicenano/variant.h`
  definiert (kein offizielles PlatformIO-Board). Pin-Makros dort: `PIN_0xx` = P0.xx,
  `PIN_1xx` = P1.(xx).
- **NFC-Chip:** PN532-Breakout, per SPI angebunden. Eigene `SPIClass`-Instanz auf
  `NRF_SPIM2` (das Default-`SPI`-Objekt belegt schon die Standard-Hardware-SPI-Pins).
- **Verkabelung** (User hat kürzlich neu verlötet, Pins wurden in diesem Thread
  entsprechend angepasst — siehe `README.md` für die aktuelle Tabelle):
  SCK=P0.11, MISO=P1.00, MOSI=P0.24, SS=P0.22, IRQ=P0.08 (verkabelt, aber von der
  Firmware noch nicht genutzt), Battery-Sense=P0.31.
- **Stromversorgung/Akku:** Spannungsteiler aus 2× 1 MOhm (1:1) von der Batteriespannung
  auf P0.31 (AIN7). Kein Akku-Lade-IC im Scope dieses Threads, nur die Messung.

### Firmware (`nfc-ble-reader/src/main.cpp`, Adafruit Bluefruit nRF52 Arduino Core)

- **`setup()`:** BLE-Stack starten (`Bluefruit.begin()` initialisiert intern auch
  Security/Bonding automatisch, siehe unten), drei BLE-Services registrieren, PN532
  initialisieren (busy-blinkt die LED, falls der PN532 nicht antwortet), Retry-Limit
  für Tag-Detection auf 3 setzen (Standard wäre "retry forever", zieht sonst
  durchgehend ~113 mA).
- **`loop()` (alle ~650 ms):** PN532 nach einem Tag fragen (150 ms Suchfenster) →
  bei neuer UID über die Custom-Characteristic notifyen + LED kurz blinken → danach
  PN532 explizit in Power-Down-Mode schicken (Normal-Mode zieht ~100 mA dauerhaft,
  Power-Down nur 2–20 µA) → alle 60 s zusätzlich den Batteriestand aktualisieren.
  Das ist der zentrale Stromspar-Trick des ganzen Designs — PN532 ist die meiste Zeit
  schlafen gelegt, nicht die BLE-Radio.
- **Drei BLE-Services, gleichzeitig aktiv:**
  1. **`BLEDfu`** — Standard-OTA-Update-Trigger-Service. Muss laut Bluefruit-Doku vor
     `startAdv()` registriert werden, damit OTA korrekt beworben wird. Der eigentliche
     Flash-Vorgang läuft dann über `tools/ble_dfu/ble_dfu.py` (Nordics *Legacy*
     DFU-over-BLE-Protokoll, Service `0x1530` — nicht das neuere Secure-DFU).
  2. **`BLEBas`** — Standard Battery Service (UUID `180f`/Level-Char `2a19`), Wert
     0–100 %, wird per `updateBatteryService()` geschrieben.
  3. **Custom NFC-Service** (zufällige 128-bit-UUIDs, siehe `README.md`) mit genau
     einer Characteristic, die die zuletzt gescannte UID roh (4–7 Bytes) per
     `Notify`+`Read` rausgibt. `SECMODE_OPEN` — bewusst keine Verschlüsselung
     vorausgesetzt (ändert aber nichts daran, dass Windows trotzdem OS-seitig pairen
     will, siehe Root Cause 4 unten).
- **Advertising-Aufteilung:** Flags + TX-Power + die 128-bit-Service-UUID füllen das
  31-Byte-Advertising-Paket fast komplett, deshalb liegt der Gerätename
  (`NFC-Reader_<READER_SERIAL>`, IDs 4-stellig wie `0001`) im separaten
  Scan-Response-Paket (`Bluefruit.ScanResponse.addName()`).
- **Bonding/Pairing** läuft automatisch über Bluefruit's `BLESecurity`-Klasse
  (`Just Works`, kein MITM, wird bei `Bluefruit.begin()` mitinitialisiert) — dafür
  ist **kein** eigener Code im Sketch nötig, das ist Bibliotheks-Default.
- **Multi-Geräte-Namensgebung:** `READER_SERIAL` wird als Build-Flag injiziert
  (`platformio.ini`, `[env:nicenano_0001]`), macht den BLE-Namen pro geflashter
  Einheit eindeutig. Für ein zweites Gerät: neuen `[env:nicenano_0002]`-Block mit
  eigenem `READER_SERIAL` ergänzen.
- **Diagnose-Callbacks** (in diesem Thread ergänzt, rein für USB-Serial-Debugging,
  kein Einfluss auf Normalbetrieb): loggen Connect/Disconnect (inkl. HCI-Reason-Code)
  und Pairing/Security-Status. Sichtbar nur mit angeschlossenem USB + `pio device
  monitor` — im Batteriebetrieb ohne USB-Host werden die `Serial.printf`-Aufrufe
  einfach verworfen, kein Blocking.

### App-Seite (Flutter, Riverpod)

- **`BleReaderNotifier`** (`providers.dart`, globaler `NotifierProvider`, nicht
  `.autoDispose` — lebt für die gesamte App-Laufzeit unabhängig von einzelnen
  Screens) ist die zentrale Instanz: Scannen (`FlutterBluePlus.startScan`, gefiltert
  auf die Custom-Service-UUID), Verbinden, GATT-Service-Discovery, Notify-
  Subscriptions für UID- und Battery-Characteristic, automatischer Reconnect bei
  Disconnect (5 s Delay), Persistierung der zuletzt gekoppelten Geräte-ID in
  `FlutterSecureStorage` (damit sie beim App-Start automatisch wiederverbunden wird).
- **`NfcInputField`**-Widget (in `pos_screen.dart` eingebettet) ist der gemeinsame
  Eingabepunkt für **drei** UID-Quellen: USB-HID-Tastatur-Emulation (Enter/Return am
  Ende erkennen), native Android-NFC (`NfcService`), und jetzt eben BLE
  (`ref.listen(bleReaderProvider, ...)` auf den `lastUidSeq`-Zähler, damit auch
  zweimal hintereinander dieselbe UID zuverlässig triggert).
- **Settings-Screen** hat einen dritten Tab "NFC-Lesegerät" (`_BleTab`/
  `_BleScanList` in `settings_screen.dart`) zum Suchen/Koppeln/Trennen/Vergessen
  eines Readers, inkl. Live-Akkustand-Anzeige (Punkt B der offenen Probleme).
- **Plattform-Unterschied:** `flutter_blue_plus` ist ein föderiertes Plugin — auf
  Android läuft es nativ, im Browser über `flutter_blue_plus_web` (kapselt die
  Web-Bluetooth-API des Browsers). Deren Verhalten unterscheidet sich relevant:
  Windows verlangt OS-Pairing (Android nicht), `permission_handler` existiert im
  Web nicht wirklich, und der Browser braucht einen secure context — alles unten
  unter "Chronologie" im Detail.

---

---

## Chronologie / behobene Root Causes

1. **BLE-Devicename nur 5 Zeichen ("NFC-R") auf dem Handy sichtbar**
   Ursache: 128-bit Service-UUID + Flags + TX-Power füllten das 31-Byte-Advertising-Paket
   fast komplett, für den Namen blieben nur 5 Zeichen (Bluefruit kürzt automatisch).
   Fix: Name in `Bluefruit.ScanResponse.addName()` statt `Bluefruit.Advertising.addName()`
   verschoben (separates 31-Byte-Paket) — `nfc-ble-reader/src/main.cpp`.

2. **Windows-Laptop fand den Reader im Browser gar nicht**
   Web Bluetooth (`navigator.bluetooth`) braucht einen *secure context* (HTTPS oder
   `localhost`). Backend läuft nur über HTTP auf der LAN-IP → kein secure context.
   Workaround (aktuell genutzt, kein Server-Umbau): Edge/Chrome-Flag
   `edge://flags/#unsafely-treat-insecure-origin-as-secure` mit der **exakten**
   aktuellen LAN-IP des Kassensystem-PCs eintragen (z. B. `http://10.42.1.94:8000`),
   Dropdown auf **Enabled**, Browser komplett neu starten.
   ⚠️ **Das Flag ist an die exakte Origin gebunden.** Ändert sich die LAN-IP (DHCP!),
   muss das Flag neu gesetzt werden — ist im Thread schon einmal passiert. Langfristige
   Lösung wäre eine feste IP/Hostname für den Kassensystem-PC oder echtes HTTPS
   (z. B. mkcert + Reverse Proxy) — noch nicht umgesetzt, nur besprochen.

3. **`permission_handler` wirft auf Web** (`Permission.bluetoothScan` etc. sind
   Android-Konzepte, keine Web-Implementierung vorhanden) → Absturz sofort beim Klick
   auf "Nach Geräten suchen".
   Fix: `BleReaderNotifier.startScan()` in `providers.dart` überspringt
   `_ensurePermissions()` jetzt mit `if (!kIsWeb) { ... }`.

4. **Windows verlangt OS-Pairing für JEDE GATT-Verbindung** (anders als
   Android/macOS/Linux/iOS), unabhängig davon, dass die Firmware ihre Characteristics
   bewusst offen (`SECMODE_OPEN`) deklariert. Das ist eine bekannte Chromium/Windows-
   Einschränkung, keine Firmware-Lücke — Bonding lief schon vorher automatisch über
   Adafruits `BLESecurity`-Klasse (siehe `Bluefruit.begin()` → `Security.begin()`,
   Datei `.platformio/packages/framework-arduinoadafruitnrf52/.../BLESecurity.cpp`).
   Zum Debuggen wurden in `main.cpp` Serial-Diagnose-Callbacks ergänzt
   (`connect_callback`, `disconnect_callback`, `sec_complete_callback`,
   `secured_callback`) — printen HCI-Disconnect-Reason-Codes & Auth-Status über USB
   (115200 Baud, `pio device monitor`). Damit wurde verifiziert: Pairing lief
   erfolgreich (`auth_status=0x00`), der kurze Disconnect direkt danach
   (`reason=0x13`, Remote User Terminated) war **normales** Verhalten des
   Windows-"Add a device"-Pairing-Flows (verbindet kurz zum Bonden, trennt dann
   bewusst selbst) — kein Bug.
   Zusätzlich musste in Windows-Einstellungen → Bluetooth & devices → Devices →
   "**Bluetooth devices discovery**" von "Default" auf "**Advanced**" gestellt werden,
   sonst listete Windows den Reader gar nicht zum Pairen.

5. **Stale Flutter-Web-Plugin-Registrant** — der eigentliche Hauptgrund, warum es
   lange nach nichts aussah: `.dart_tool/flutter_build/*/web_plugin_registrant.dart`
   wurde nie neu generiert, seit `flutter_blue_plus`/`permission_handler` zu
   `pubspec.yaml` hinzugefügt wurden (der Cache-Key hat die neuen Plugins nicht
   erkannt). Dadurch registrierte sich `FlutterBluePlusWeb` im Browser nie —
   `FlutterBluePlusPlatform.instance` blieb `null` → `UnsupportedError:
   flutter_blue_plus is unsupported on this platform`, ganz ohne Build-Fehler.
   Fix: `flutter clean && flutter pub get` vor dem Web-Build erzwingt Neugenerierung.
   `NFC_Flutter_Project/build_and_deploy.bat` macht das jetzt **automatisch** vor
   jedem Build (neuer Schritt "2b. Clean").

Nach Fix 1–5: Reader lässt sich im Browser über den "Nach Geräten suchen"-Button
finden, verbinden, bleibt stabil verbunden, UID-Scans kommen im NFC-Eingabefeld an.

---

## RESOLVED (Folgesession, 2026-08-06)

### A. "Bad state: Cannot use 'ref' after the widget was disposed."

Der `pos_screen.dart`-Guard war tatsächlich schon korrekt (verifiziert gegen den
`flutter_riverpod`-Quellcode). Die vom User erneut gemeldeten Fehler waren **drei
separate, echte Bugs**, gefunden über einen source-mapped Web-Build
(`build_and_deploy.bat` jetzt mit `--source-maps`) statt Rätselraten an minifizierten
Stacktraces:

1. Dasselbe Anti-Pattern (`ref.read`/`setState` nach `await` ohne `mounted`-Check) an
   8 weiteren Stellen projektweit, am kritischsten `cart_panel.dart` (`_book`/
   `_printAndBook`, der Buchen-Button). Bei `cart_panel.dart` und
   `cancel_booking_dialog.dart` (wo schon Geld serverseitig bewegt wurde, bevor der
   Fehler auftreten kann) wurden die betroffenen Notifier vor dem `await` eingefangen
   statt einfach früh zurückzukehren, damit Cart/Customer/Buchungs-State trotzdem
   konsistent bleibt.
2. `_BleScanListState.dispose()` in `settings_screen.dart` rief `ref.read(...)` frisch
   beim Dispose auf — sicher aussehend, aber wenn der komplette Screen in einem Rutsch
   verschwindet (Navigation via `switch`-Widget-Swap), betrachtet Riverpod `ref` schon
   vor Ausführung von `dispose()` als ungültig. Fix: Notifier in `initState()` einfangen.

Alle Details/Muster jetzt in der Root-`CLAUDE.md` unter "BLE NFC reader" bzw. bei den
jeweiligen Commit-Diffs — nicht hier dupliziert.

### B. Akkustand wurde in der Webapp nicht angezeigt

Ursache: Web Bluetooth erlaubt `discoverServices()` nur Zugriff auf Services, die beim
`requestDevice()`-Aufruf explizit erlaubt wurden. Der Custom-NFC-Service war über den
Scan-Filter automatisch erlaubt, der Battery Service nie — `discoverServices()` gab ihn
auf Web kommentarlos leer zurück (kein Error). Fix: `webOptionalServices:
[BleNfcService.batteryServiceUuid]` bei `FlutterBluePlus.startScan(...)` ergänzt.

**Danach aufgetretene Folgeprobleme** (gleicher Test-Fix-Zyklus, alle behoben):
- Reconnect über gespeicherte Geräte-ID (`BluetoothDevice.fromId(id)`) funktioniert auf
  Web grundsätzlich nie — Web Bluetooth kann eine reine ID nie zu einem verbindbaren
  Handle auflösen, nur `requestDevice()` selbst tut das. Cold-Start-Restore und der
  ⋮-Menü-"Verbinden"-Button verzweigen jetzt auf `kIsWeb` (zeigen nur Status / lösen
  einen Scan statt Direct-Connect aus).
- `flutter_blue_plus_web` meldet nie einen *externen* Disconnect (Reader ausgeschaltet)
  — nur einen, den die App selbst auslöst. Ein aktiver Health-Check-Workaround
  (periodisches `read()`) verursachte dabei zwei neue Bugs: (a) `read()` und `notify`
  teilen sich denselben `onValueReceived`-Stream, wodurch der periodische Read den
  zwischengespeicherten letzten UID-Wert als Phantom-Scan erneut ins Eingabefeld lud;
  (b) ein extern hängender Browser-Call gibt den pro-Gerät-Mutex von
  `flutter_blue_plus` nie frei, wodurch ein externes `.timeout()` zwar den eigenen Code
  aufgeben lässt, aber alle folgenden Operationen (inkl. Reconnect) auf diesem Gerät für
  den Rest der Seiten-Session dauerhaft blockiert. Finale Lösung: rein passiver
  Health-Check, der nur vergleicht, wie lange das letzte (ohnehin alle ~60s von der
  Firmware gesendete) Battery-Notify her ist — keine eigene GATT-Operation, kein
  Mutex-Risiko.

---

## Geänderte Dateien (beide Repos, alles unstaged)

**`nfc-ble-reader/`** (Firmware + Tools):
- `src/main.cpp` — Pin-Remap (User hat neu verlötet), Battery-ADC-Code (P0.31,
  2x-1MOhm-Teiler, Kurve 0%@<3.3V → 10%@3.6V → 100%@4.2V — Kalkulation wurde als
  korrekt verifiziert, einziger Hinweis: hohe Quellimpedanz des Teilers ggf. mal
  gegen Multimeter prüfen), BLE Battery Service, Scan-Response-Name-Fix,
  Connect/Disconnect/Security-Diagnose-Logging über Serial
- `platformio.ini` — `[env]`-Shared-Config + `[env:nicenano_0001]` mit
  `READER_SERIAL` Build-Flag (Multi-Geräte-Vorbereitung)
- `tools/ble_dfu/ble_dfu.py` — `find_default_package()` sucht jetzt per Glob über
  alle `.pio/build/*/firmware.zip` (statt hartkodiert `nicenano/`); `--name`-Default
  auf `NFC-Reader_0001` korrigiert (Firmware wirbt jetzt `NFC-Reader_<SERIAL>` statt
  `nfc-ble-reader`)
- `README.md` — Wiring-Tabelle, Pfade, BLE-GATT-Doku aktualisiert

**`NFC_Flutter_Project/`** (App):
- `nfc_kasse_app/lib/services/ble_nfc_service.dart` — **neu**, GATT-UUID-Konstanten
- `nfc_kasse_app/lib/providers/providers.dart` — `BleReaderNotifier`/`BleReaderState`
  (Scan/Connect/Reconnect/GATT-Subscriptions), `kIsWeb`-Guard um `_ensurePermissions()`
- `nfc_kasse_app/lib/screens/settings_screen.dart` — neuer Tab "NFC-Lesegerät"
  (`_BleTab`, `_BleScanList`)
- `nfc_kasse_app/lib/screens/pos_screen.dart` — `mounted`-Guard-Fix (offenes Problem A)
- `nfc_kasse_app/lib/widgets/nfc_input_field.dart` — dritter Input-Pfad neben
  USB-HID/Native-NFC: BLE-Scan via `ref.listen(bleReaderProvider, ...)`
- `nfc_kasse_app/lib/services/nfc_service.dart` — kleines Refactoring
  (`bytesToUidHex`-Helper ausgelagert nach `utils/formatters.dart`)
- `nfc_kasse_app/pubspec.yaml` — `flutter_blue_plus: ^2.3.11`,
  `permission_handler: ^13.0.0`
- `build_and_deploy.bat` — neuer Schritt "2b. Clean" (immer `flutter clean` +
  `flutter pub get` vor dem Bauen, behebt/verhindert Root-Cause 5 oben)

Nicht von mir verändert, aber `git status` zeigt sie als modifiziert (vermutlich
User selbst, vor diesem Thread): `android/app/build.gradle.kts`,
`AndroidManifest.xml`, `main_shell.dart`, `formatters.dart`, `pubspec.lock`.

---

## Praktische Hinweise für die nächste Session

- **Deploy-Workflow (Web):** `NFC_Flutter_Project\build_and_deploy.bat` → Option
  `3` (Nur Web App) → baut automatisch clean → kopiert nach `backend\webapp\` →
  **Backend danach neu starten** (`start_backend.bat`), sonst liefert es alte Dateien.
- **Firmware flashen:** `python nfc-ble-reader/tools/ble_dfu/ble_dfu.py` (OTA über
  BLE, kein USB nötig). Für einen Rebuild: `pio run -e nicenano_0001` im
  `nfc-ble-reader`-Ordner.
- **Firmware-Diagnose:** Reader per USB anschließen, `pio device monitor`
  (115200 Baud) — zeigt jetzt Connect/Disconnect/Pairing-Events mit HCI-Reason-Codes.
- **Browser-Fehler debuggen:** DevTools → Console-Tab (nicht Sources!). Release-Builds
  sind minifiziert, `Uncaught Error` zeigt oft keine Message — Workaround, der sich
  in diesem Thread bewährt hat:
  ```js
  window.addEventListener('error', e => console.log('ERR:', e.error?.message, '||', e.error?.stack));
  window.addEventListener('unhandledrejection', e => console.log('REJECTION:', e.reason?.message, e.reason));
  ```
  Danach die Aktion auslösen, die den Fehler produziert.
- **Edge-Flag bei IP-Wechsel:** `edge://flags/#unsafely-treat-insecure-origin-as-secure`
  neu setzen, wenn sich die LAN-IP des Kassensystem-PCs ändert (siehe Root Cause 2).
