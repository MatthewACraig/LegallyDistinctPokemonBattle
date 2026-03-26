import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/power_up_event.dart';
import 'power_up_source.dart';

class BlePowerUpSource implements PowerUpSource {
  BlePowerUpSource({
    required this.serviceUuid,
    required this.powerUpNotifyCharacteristicUuid,
    required this.mobileReadyWriteCharacteristicUuid,
    this.preferredDeviceName = 'EGR425_BLE_Tag_Server',
    this.mobileReadyPayload = 'mobileReady',
  });

  final String serviceUuid;
  final String powerUpNotifyCharacteristicUuid;
  final String mobileReadyWriteCharacteristicUuid;
  final String preferredDeviceName;
  final String mobileReadyPayload;

  final StreamController<PowerUpEvent> _controller =
      StreamController<PowerUpEvent>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _powerUpNotifyCharacteristic;
  BluetoothCharacteristic? _mobileReadyWriteCharacteristic;

  bool _disposed = false;
  bool _isScanning = false;
  Timer? _retryTimer;
  int _requestCounter = 0;
  final Map<String, Completer<int>> _pendingChallengeResults = {};

  @override
  Stream<PowerUpEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    await _startScan();
  }

  Future<void> _startScan() async {
    if (_disposed || _isScanning || _device != null) {
      return;
    }
    _isScanning = true;

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        if (!_matchesExpectedDevice(result)) {
          continue;
        }

        await FlutterBluePlus.stopScan();
        _isScanning = false;
        await _connectToDevice(result.device);
        return;
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {
      _isScanning = false;
      _scheduleRetry();
      return;
    }

    _isScanning = false;
    _scheduleRetry();
  }

  bool _matchesExpectedDevice(ScanResult result) {
    final advertisedName = result.advertisementData.advName.trim();
    if (advertisedName.isNotEmpty && advertisedName == preferredDeviceName) {
      return true;
    }
    return result.device.platformName.trim() == preferredDeviceName;
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_disposed) {
      return;
    }

    _retryTimer?.cancel();
    _device = device;

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _cleanupConnectionState();
        _scheduleRetry();
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 12));
      await _discoverAndSubscribe(device);
    } catch (_) {
      _cleanupConnectionState();
      _scheduleRetry();
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = _firstWhereOrNull<BluetoothService>(
      services,
      (entry) => entry.uuid == Guid(serviceUuid),
    );

    if (service == null) {
      _cleanupConnectionState();
      _scheduleRetry();
      return;
    }

    _powerUpNotifyCharacteristic = _firstWhereOrNull<BluetoothCharacteristic>(
      service.characteristics,
      (entry) => entry.uuid == Guid(powerUpNotifyCharacteristicUuid),
    );
    _mobileReadyWriteCharacteristic =
        _firstWhereOrNull<BluetoothCharacteristic>(
          service.characteristics,
          (entry) => entry.uuid == Guid(mobileReadyWriteCharacteristicUuid),
        );

    if (_powerUpNotifyCharacteristic == null) {
      _cleanupConnectionState();
      _scheduleRetry();
      return;
    }

    await _powerUpNotifyCharacteristic!.setNotifyValue(true);
    await _notifySubscription?.cancel();
    _notifySubscription = _powerUpNotifyCharacteristic!.lastValueStream.listen((
      value,
    ) {
      final payload = utf8.decode(value, allowMalformed: true);
      if (_tryHandleChallengeResult(payload)) {
        return;
      }

      final event = _tryParsePowerUp(payload);
      if (event != null) {
        _controller.add(event);
      }
    });

    if (_mobileReadyWriteCharacteristic != null) {
      try {
        final characteristic = _mobileReadyWriteCharacteristic!;
        final bytes = utf8.encode(mobileReadyPayload);
        final supportsWrite = characteristic.properties.write;
        final supportsWriteWithoutResponse =
            characteristic.properties.writeWithoutResponse;

        if (supportsWrite) {
          await characteristic.write(bytes, withoutResponse: false);
        } else if (supportsWriteWithoutResponse) {
          await characteristic.write(bytes, withoutResponse: true);
        } else {
          await characteristic.write(bytes);
        }
      } catch (_) {
        try {
          await _mobileReadyWriteCharacteristic!.write(
            utf8.encode(mobileReadyPayload),
            withoutResponse: false,
          );
        } catch (_) {}
      }
    }
  }

  PowerUpEvent? _tryParsePowerUp(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic> && decoded['powerUp'] is String) {
        return PowerUpEvent.fromPayload(decoded['powerUp'] as String);
      }
    } catch (_) {}

    return PowerUpEvent.fromPayload(payload.trim());
  }

  bool _tryHandleChallengeResult(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['type'] != 'challengeResult') {
        return false;
      }

      final requestId = decoded['requestId'];
      final countRaw = decoded['count'];
      if (requestId is! String || countRaw is! num) {
        return false;
      }

      final completer = _pendingChallengeResults.remove(requestId);
      completer?.complete(countRaw.toInt());
      return completer != null;
    } catch (_) {
      return false;
    }
  }

  Future<int> runChallenge({
    required String matchId,
    required String phase,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final writeCharacteristic = _mobileReadyWriteCharacteristic;
    if (writeCharacteristic == null) {
      return 0;
    }

    final requestId =
        'r${DateTime.now().millisecondsSinceEpoch}_${_requestCounter++}';
    final completer = Completer<int>();
    _pendingChallengeResults[requestId] = completer;

    final payload = 'challenge|start|$phase|$requestId|$matchId';
    try {
      final supportsWrite = writeCharacteristic.properties.write;
      final supportsWriteWithoutResponse =
          writeCharacteristic.properties.writeWithoutResponse;

      if (supportsWrite) {
        await writeCharacteristic.write(
          utf8.encode(payload),
          withoutResponse: false,
        );
      } else if (supportsWriteWithoutResponse) {
        await writeCharacteristic.write(
          utf8.encode(payload),
          withoutResponse: true,
        );
      } else {
        await writeCharacteristic.write(utf8.encode(payload));
      }
    } catch (_) {
      _pendingChallengeResults.remove(requestId);
      return 0;
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pendingChallengeResults.remove(requestId);
      return 0;
    }
  }

  void _cleanupConnectionState() {
    _powerUpNotifyCharacteristic = null;
    _mobileReadyWriteCharacteristic = null;
    _device = null;
  }

  void _scheduleRetry() {
    if (_disposed) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _startScan();
    });
  }

  T? _firstWhereOrNull<T>(Iterable<T> entries, bool Function(T entry) test) {
    for (final entry in entries) {
      if (test(entry)) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _notifySubscription?.cancel();
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    for (final completer in _pendingChallengeResults.values) {
      if (!completer.isCompleted) {
        completer.complete(0);
      }
    }
    _pendingChallengeResults.clear();
    await _controller.close();
  }
}
