#include <bluefruit.h>
#include <SPI.h>
#include <Adafruit_PN532.h>

// PN532 wiring (SPI, custom pins - see project notes)
#define PN532_SCK PIN_017
#define PN532_MISO PIN_022
#define PN532_MOSI PIN_020
#define PN532_SS PIN_024
// IRQ (PIN_104) is wired but not used yet.

#define LED_PIN 15

// Default `SPI` already owns the board's hardware SPI pins/peripheral, so the
// PN532 gets its own SPIClass instance on a separate peripheral (NRF_SPIM2).
SPIClass pn532SPI(NRF_SPIM2, PN532_MISO, PN532_SCK, PN532_MOSI);
Adafruit_PN532 nfc(PN532_SS, &pn532SPI);

// OTA DFU service - lets a phone/PC flash new firmware over BLE.
BLEDfu bledfu;

// Custom service: notifies the UID of whichever NFC tag was last scanned.
const uint8_t NFC_SERVICE_UUID[16] = {0x2a, 0x4e, 0xd0, 0xce, 0x6d, 0x21, 0x8b, 0xac,
                                       0xb3, 0x49, 0xa7, 0x47, 0xf2, 0x98, 0x27, 0x82};
const uint8_t NFC_UID_CHAR_UUID[16] = {0xee, 0x13, 0xfc, 0x14, 0xe0, 0x8e, 0x80, 0x94,
                                        0xe3, 0x43, 0xdb, 0x99, 0x55, 0x09, 0xe7, 0xb2};

BLEService nfcService(NFC_SERVICE_UUID);
BLECharacteristic nfcUidChar(NFC_UID_CHAR_UUID);

uint8_t lastUid[7];
uint8_t lastUidLength = 0;

void startAdv(void) {
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(nfcService);
  Bluefruit.Advertising.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244); // in units of 0.625 ms
  Bluefruit.Advertising.setFastTimeout(30);   // seconds in fast mode
  Bluefruit.Advertising.start(0);             // 0 = advertise forever
}

void setup() {
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("nfc-ble-reader");

  // Must be added before startAdv() for OTA DFU to be advertised correctly
  bledfu.begin();

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

  pn532PowerDown();
  delay(500); // PN532 is in Power Down for this whole window
}
