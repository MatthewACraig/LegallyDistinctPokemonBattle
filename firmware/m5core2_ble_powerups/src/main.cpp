#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <M5Core2.h>

static const char* SERVICE_UUID = "4d92ed41-94fc-43a2-a9e6-e17e7f804d02";
static const char* POWERUP_NOTIFY_UUID = "99f63e2d-8c68-4206-b763-da326c24009a";
static const char* MOBILE_READY_WRITE_UUID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
static const char* SERVER_NAME = "EGR425_BLE_Tag_Server";

BLEServer* bleServer = nullptr;
BLECharacteristic* powerUpNotifyCharacteristic = nullptr;
BLECharacteristic* mobileReadyWriteCharacteristic = nullptr;

bool deviceConnected = false;
bool clientSubscribed = false;
String activeMatchId = "";

void drawStatus(const String& line1, const String& line2 = "", const String& line3 = "") {
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextColor(WHITE, BLACK);
  M5.Lcd.setCursor(10, 20);
  M5.Lcd.setTextSize(2);
  M5.Lcd.println("M5 BLE Powerups");
  M5.Lcd.setTextSize(1);
  M5.Lcd.println();
  M5.Lcd.println(line1);
  if (line2.length() > 0) {
    M5.Lcd.println(line2);
  }
  if (line3.length() > 0) {
    M5.Lcd.println(line3);
  }
}

void restartAdvertising() {
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->stop();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    (void)pServer;
    deviceConnected = true;
    clientSubscribed = false;
    drawStatus("Client connected", "Waiting for mobileReady write");
  }

  void onDisconnect(BLEServer* pServer) override {
    (void)pServer;
    deviceConnected = false;
    clientSubscribed = false;
    activeMatchId = "";
    drawStatus("Client disconnected", "Advertising...");
    restartAdvertising();
  }
};

class MobileReadyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String value = pCharacteristic->getValue().c_str();
    value.trim();
    if (value.startsWith("mobileReady:")) {
      activeMatchId = value.substring(String("mobileReady:").length());
    } else {
      activeMatchId = value;
    }

    if (activeMatchId.length() == 0) {
      activeMatchId = "local";
    }

    drawStatus("Ready", "Match: " + activeMatchId, "A=heal B=shield C=boost");
  }

  void onStatus(BLECharacteristic* pCharacteristic, Status s, uint32_t code) override {
    (void)pCharacteristic;
    (void)code;
    if (s == SUCCESS_NOTIFY || s == SUCCESS_INDICATE) {
      clientSubscribed = true;
    } else if (s == ERROR_NO_CLIENT || s == ERROR_NOTIFY_DISABLED) {
      clientSubscribed = false;
    }
  }
};

void sendPowerUp(const char* powerUp) {
  if (!deviceConnected || powerUpNotifyCharacteristic == nullptr) {
    drawStatus("Not connected", "Reconnect mobile BLE client");
    return;
  }

  if (activeMatchId.length() == 0) {
    drawStatus("No match id", "Waiting for mobileReady write");
    return;
  }

  String payload = "{\"type\":\"powerUp\",\"matchId\":\"" + activeMatchId +
                   "\",\"powerUp\":\"" + String(powerUp) + "\",\"player\":\"m5core2\"}";
  powerUpNotifyCharacteristic->setValue(payload.c_str());
  powerUpNotifyCharacteristic->notify();

  String line2 = "Match: " + activeMatchId;
  if (!clientSubscribed) {
    line2 += " (notify pending)";
  }
  drawStatus("Sent power-up", line2, String("Power-up: ") + powerUp);
}

void setupBleServer() {
  BLEDevice::init(SERVER_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);
  powerUpNotifyCharacteristic = service->createCharacteristic(
      POWERUP_NOTIFY_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_INDICATE);
  powerUpNotifyCharacteristic->addDescriptor(new BLE2902());
  powerUpNotifyCharacteristic->setCallbacks(new MobileReadyCallbacks());
  powerUpNotifyCharacteristic->setValue("{\"powerUp\":\"heal\"}");

  mobileReadyWriteCharacteristic = service->createCharacteristic(
      MOBILE_READY_WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  mobileReadyWriteCharacteristic->setCallbacks(new MobileReadyCallbacks());
  mobileReadyWriteCharacteristic->setValue("mobileReady");

  service->start();
  restartAdvertising();
}

void setup() {
  M5.begin();
  M5.Lcd.setRotation(1);
  drawStatus("Booting BLE server...");
  setupBleServer();
  drawStatus("Advertising", "Name: EGR425_BLE_Tag_Server");
}

void loop() {
  M5.update();

  if (activeMatchId.length() > 0) {
    if (M5.BtnA.wasPressed()) {
      sendPowerUp("heal");
    }
    if (M5.BtnB.wasPressed()) {
      sendPowerUp("shield");
    }
    if (M5.BtnC.wasPressed()) {
      sendPowerUp("boost");
    }
  }

  delay(10);
}
