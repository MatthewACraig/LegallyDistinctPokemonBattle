# M5 Core2 Powerup Controller

This sketch connects an M5 Core2 to the same MQTT broker used by the Flutter app and joins a match instance automatically.

## What it does
- Subscribes to `m5core2/match`
- Waits for a `mobileReady` message with a `matchId`
- Publishes `m5Ready` with that same `matchId`
- Sends powerups on `m5core2/powerups` scoped to that `matchId`

## Button mapping
- `A`: `heal`
- `B`: `shield`
- `C`: `boost`

## Setup
1. Install Arduino libraries:
- `M5Core2`
- `PubSubClient`
- `ArduinoJson`

2. Open `m5core2_powerups.ino` and set:
- `WIFI_SSID`
- `WIFI_PASSWORD`
- `MQTT_BROKER`

3. Flash to M5 Core2.

4. Start a match in Flutter on the same network.

## Expected JSON contract
Match topic (`m5core2/match`):
```json
{"type":"mobileReady","matchId":"match_...","player":"mobile"}
{"type":"m5Ready","matchId":"match_...","player":"m5core2"}
```

Powerup topic (`m5core2/powerups`):
```json
{"type":"powerUp","matchId":"match_...","powerUp":"heal|shield|boost","player":"m5core2"}
```
