# M5 Core2 BLE Powerup Controller

This firmware uses the same BLE server/client pattern as your working sample.

## BLE contract
- Device name: `EGR425_BLE_Tag_Server`
- Service UUID: `4d92ed41-94fc-43a2-a9e6-e17e7f804d02`
- Notify characteristic (M5 -> mobile): `99f63e2d-8c68-4206-b763-da326c24009a`
- Write characteristic (mobile -> M5): `a1b2c3d4-e5f6-7890-abcd-ef1234567890`

The mobile app writes `mobileReady:<matchId>`.  
The M5 notifies JSON power-up payloads:

```json
{"type":"powerUp","matchId":"match_...","powerUp":"heal|shield|boost","player":"m5core2"}
```

## Button mapping
- `A`: `heal`
- `B`: `shield`
- `C`: `boost`

## Build and flash
```bash
cd firmware/m5core2_ble_powerups
pio run -t upload
pio device monitor
```

## Flutter side
Run the app with BLE transport enabled:

```bash
flutter run --dart-define=POWERUP_TRANSPORT=ble
```
