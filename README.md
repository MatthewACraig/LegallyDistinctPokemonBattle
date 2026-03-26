# LegallyDistinctPokemonBattle

A multiplayer battle prototype where:
- Mobile (Flutter) controls fighter actions
- M5 Core2 controls powerups

The game now uses match-scoped MQTT handshakes so each battle instance waits for an M5 Core2 player to join that exact match.

This repo also includes an alternative BLE transport that mirrors the same client/server workflow from your working sample.

## MQTT topics
- `m5core2/match`
- `m5core2/powerups`

## Match handshake flow
1. Mobile enters battle and generates a `matchId`.
2. Mobile publishes:
```json
{"type":"mobileReady","matchId":"match_...","player":"mobile"}
```
3. M5 listens for `mobileReady`, adopts that `matchId`, and responds:
```json
{"type":"m5Ready","matchId":"match_...","player":"m5core2"}
```
4. Mobile begins gameplay only after receiving `m5Ready` for the same `matchId`.
5. M5 powerups are published as:
```json
{"type":"powerUp","matchId":"match_...","powerUp":"heal|shield|boost","player":"m5core2"}
```

The Flutter app ignores powerups that do not match the active `matchId`.

## Mobile setup
1. Install Flutter dependencies:
```bash
flutter pub get
```
2. Set broker IP in [battle_screen.dart](/Users/gracebergquist/Repos/LegallyDistinctPokemonBattle/lib/screens/battle_screen.dart).
3. Run app:
```bash
flutter run
```

## Mobile BLE mode (optional)
Run with:
```bash
flutter run --dart-define=POWERUP_TRANSPORT=ble
```

The BLE transport runs M5 challenge phases from an M5 BLE server named `EGR425_BLE_Tag_Server`:
- `READY` (1 second)
- `GO!` (4 seconds of A/B/C mashing)
- Flutter uses press count for attack bonus or defense block

## M5 Core2 setup
Firmware lives at:
- [m5core2_powerups.ino](/Users/gracebergquist/Repos/LegallyDistinctPokemonBattle/firmware/m5core2_powerups/m5core2_powerups.ino)
- [firmware README](/Users/gracebergquist/Repos/LegallyDistinctPokemonBattle/firmware/m5core2_powerups/README.md)

Follow that firmware README to configure WiFi, broker, and flash the board.

## M5 Core2 BLE firmware (optional)
Alternative BLE firmware lives at:
- [BLE firmware README](/Users/gracebergquist/Repos/LegallyDistinctPokemonBattle/firmware/m5core2_ble_powerups/README.md)

Use that when you want local BLE client/server instead of MQTT.
