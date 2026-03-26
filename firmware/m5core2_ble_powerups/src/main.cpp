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
bool challengeActive = false;
bool challengeGo = false;
String challengePhase = "";
String challengeRequestId = "";
int challengePressCount = 0;
unsigned long challengeStartMs = 0;
unsigned long challengeGoMs = 0;
unsigned long lastHudRefreshMs = 0;

static const unsigned long READY_MS = 1000;
static const unsigned long CHALLENGE_MS = 4000;

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
    challengeActive = false;
    challengeGo = false;
    drawStatus("Client disconnected", "Advertising...");
    restartAdvertising();
  }
};

String tokenAt(const String& input, int tokenIndex) {
  int start = 0;
  int current = 0;

  while (start <= input.length()) {
    int end = input.indexOf('|', start);
    if (end < 0) {
      end = input.length();
    }
    if (current == tokenIndex) {
      return input.substring(start, end);
    }
    if (end >= input.length()) {
      break;
    }
    start = end + 1;
    current++;
  }

  return "";
}

void startChallenge(const String& phase, const String& requestId) {
  challengeActive = true;
  challengeGo = false;
  challengePhase = phase;
  challengeRequestId = requestId;
  challengePressCount = 0;
  challengeStartMs = millis();
  challengeGoMs = 0;
  lastHudRefreshMs = 0;
  drawStatus("M5 turn incoming", "READY", "Get ready to mash A/B/C");
}

void sendChallengeResult() {
  if (!deviceConnected || powerUpNotifyCharacteristic == nullptr) {
    return;
  }

  String payload = "{\"type\":\"challengeResult\",\"matchId\":\"" + activeMatchId +
                   "\",\"phase\":\"" + challengePhase + "\",\"requestId\":\"" + challengeRequestId +
                   "\",\"count\":" + String(challengePressCount) + "}";
  powerUpNotifyCharacteristic->setValue(payload.c_str());
  powerUpNotifyCharacteristic->notify();

  drawStatus("Result sent",
             "Phase: " + challengePhase,
             "Presses: " + String(challengePressCount));
}

class MobileCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String value = pCharacteristic->getValue().c_str();
    value.trim();

    if (value.startsWith("mobileReady:")) {
      activeMatchId = value.substring(String("mobileReady:").length());
      if (activeMatchId.length() == 0) {
        activeMatchId = "local";
      }
      drawStatus("Ready", "Match: " + activeMatchId, "Waiting for challenge...");
      return;
    }

    if (!value.startsWith("challenge|start|")) {
      return;
    }

    const String command = tokenAt(value, 0);
    const String action = tokenAt(value, 1);
    const String phase = tokenAt(value, 2);
    const String requestId = tokenAt(value, 3);
    const String matchId = tokenAt(value, 4);

    if (command != "challenge" || action != "start") {
      return;
    }
    if (phase != "attack" && phase != "defense") {
      return;
    }
    if (requestId.length() == 0) {
      return;
    }

    if (matchId.length() > 0) {
      activeMatchId = matchId;
    }
    if (activeMatchId.length() == 0) {
      activeMatchId = "local";
    }

    startChallenge(phase, requestId);
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

void setupBleServer() {
  BLEDevice::init(SERVER_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);
  powerUpNotifyCharacteristic = service->createCharacteristic(
      POWERUP_NOTIFY_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_INDICATE);
  powerUpNotifyCharacteristic->addDescriptor(new BLE2902());
  powerUpNotifyCharacteristic->setCallbacks(new MobileCallbacks());
  powerUpNotifyCharacteristic->setValue("{\"powerUp\":\"heal\"}");

  mobileReadyWriteCharacteristic = service->createCharacteristic(
      MOBILE_READY_WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  mobileReadyWriteCharacteristic->setCallbacks(new MobileCallbacks());
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

  if (challengeActive) {
    const unsigned long now = millis();

    if (!challengeGo) {
      if (now - challengeStartMs >= READY_MS) {
        challengeGo = true;
        challengeGoMs = now;
        drawStatus("GO!", "Mash A / B / C", "Time: 4.0s");
      }
      delay(10);
      return;
    }

    if (M5.BtnA.wasPressed()) {
      challengePressCount++;
    }
    if (M5.BtnB.wasPressed()) {
      challengePressCount++;
    }
    if (M5.BtnC.wasPressed()) {
      challengePressCount++;
    }

    const unsigned long elapsed = now - challengeGoMs;
    if (now - lastHudRefreshMs > 120) {
      lastHudRefreshMs = now;
      const int remainingMs = (int)max((long)0, (long)CHALLENGE_MS - (long)elapsed);
      String line2 = "Presses: " + String(challengePressCount);
      String line3 = "Time: " + String(remainingMs / 1000.0f, 1) + "s";
      drawStatus("GO!", line2, line3);
    }

    if (elapsed >= CHALLENGE_MS) {
      challengeActive = false;
      sendChallengeResult();
      drawStatus("Ready", "Match: " + activeMatchId, "Waiting for challenge...");
    }
  }

  delay(10);
}
