#include <M5Core2.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ----------- Config -----------
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
const char* MQTT_BROKER = "192.168.1.50";
const uint16_t MQTT_PORT = 1883;

const char* TOPIC_MATCH = "m5core2/match";
const char* TOPIC_POWERUPS = "m5core2/powerups";

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

String activeMatchId;
unsigned long lastReconnectAttemptMs = 0;

void drawStatus(const String& line1, const String& line2 = "", const String& line3 = "") {
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextColor(WHITE, BLACK);
  M5.Lcd.setCursor(10, 20);
  M5.Lcd.setTextSize(2);
  M5.Lcd.println("M5 Powerup Client");
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

void publishM5Ready() {
  if (activeMatchId.length() == 0) {
    return;
  }

  StaticJsonDocument<192> doc;
  doc["type"] = "m5Ready";
  doc["player"] = "m5core2";
  doc["matchId"] = activeMatchId;
  doc["timestampMs"] = millis();

  char payload[192];
  const size_t size = serializeJson(doc, payload, sizeof(payload));
  if (size > 0) {
    mqttClient.publish(TOPIC_MATCH, payload, false);
  }
}

void publishPowerup(const char* powerUp) {
  if (!mqttClient.connected() || activeMatchId.length() == 0) {
    return;
  }

  StaticJsonDocument<192> doc;
  doc["type"] = "powerUp";
  doc["player"] = "m5core2";
  doc["matchId"] = activeMatchId;
  doc["powerUp"] = powerUp;
  doc["timestampMs"] = millis();

  char payload[192];
  const size_t size = serializeJson(doc, payload, sizeof(payload));
  if (size > 0) {
    mqttClient.publish(TOPIC_POWERUPS, payload, false);
  }
  drawStatus("Connected", "Match: " + activeMatchId, String("Sent: ") + powerUp);
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, TOPIC_MATCH) != 0) {
    return;
  }

  StaticJsonDocument<256> doc;
  const DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    return;
  }

  const char* type = doc["type"];
  const char* matchId = doc["matchId"];

  if (!type || !matchId) {
    return;
  }

  if (strcmp(type, "mobileReady") == 0) {
    activeMatchId = matchId;
    publishM5Ready();
    drawStatus("Connected", "Match: " + activeMatchId, "A=heal B=shield C=boost");
  }
}

bool connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  drawStatus("Connecting WiFi...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  const unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startMs < 15000) {
    delay(200);
  }

  if (WiFi.status() == WL_CONNECTED) {
    drawStatus("WiFi connected", WiFi.localIP().toString());
    return true;
  }

  drawStatus("WiFi failed", "Check SSID/password");
  return false;
}

bool connectMqtt() {
  if (mqttClient.connected()) {
    return true;
  }

  if (millis() - lastReconnectAttemptMs < 1500) {
    return false;
  }
  lastReconnectAttemptMs = millis();

  const String clientId = String("m5core2_") + String((uint32_t)ESP.getEfuseMac(), HEX);
  if (!mqttClient.connect(clientId.c_str())) {
    drawStatus("MQTT connect failed", "Broker: " + String(MQTT_BROKER));
    return false;
  }

  mqttClient.subscribe(TOPIC_MATCH);
  drawStatus("MQTT connected", "Listening for mobileReady");

  if (activeMatchId.length() > 0) {
    publishM5Ready();
  }

  return true;
}

void setup() {
  M5.begin();
  M5.Lcd.setRotation(1);
  drawStatus("Booting...");

  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);

  connectWiFi();
  connectMqtt();
}

void loop() {
  M5.update();

  if (!connectWiFi()) {
    delay(250);
    return;
  }

  if (!connectMqtt()) {
    delay(100);
    return;
  }

  mqttClient.loop();

  if (activeMatchId.length() > 0) {
    if (M5.BtnA.wasPressed()) {
      publishPowerup("heal");
    }
    if (M5.BtnB.wasPressed()) {
      publishPowerup("shield");
    }
    if (M5.BtnC.wasPressed()) {
      publishPowerup("boost");
    }
  }

  delay(10);
}
