import 'dart:async';

import '../models/power_up_event.dart';

abstract class PowerUpSource {
  Stream<PowerUpEvent> get events;
  Future<void> connect();
  Future<void> dispose();
}

class NoopPowerUpSource implements PowerUpSource {
  final StreamController<PowerUpEvent> _controller =
      StreamController<PowerUpEvent>.broadcast();

  @override
  Stream<PowerUpEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
