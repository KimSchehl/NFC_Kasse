#!/usr/bin/env python3
"""Flash a Nordic/Adafruit nRF52 DFU .zip package over BLE from a PC.

Usage:
    python ble_dfu.py <firmware.zip> [--name nfc-ble-reader] [--timeout 20]

Requires the target to be running a sketch with Adafruit's BLEDfu ("legacy
DFU trigger") service, or to already be sitting in the DFU bootloader. This
board's bootloader implements Nordic's *legacy* DFU-over-BLE profile (service
0x1530) rather than the newer Secure DFU (0xFE59) - confirmed by dumping its
GATT table while sitting in bootloader mode. Talks that protocol directly via
bleak - no phone, no dongle.
"""

import argparse
import asyncio
import json
import sys
import zipfile
from pathlib import Path

from bleak import BleakClient, BleakScanner

# Default location produced by `pio run` for this project, so the script can
# just be double-clicked in Explorer without passing a path on the command line.
DEFAULT_PACKAGE = Path(__file__).resolve().parents[2] / ".pio" / "build" / "nicenano" / "firmware.zip"

# Legacy Nordic DFU service - used BOTH by BLEDfu in the running app (just to
# trigger a reboot into the bootloader) AND by the bootloader itself (to
# actually receive the firmware). Same UUIDs, two very different behaviors
# depending on which side is currently running.
LEGACY_DFU_SERVICE_UUID = "00001530-1212-efde-1523-785feabcd123"
LEGACY_DFU_CONTROL_UUID = "00001531-1212-efde-1523-785feabcd123"
LEGACY_DFU_PACKET_UUID = "00001532-1212-efde-1523-785feabcd123"
START_DFU = bytes([0x01])

OP_START_DFU = 0x01
OP_INITIALIZE_DFU = 0x02
OP_RECEIVE_FIRMWARE_IMAGE = 0x03
OP_VALIDATE_FIRMWARE_IMAGE = 0x04
OP_ACTIVATE_FIRMWARE_RESET = 0x05
OP_PKT_RCPT_NOTIF_REQ = 0x08
OP_RESPONSE = 0x10
PKT_RCPT_NOTIF = 0x11
PRN_INTERVAL = 512  # empirically the largest interval that still completes reliably; 10000 (effectively unpaced) stalled

IMG_TYPE_APPLICATION = 0x04
INIT_PACKET_START = 0x00
INIT_PACKET_COMPLETE = 0x01

RESULT_SUCCESS = 0x01
RESULT_NAMES = {
    0x02: "Invalid state",
    0x03: "Not supported",
    0x04: "Data size exceeds limit",
    0x05: "CRC error",
    0x06: "Operation failed",
}

DEFAULT_CHUNK = 20  # ATT_MTU(23) - 3 byte header, safe fallback without MTU negotiation


def load_package(zip_path: Path):
    with zipfile.ZipFile(zip_path) as zf:
        manifest = json.loads(zf.read("manifest.json"))
        app = manifest["manifest"]["application"]
        init_data = zf.read(app["dat_file"])
        bin_data = zf.read(app["bin_file"])
    return init_data, bin_data


class DfuError(RuntimeError):
    pass


class LegacyDfuClient:
    """Nordic legacy DFU-over-BLE (service 0x1530), as used by the Adafruit
    nRF52 bootloader. Simpler than Secure DFU: no per-object CRC handshake -
    the bootloader just tracks byte counts against the size it was told
    upfront and acks once each phase (init packet / image) is complete."""

    def __init__(self, client: BleakClient, chunk_size: int):
        self.client = client
        self.chunk_size = chunk_size
        self._waiter: asyncio.Future | None = None
        self._receipts: asyncio.Queue | None = None

    async def start(self):
        self._receipts = asyncio.Queue()
        await self.client.start_notify(LEGACY_DFU_CONTROL_UUID, self._on_notify)

    def _on_notify(self, _handle, data: bytearray):
        data = bytes(data)
        if not data:
            return
        if data[0] == OP_RESPONSE:
            if self._waiter and not self._waiter.done():
                self._waiter.set_result(data)
        elif data[0] == PKT_RCPT_NOTIF:
            self._receipts.put_nowait(data)

    def _arm(self):
        """Create the response future BEFORE writing the opcode that triggers
        it, so a fast reply can't race ahead of us starting to wait for it."""
        self._waiter = asyncio.get_running_loop().create_future()

    async def _write_control(self, opcode: int, payload: bytes = b""):
        await self.client.write_gatt_char(
            LEGACY_DFU_CONTROL_UUID, bytes([opcode]) + payload, response=True
        )

    async def _write_data(self, data: bytes):
        for i in range(0, len(data), self.chunk_size):
            await self.client.write_gatt_char(
                LEGACY_DFU_PACKET_UUID, data[i : i + self.chunk_size], response=False
            )

    async def _expect(self, opcode: int, timeout: float = 15):
        data = await asyncio.wait_for(self._waiter, timeout=timeout)
        if len(data) < 3 or data[1] != opcode:
            raise DfuError(f"Unexpected response {data.hex()} waiting for opcode {opcode:#x}")
        result = data[2]
        if result != RESULT_SUCCESS:
            raise DfuError(f"Opcode {opcode:#x} failed: {RESULT_NAMES.get(result, hex(result))}")

    async def send(self, init_data: bytes, app_data: bytes):
        # START_DFU: response only arrives after the size packet that follows it.
        self._arm()
        await self._write_control(OP_START_DFU, bytes([IMG_TYPE_APPLICATION]))
        # SoftDevice size, Bootloader size, Application size (app-only update, so only the last matters)
        await self._write_data(bytes(8) + len(app_data).to_bytes(4, "little"))
        await self._expect(OP_START_DFU)

        # INITIALIZE_DFU: "start" has no response; only "complete" does.
        await self._write_control(OP_INITIALIZE_DFU, bytes([INIT_PACKET_START]))
        await self._write_data(init_data)
        self._arm()
        await self._write_control(OP_INITIALIZE_DFU, bytes([INIT_PACKET_COMPLETE]))
        await self._expect(OP_INITIALIZE_DFU)

        # Ask for a receipt every PRN_INTERVAL packets so we can throttle writes to
        # what the link actually drains, instead of flooding write-without-response
        # faster than the radio can carry it (which silently drops data - the
        # bootloader then waits forever for bytes that never arrived). Per the
        # bootloader's own source (ble_dfu.c), this request is fire-and-forget -
        # it is never acknowledged, even when accepted, so don't wait for one.
        while not self._receipts.empty():
            self._receipts.get_nowait()
        await self._write_control(OP_PKT_RCPT_NOTIF_REQ, PRN_INTERVAL.to_bytes(2, "little"))

        # RECEIVE_FIRMWARE_IMAGE: response only arrives once all app_size bytes have landed.
        self._arm()
        await self._write_control(OP_RECEIVE_FIRMWARE_IMAGE)
        sent = 0
        packet_count = 0
        paced = True
        for i in range(0, len(app_data), self.chunk_size):
            chunk = app_data[i : i + self.chunk_size]
            await self.client.write_gatt_char(LEGACY_DFU_PACKET_UUID, chunk, response=False)
            sent += len(chunk)
            packet_count += 1
            if sent % 4096 < self.chunk_size:
                print(f"  {sent}/{len(app_data)} bytes")
            if paced and packet_count % PRN_INTERVAL == 0:
                try:
                    await asyncio.wait_for(self._receipts.get(), timeout=10)
                except asyncio.TimeoutError:
                    print("  (no receipt notification, continuing unpaced)")
                    paced = False
        await self._expect(OP_RECEIVE_FIRMWARE_IMAGE, timeout=60)
        print(f"  {len(app_data)}/{len(app_data)} bytes")

        self._arm()
        await self._write_control(OP_VALIDATE_FIRMWARE_IMAGE)
        await self._expect(OP_VALIDATE_FIRMWARE_IMAGE)

        # Device applies the update and reboots. Per the bootloader source, it
        # closes the BLE connection itself as the *first* step of activating,
        # before persisting the "app is valid" flag to flash - so this write can
        # legitimately race-fail the same way the initial bootloader-entry trigger
        # did. Use write-WITH-response for the best chance of delivery, but don't
        # treat a failure here as fatal.
        try:
            await self._write_control(OP_ACTIVATE_FIRMWARE_RESET)
        except Exception as e:
            print(f"  (activate write reported as failed, likely just the reset race: {e})")
        # Give the bootloader time to persist the flag and reset before we
        # tear down the connection ourselves.
        await asyncio.sleep(3)


async def trigger_bootloader(name: str, timeout: float):
    print(f"Scanning for '{name}' (running app)...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, adv: (d.name or "") == name or ((adv.local_name or "") == name),
        timeout=timeout,
    )
    if device is None:
        return None

    print(f"Found {device.address}, requesting reboot into bootloader...")
    async with BleakClient(device) as client:
        # The device's write-authorize callback rejects the trigger unless the
        # control characteristic's CCCD is configured (notifications enabled),
        # even though it never actually sends a notification back.
        await client.start_notify(LEGACY_DFU_CONTROL_UUID, lambda _h, _d: None)
        try:
            await client.write_gatt_char(LEGACY_DFU_CONTROL_UUID, START_DFU, response=True)
        except Exception as e:
            # The device disconnects itself the instant it accepts this write
            # (that's the whole point), which usually races the ATT response
            # on Windows and surfaces as a spurious write failure here even
            # though the reboot-into-bootloader already happened on-device.
            print(f"  (write reported as failed, likely just the reboot race: {e})")
    return device.address


async def find_bootloader(prior_address: str | None, timeout: float):
    print("Scanning for DFU bootloader...")

    def matches(d, adv):
        if prior_address and d.address == prior_address:
            return True
        return LEGACY_DFU_SERVICE_UUID in [u.lower() for u in (adv.service_uuids or [])]

    device = await BleakScanner.find_device_by_filter(matches, timeout=timeout)
    return device


async def run(zip_path: Path, name: str, timeout: float):
    init_data, bin_data = load_package(zip_path)
    print(f"Loaded package: init packet {len(init_data)} bytes, firmware {len(bin_data)} bytes")

    prior_address = await trigger_bootloader(name, timeout)
    if prior_address:
        await asyncio.sleep(2)  # let the device actually reboot before rescanning

    device = await find_bootloader(prior_address, timeout)
    if device is None:
        print("Could not find the device in bootloader/DFU mode.", file=sys.stderr)
        print("Double-tap reset on the board and try again.", file=sys.stderr)
        return 1

    print(f"Connecting to bootloader at {device.address}...")
    async with BleakClient(device) as client:
        # 20B works; both 40B and 128B stalled on the very first receipt
        # notification. That's consistent with this old SDK11 softdevice never
        # negotiating a bigger ATT MTU at all (default MTU 23 => exactly 20B
        # usable payload) - anything past that is dropped at the link, not the
        # bootloader's own receive logic. So the chunk size is a hard ceiling,
        # not tunable; only PRN_INTERVAL is worth adjusting for speed.
        chunk_size = DEFAULT_CHUNK
        print(f"Using {chunk_size}-byte write chunks")

        dfu = LegacyDfuClient(client, chunk_size)
        await dfu.start()

        print("Sending init packet + firmware image...")
        await dfu.send(init_data, bin_data)

    print("Done. Device should now reboot into the new firmware.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "package",
        type=Path,
        nargs="?",
        default=DEFAULT_PACKAGE,
        help=f"Path to the DFU .zip package (default: {DEFAULT_PACKAGE})",
    )
    parser.add_argument("--name", default="nfc-ble-reader", help="BLE advertising name of the running app")
    parser.add_argument("--timeout", type=float, default=20.0, help="BLE scan timeout in seconds")
    args = parser.parse_args()

    if not args.package.exists():
        print(f"No such file: {args.package}", file=sys.stderr)
        print("Build the firmware first (pio run), or pass an explicit path.", file=sys.stderr)
        return 1

    try:
        return asyncio.run(run(args.package, args.name, args.timeout))
    except DfuError as e:
        print(f"DFU failed: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    try:
        exit_code = main()
    except SystemExit as e:
        exit_code = e.code
    input("\nPress Enter to exit...")
    sys.exit(exit_code)
