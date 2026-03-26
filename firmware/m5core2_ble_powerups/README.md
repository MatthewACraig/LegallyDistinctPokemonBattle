# M5 Core2 BLE Challenge Controller

This firmware uses the same BLE server/client pattern as your working sample, but for turn-based button-mash challenges.

## BLE contract
- Device name: `EGR425_BLE_Tag_Server`
- Service UUID: `4d92ed41-94fc-43a2-a9e6-e17e7f804d02`
- Notify characteristic (M5 -> mobile): `99f63e2d-8c68-4206-b763-da326c24009a` (`challengeResult` JSON)
- Write characteristic (mobile -> M5): `a1b2c3d4-e5f6-7890-abcd-ef1234567890` (`mobileReady` and `challenge|start|...`)

## Flow
1. Mobile writes `mobileReady:<matchId>`.
2. Mobile writes challenge command:
`challenge|start|attack|<requestId>|<matchId>` or
`challenge|start|defense|<requestId>|<matchId>`.
3. M5 shows `READY` for 1 second, then `GO!` for 4 seconds and counts A/B/C presses.
4. M5 notifies result JSON:

```json
{"type":"challengeResult","matchId":"match_...","phase":"attack","requestId":"r...","count":27}
```

## Button mapping during GO
- `A`: +1 press
- `B`: +1 press
- `C`: +1 press

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
