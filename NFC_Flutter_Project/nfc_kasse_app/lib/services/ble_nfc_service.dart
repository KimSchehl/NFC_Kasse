import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT UUIDs for the nfc-ble-reader firmware (see nfc-ble-reader/README.md).
/// Custom, randomly generated UUIDs - not SIG-assigned.
class BleNfcService {
  static final nfcServiceUuid = Guid('822798f2-47a7-49b3-ac8b-216dced04e2a');
  static final uidCharUuid = Guid('b2e70955-99db-43e3-9480-8ee014fc13ee');

  // Standard BLE Battery Service - SIG-assigned, value is a single uint8 0-100.
  static final batteryServiceUuid = Guid('0000180f-0000-1000-8000-00805f9b34fb');
  static final batteryLevelCharUuid = Guid('00002a19-0000-1000-8000-00805f9b34fb');

  BleNfcService._();
}
