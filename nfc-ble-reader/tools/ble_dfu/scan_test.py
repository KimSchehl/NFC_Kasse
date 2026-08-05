#!/usr/bin/env python3
"""List every BLE advertisement bleak can see, for troubleshooting discovery issues."""

import asyncio

from bleak import BleakScanner


async def main():
    print("Scanning for 10 seconds...")
    devices = await BleakScanner.discover(timeout=10, return_adv=True)
    if not devices:
        print("No BLE devices found at all.")
        return
    for address, (device, adv) in devices.items():
        print(f"{address}  name={device.name!r} local_name={adv.local_name!r} rssi={adv.rssi} services={adv.service_uuids}")


if __name__ == "__main__":
    asyncio.run(main())
    input("\nPress Enter to exit...")
