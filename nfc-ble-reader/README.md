# nfc-ble-reader

Battery-powered NFC wristband reader. Scans an ISO14443A tag's UID and pushes
it over Bluetooth LE to whichever central is listening (e.g. a POS tablet).

## Hardware

- **MCU:** nice!nano (nRF52840, Pro Micro form factor) - this is a clone
  board, not an official nice!nano; see `boards/`.
- **NFC reader:** PN532 breakout, SPI mode.

### Wiring

| PN532 pin | nice!nano pad |
|-----------|---------------|
| SCK       | P0.17         |
| MISO      | P0.22         |
| MOSI      | P0.20         |
| SS        | P0.24         |
| IRQ       | P1.04 (wired, not used by firmware yet) |
| VCC       | regulated 3.3V rail (not RAW - that's unregulated battery voltage) |
| GND       | GND           |
| RSTO      | not connected |

SPI runs on `NRF_SPIM2`, a separate peripheral from the board's default
`SPI` object (which owns the standard hardware SPI pins), so both can coexist.

## Firmware

`src/main.cpp`:

- Polls the PN532 for a tag every ~650ms (150ms search window). Between polls
  the PN532 is put into hardware Power Down mode and woken by the next SPI
  command - it draws ~100mA in Normal mode regardless of whether it's
  actively scanning, and only ~2-20uA in Power Down (NXP UM0701-02 §7.2.11),
  so this is what actually matters for battery life.
- On a new/changed UID, writes it to a BLE characteristic and notifies any
  connected central. The onboard LED flashes briefly.
- Advertises OTA DFU (`BLEDfu`) so firmware updates don't require USB after
  the first flash.

### Custom board definition

PlatformIO's `nordicnrf52` platform has no built-in `nicenano` board, so
`boards/nicenano.json` + `boards/variants/nicenano/` define one locally
(pin numbering is a straight passthrough: Arduino pin N = P0.N for N<32,
P1.(N-32) above that). Nothing outside this repo needs to change for this
to work - `board_build.variants_dir` in the board JSON points at the local
`boards/variants` folder.

### BLE GATT

| | UUID |
|---|---|
| NFC service | `822798f2-47a7-49b3-ac8b-216dced04e2a` |
| UID characteristic | `b2e70955-99db-43e3-9480-8ee014fc13ee` |

Custom, randomly generated UUIDs (not SIG-assigned). The characteristic
supports `Read` and `Notify`; the value is the raw tag UID bytes (4-7 bytes,
MSB first, as returned by `readPassiveTargetID`).

## Build & flash

```
pio run
```

**First flash** needs USB, since the stock bootloader has no OTA capability
until this firmware (with `BLEDfu`) is on the device:

1. Convert the build to UF2 (the bootloader's `uf2conv.py`, family `0xADA52840`):
   ```
   python <path-to-framework-arduinoadafruitnrf52>/tools/uf2conv/uf2conv.py \
     .pio/build/nicenano/firmware.hex -c -f 0xADA52840 \
     -o .pio/build/nicenano/firmware.uf2
   ```
2. Double-tap reset to enter the bootloader (drive `NICENANO` appears).
3. Copy `firmware.uf2` onto that drive.

**Every update after that** can go over BLE, no USB required:

```
python tools/ble_dfu/ble_dfu.py
```

Talks the bootloader's Legacy DFU-over-BLE protocol (service `0x1530`)
directly via `bleak` from the PC's own Bluetooth adapter - see
`tools/ble_dfu/` for details. Defaults to `.pio/build/nicenano/firmware.zip`
(produced automatically by `pio run` since `upload_protocol = nrfutil`).
