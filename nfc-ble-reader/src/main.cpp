#include <bluefruit.h>
#include <SPI.h>
#include <Adafruit_PN532.h>

// PN532 wiring (SPI, custom pins - see project notes)
#define PN532_SCK PIN_011
#define PN532_MISO PIN_100
#define PN532_MOSI PIN_024
#define PN532_SS PIN_022
// IRQ (PIN_008) is wired but not used yet.

// Battery divider midpoint (2x 1MOhm) for analog voltage measurement.
#define BATTERY_SENSE_PIN PIN_031

#define LED_PIN 15

// Set per-device via `-D READER_SERIAL="0001"` build flag (see platformio.ini)
// so each physical reader advertises a distinct BLE name.
#ifndef READER_SERIAL
#define READER_SERIAL "0000"
#endif
#define READER_NAME "NFC-Reader_" READER_SERIAL

// Default `SPI` already owns the board's hardware SPI pins/peripheral, so the
// PN532 gets its own SPIClass instance on a separate peripheral (NRF_SPIM2).
SPIClass pn532SPI(NRF_SPIM2, PN532_MISO, PN532_SCK, PN532_MOSI);
Adafruit_PN532 nfc(PN532_SS, &pn532SPI);

// OTA DFU service - lets a phone/PC flash new firmware over BLE.
BLEDfu bledfu;

// Standard BLE Battery Service so apps can read the battery level directly.
BLEBas bleBas;

// Custom service: notifies the UID of whichever NFC tag was last scanned.
const uint8_t NFC_SERVICE_UUID[16] = {0x2a, 0x4e, 0xd0, 0xce, 0x6d, 0x21, 0x8b, 0xac,
                                       0xb3, 0x49, 0xa7, 0x47, 0xf2, 0x98, 0x27, 0x82};
const uint8_t NFC_UID_CHAR_UUID[16] = {0xee, 0x13, 0xfc, 0x14, 0xe0, 0x8e, 0x80, 0x94,
                                        0xe3, 0x43, 0xdb, 0x99, 0x55, 0x09, 0xe7, 0xb2};

BLEService nfcService(NFC_SERVICE_UUID);
BLECharacteristic nfcUidChar(NFC_UID_CHAR_UUID);

uint8_t lastUid[7];
uint8_t lastUidLength = 0;
uint8_t lastBatteryLevel = 0xFF;
uint32_t lastBatteryUpdateMs = 0;

float readBatteryVoltageMv() {
  analogReference(AR_INTERNAL_3_0);
  analogReadResolution(12);
  delay(1);

  uint16_t raw = analogRead(BATTERY_SENSE_PIN);

  analogReference(AR_DEFAULT);
  analogReadResolution(10);

  // The divider is 1:1, so the measured midpoint voltage is half the battery.
  return raw * (3000.0f / 4095.0f) * 2.0f;
}

uint8_t batteryMillivoltsToPercent(float millivolts) {
  if (millivolts < 3300.0f) {
    return 0;
  }

  if (millivolts < 3600.0f) {
    return (uint8_t)((millivolts - 3300.0f) / 30.0f);
  }

  float percent = 10.0f + ((millivolts - 3600.0f) * 0.15f);

  if (percent > 100.0f) {
    percent = 100.0f;
  }

  return (uint8_t)(percent + 0.5f);
}

uint8_t readBatteryLevelPercent() {
  float batteryMillivolts = readBatteryVoltageMv();
  return batteryMillivoltsToPercent(batteryMillivolts);
}

void updateBatteryService(bool force = false) {
  uint32_t now = millis();
  if (!force && (now - lastBatteryUpdateMs) < 60000UL) {
    return;
  }

  lastBatteryUpdateMs = now;
  uint8_t batteryLevel = readBatteryLevelPercent();

  if (force || batteryLevel != lastBatteryLevel) {
    lastBatteryLevel = batteryLevel;
    bleBas.write(batteryLevel);
  }
}

// Diagnostic-only: prints connection/security lifecycle over USB serial so a
// disconnect's actual HCI reason code (and how far pairing got) is visible
// instead of having to guess. Harmless if nothing is listening on the port.
void connect_callback(uint16_t conn_hdl) {
  BLEConnection* conn = Bluefruit.Connection(conn_hdl);
  char peerName[32] = {0};
  conn->getPeerName(peerName, sizeof(peerName));
  Serial.printf("[BLE] connected: handle=%u peer=\"%s\" bonded=%d\n", conn_hdl, peerName, conn->bonded());
}

void disconnect_callback(uint16_t conn_hdl, uint8_t reason) {
  // reason is a BLE_HCI_STATUS_CODE_* from ble_hci.h, e.g.
  // 0x08 = Connection Timeout, 0x13 = Remote User Terminated,
  // 0x16 = Local Host Terminated, 0x3D = Connection Failed to be Established,
  // 0x3E = MIC Failure (security/encryption mismatch).
  Serial.printf("[BLE] disconnected: handle=%u reason=0x%02X\n", conn_hdl, reason);
}

void sec_complete_callback(uint16_t conn_hdl, uint8_t auth_status) {
  // auth_status is a BLE_GAP_SEC_STATUS_* from ble_gap.h, e.g.
  // 0x00 = Success, 0x03 = MITM mismatch, 0x05 = Pairing not supported,
  // 0x08 = Unspecified reason, 0x0A = Repeated attempts.
  Serial.printf("[BLE] pairing complete: handle=%u auth_status=0x%02X\n", conn_hdl, auth_status);
}

void secured_callback(uint16_t conn_hdl) {
  Serial.printf("[BLE] link secured (encrypted): handle=%u\n", conn_hdl);
}

void startAdv(void) {
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(nfcService);

  // The 128-bit service UUID above already uses 18 of the 31 bytes available
  // in the advertising packet, leaving too little room for the full name
  // (it would get silently shortened to "NFC-R"). The scan response is a
  // separate 31-byte packet, so put the name there instead - phones doing
  // an active scan (the default) pick it up automatically.
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244); // in units of 0.625 ms
  Bluefruit.Advertising.setFastTimeout(30);   // seconds in fast mode
  Bluefruit.Advertising.start(0);             // 0 = advertise forever
}

void setup() {
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // Non-blocking: writes are silently dropped if no USB host has the CDC
  // port open, so this is safe to leave in for normal battery-only use.
  Serial.begin(115200);

  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName(READER_NAME);

  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);
  Bluefruit.Security.setPairCompleteCallback(sec_complete_callback);
  Bluefruit.Security.setSecuredCallback(secured_callback);

  // Must be added before startAdv() for OTA DFU to be advertised correctly
  bledfu.begin();

  bleBas.begin();

  analogReadResolution(12);
  updateBatteryService(true);

  nfcService.begin();

  nfcUidChar.setProperties(CHR_PROPS_NOTIFY | CHR_PROPS_READ);
  nfcUidChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  nfcUidChar.setMaxLen(7);
  nfcUidChar.begin();

  startAdv();

  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    // PN532 not found - flash fast forever so the failure is visible without a debugger.
    while (1) {
      digitalToggle(LED_PIN);
      delay(100);
    }
  }
  nfc.SAMConfig();

  // Default MxRtyPassiveActivation is 0xFF (retry forever) - without this the
  // RF field stays on internally hunting for a tag even after our own
  // readPassiveTargetID() timeout gives up on it, which is most of why this
  // was drawing 113mA continuously. Bound it to a few quick retries instead.
  nfc.setPassiveActivationRetries(3);
}

// PN532 draws ~100mA in Normal mode regardless of whether it's actively
// searching for a tag - Power Down mode cuts that to ~2-20uA (per NXP
// UM0701-02 7.2.11). WakeUpEnable = SPI bit (bit 5): any new SPI command
// (the next readPassiveTargetID call) wakes it back up automatically.
void pn532PowerDown() {
  uint8_t cmd[] = {PN532_COMMAND_POWERDOWN, 0x20};
  nfc.sendCommandCheckAck(cmd, sizeof(cmd));
}

void loop() {
  uint8_t uid[7];
  uint8_t uidLength;

  bool found = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 150);

  if (found) {
    bool isNewTag = (uidLength != lastUidLength) || memcmp(uid, lastUid, uidLength) != 0;
    if (isNewTag) {
      memcpy(lastUid, uid, uidLength);
      lastUidLength = uidLength;

      nfcUidChar.write(uid, uidLength);
      if (Bluefruit.connected() && nfcUidChar.notifyEnabled()) {
        nfcUidChar.notify(uid, uidLength);
      }

      digitalWrite(LED_PIN, HIGH);
      delay(100);
      digitalWrite(LED_PIN, LOW);
    }
  } else {
    lastUidLength = 0;
  }

  updateBatteryService();
  pn532PowerDown();
  delay(500); // PN532 is in Power Down for this whole window
}
