import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/power_up_event.dart';
import 'power_up_source.dart';

class MqttPowerUpSource implements PowerUpSource {
  MqttPowerUpSource({
    required this.broker,
    required this.topic,
    this.port = 1883,
    this.clientId = 'battle_client',
    this.activeMatchIdProvider,
    this.requireMatchId = false,
  });

  final String broker;
  final String topic;
  final int port;
  final String clientId;
  final String? Function()? activeMatchIdProvider;
  final bool requireMatchId;
  final StreamController<PowerUpEvent> _controller =
      StreamController<PowerUpEvent>.broadcast();
  MqttServerClient? _client;

  @override
  Stream<PowerUpEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    final client = MqttServerClient(broker, clientId);
    client.port = port;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.connectTimeoutPeriod = 2000;
    client.onDisconnected = () {};

    final connectMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connectMessage;

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        _client = client;
        client.subscribe(topic, MqttQos.atLeastOnce);
        client.updates?.listen((messages) {
          for (final message in messages) {
            final payload = MqttPublishPayload.bytesToStringAsString(
              (message.payload as MqttPublishMessage).payload.message,
            );
            final parsed = _tryParsePowerUp(payload);
            if (parsed != null) {
              _controller.add(parsed);
            }
          }
        });
      }
    } catch (_) {
      client.disconnect();
    }
  }

  PowerUpEvent? _tryParsePowerUp(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic> && decoded['powerUp'] is String) {
        final expectedMatchId = activeMatchIdProvider?.call();
        final incomingMatchId = decoded['matchId'];
        if (requireMatchId && expectedMatchId != null) {
          if (incomingMatchId is! String || incomingMatchId != expectedMatchId) {
            return null;
          }
        }
        return PowerUpEvent.fromPayload(decoded['powerUp'] as String);
      }
    } catch (_) {}

    if (requireMatchId) {
      return null;
    }

    final simpleEvent = PowerUpEvent.fromPayload(payload);
    if (simpleEvent != null) {
      return simpleEvent;
    }

    return null;
  }

  @override
  Future<void> dispose() async {
    _client?.disconnect();
    await _controller.close();
  }
}
