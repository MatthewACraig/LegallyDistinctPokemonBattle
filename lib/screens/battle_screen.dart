import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/battle_move.dart';
import '../models/fighter_class.dart';
import '../services/ble_power_up_source.dart';
import '../services/mqtt_power_up_source.dart';
import '../services/power_up_source.dart';
import '../widgets/sprite_sheet_actor.dart';
import 'character_select_screen.dart';

class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    this.enableHardware = true,
    required this.playerClass,
  });

  final bool enableHardware;
  final FighterClass playerClass;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

enum CombatantPose {
  idle,
  run,
  jumpUp,
  jumpMid,
  jumpDown,
  melee,
  ranged,
  hit,
  stunned,
  death,
}

enum CommandMode { root, attacks }

class _BattleScreenState extends State<BattleScreen> {
  static const String _powerUpTransport = String.fromEnvironment(
    'POWERUP_TRANSPORT',
    defaultValue: 'mqtt',
  );

  static const String _mqttBroker = '172.20.10.6';
  static const String _mqttTopic = 'm5core2/powerups';
  static const String _mqttMatchTopic = 'm5core2/match';
  static const String _bleDeviceName = 'EGR425_BLE_Tag_Server';
  static const String _bleServiceUuid = '4d92ed41-94fc-43a2-a9e6-e17e7f804d02';
  static const String _blePowerUpNotifyUuid =
      '99f63e2d-8c68-4206-b763-da326c24009a';
  static const String _bleMobileReadyWriteUuid =
      'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  static const int _maxItems = 3;

  static const List<String> _backgrounds = [
    'assets/BattleBackgrounds/battleback1.png',
    'assets/BattleBackgrounds/battleback2.png',
    'assets/BattleBackgrounds/battleback3.png',
    'assets/BattleBackgrounds/battleback4.png',
    'assets/BattleBackgrounds/battleback5.png',
    'assets/BattleBackgrounds/battleback6.png',
    'assets/BattleBackgrounds/battleback7.png',
    'assets/BattleBackgrounds/battleback8.png',
    'assets/BattleBackgrounds/battleback9.png',
    'assets/BattleBackgrounds/battleback10.png',
  ];

  static const List<String> _impactVfx = [
    'assets/VFX/spr_bloodsplatter1.png',
    'assets/VFX/spr_bloodsplatter2.png',
  ];

  final Random _random = Random();

  late final PowerUpSource _powerUpSource;
  BlePowerUpSource? _blePowerUpSource;
  late final FighterClassData _player;
  late FighterClassData _enemy;

  late int _playerHp;
  late int _enemyHp;
  int _playerShield = 0;
  int _enemyShield = 0;
  int _healingItems = _maxItems;

  MqttServerClient? _matchClient;
  bool _isM5Ready = false;
  Timer? _matchReadyTimeout;
  late String _matchId;

  bool _playerStunned = false;
  bool _enemyStunned = false;
  bool _hasBoost = false;
  bool _playerTurn = true;
  bool _isAnimating = false;

  String _status = 'Choose your action.';
  String _backgroundAsset = _backgrounds.first;
  String? _centerVfxAsset;
  bool _showCenterVfx = false;

  CommandMode _commandMode = CommandMode.root;
  CombatantPose _playerPose = CombatantPose.idle;
  CombatantPose _enemyPose = CombatantPose.idle;

  @override
  void initState() {
    super.initState();
    _player = fighterClasses.firstWhere(
      (entry) => entry.type == widget.playerClass,
    );
    _startNewMatch();

    if (widget.enableHardware && !_useBleTransport) {
      _setupMatchListener();
    }

    if (!widget.enableHardware) {
      _powerUpSource = NoopPowerUpSource();
    } else if (_useBleTransport) {
      final source = BlePowerUpSource(
        serviceUuid: _bleServiceUuid,
        powerUpNotifyCharacteristicUuid: _blePowerUpNotifyUuid,
        mobileReadyWriteCharacteristicUuid: _bleMobileReadyWriteUuid,
        preferredDeviceName: _bleDeviceName,
        mobileReadyPayload: 'mobileReady:$_matchId',
      );
      _blePowerUpSource = source;
      _powerUpSource = source;
    } else {
      _powerUpSource = MqttPowerUpSource(
        broker: _mqttBroker,
        topic: _mqttTopic,
        clientId: 'battle_client_${DateTime.now().millisecondsSinceEpoch}',
        activeMatchIdProvider: () => _matchId,
        requireMatchId: true,
      );
    }
    _setupPowerUps();
  }

  bool get _useBleTransport => _powerUpTransport.toLowerCase() == 'ble';

  @override
  void dispose() {
    _matchReadyTimeout?.cancel();
    _matchClient?.disconnect();
    _powerUpSource.dispose();
    super.dispose();
  }

  Future<void> _setupPowerUps() async {
    await _powerUpSource.connect();
  }

  Future<void> _setupMatchListener() async {
    final client = MqttServerClient(
      _mqttBroker,
      'match_client_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.connectTimeoutPeriod = 5000;
    client.onDisconnected = () {
      if (mounted) {
        setState(() {
          _isM5Ready = false;
          _status = 'M5 disconnected. Waiting for player...';
        });
      }
      _scheduleMatchReadyTimeout();
    };
    final connectMessage = MqttConnectMessage()
        .withClientIdentifier(
          'match_client_${DateTime.now().millisecondsSinceEpoch}',
        )
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connectMessage;

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        _matchClient = client;
        client.subscribe(_mqttMatchTopic, MqttQos.atLeastOnce);
        client.updates?.listen(_handleMatchMessages);

        _publishMobileReady();
        _scheduleMatchReadyTimeout();
      }
    } catch (_) {
      client.disconnect();
      if (mounted) {
        setState(() {
          _status = 'Failed to connect to match topic. Retry...';
        });
      }
    }
  }

  void _scheduleMatchReadyTimeout() {
    _matchReadyTimeout?.cancel();
    _matchReadyTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || _isM5Ready) return;
      setState(() {
        _status = 'Waiting for M5Core2 player to join...';
      });
      _publishMobileReady();
      _scheduleMatchReadyTimeout();
    });
  }

  void _handleMatchMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final payload = MqttPublishPayload.bytesToStringAsString(
        (message.payload as MqttPublishMessage).payload.message,
      );
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic> &&
            decoded['type'] == 'm5Ready' &&
            decoded['matchId'] == _matchId) {
          if (mounted) {
            setState(() {
              _isM5Ready = true;
              _status = 'M5Core2 player connected! Battle begins.';
            });
          }
          _matchReadyTimeout?.cancel();
        }
      } catch (_) {
        // ignore malformed match messages
      }
    }
  }

  Future<void> _publishMobileReady() async {
    if (_matchClient == null ||
        _matchClient?.connectionStatus?.state !=
            MqttConnectionState.connected) {
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(
      jsonEncode({
        'type': 'mobileReady',
        'matchId': _matchId,
        'player': 'mobile',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    _matchClient?.publishMessage(
      _mqttMatchTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _startNewMatch() {
    _matchId = _buildMatchId();
    _isM5Ready = !widget.enableHardware || _useBleTransport;

    final enemies = fighterClasses
        .where((entry) => entry.type != _player.type)
        .toList();

    _enemy = enemies[_random.nextInt(enemies.length)];
    _backgroundAsset = _backgrounds[_random.nextInt(_backgrounds.length)];

    _playerHp = _player.maxHp;
    _enemyHp = _enemy.maxHp;
    _playerShield = 0;
    _enemyShield = 0;
    _playerStunned = false;
    _enemyStunned = false;
    _hasBoost = false;
    _playerTurn = true;
    _isAnimating = false;
    _healingItems = _maxItems;
    _playerPose = CombatantPose.idle;
    _enemyPose = CombatantPose.idle;
    _commandMode = CommandMode.root;
    _showCenterVfx = false;
    _centerVfxAsset = null;
    _status =
        '${_player.displayName} vs ${_enemy.displayName}! Choose your action.';
    if (!_isM5Ready) {
      _status = 'Waiting for M5Core2 player to connect...';
    }

    if (widget.enableHardware && !_useBleTransport) {
      _publishMobileReady();
      _scheduleMatchReadyTimeout();
    }
  }

  String _buildMatchId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final salt = _random.nextInt(0x100000).toRadixString(16).padLeft(5, '0');
    return 'match_$timestamp$salt';
  }

  bool get _isBattleOver => _playerHp <= 0 || _enemyHp <= 0;

  bool get _canPlayerAct =>
      _playerTurn && !_isBattleOver && !_isAnimating && _isM5Ready;

  int _attackBonusFromPresses(int pressCount) => min(30, pressCount ~/ 2);

  int _defenseBlockFromPresses(int pressCount) => min(30, pressCount ~/ 2);

  Future<int> _runM5MashChallenge({
    required String phase,
    required String contextName,
  }) async {
    if (!_useBleTransport || _blePowerUpSource == null || !_isM5Ready) {
      return 0;
    }

    setState(() {
      _status =
          'M5 turn: ${phase == 'attack' ? 'Attack assist' : 'Defense assist'} for $contextName...';
    });

    return _blePowerUpSource!.runChallenge(matchId: _matchId, phase: phase);
  }

  String _pickImpactVfx() => _impactVfx[_random.nextInt(_impactVfx.length)];

  String _spriteForPose(FighterClassData fighter, CombatantPose pose) {
    switch (pose) {
      case CombatantPose.idle:
        return fighter.idleSprite;
      case CombatantPose.run:
        return fighter.runSprite;
      case CombatantPose.jumpUp:
        return fighter.jumpUpSprite;
      case CombatantPose.jumpMid:
        return fighter.jumpMidSprite;
      case CombatantPose.jumpDown:
        return fighter.jumpDownSprite;
      case CombatantPose.melee:
        return fighter.meleeAttackSprite;
      case CombatantPose.ranged:
        return fighter.rangedAttackSprite;
      case CombatantPose.hit:
        return fighter.hitSprite;
      case CombatantPose.stunned:
        switch (fighter.type) {
          case FighterClass.knight:
            return fighter.hitSprite;
          case FighterClass.monk:
            return 'assets/Monk/spr_monk_stunned.png';
          case FighterClass.ninja:
            return 'assets/Ninja/spr_ninja_stunned.png';
          case FighterClass.wizard:
            return 'assets/Wizard/spr_wizard_stunned.png';
        }
      case CombatantPose.death:
        return fighter.deathSprite;
    }
  }

  double _stepTimeForPose(CombatantPose pose) {
    switch (pose) {
      case CombatantPose.run:
        return 0.08;
      case CombatantPose.jumpUp:
      case CombatantPose.jumpMid:
      case CombatantPose.jumpDown:
        return 0.09;
      case CombatantPose.melee:
      case CombatantPose.ranged:
      case CombatantPose.hit:
        return 0.13;
      case CombatantPose.death:
      case CombatantPose.stunned:
        return 0.14;
      case CombatantPose.idle:
        return 0.11;
    }
  }

  bool _isLoopingPose(CombatantPose pose) {
    switch (pose) {
      case CombatantPose.idle:
      case CombatantPose.run:
      case CombatantPose.stunned:
        return true;
      case CombatantPose.jumpUp:
      case CombatantPose.jumpMid:
      case CombatantPose.jumpDown:
      case CombatantPose.melee:
      case CombatantPose.ranged:
      case CombatantPose.hit:
      case CombatantPose.death:
        return false;
    }
  }

  String? _projectileForMove(FighterClassData fighter, BattleMove move) {
    switch (fighter.type) {
      case FighterClass.knight:
        return null;
      case FighterClass.monk:
        return move.name == 'Cyclone Kick'
            ? null
            : 'assets/Monk/spr_fireball_charge.png';
      case FighterClass.ninja:
        return move.name == 'Kunai Toss' ? 'assets/Ninja/spr_kunai.png' : null;
      case FighterClass.wizard:
        return move.name == 'Fireball'
            ? 'assets/Wizard/spr_magic_projectile.png'
            : fighter.projectileSprite;
    }
  }

  String _impactForMove(FighterClassData fighter, BattleMove move) {
    switch (fighter.type) {
      case FighterClass.knight:
        return _pickImpactVfx();
      case FighterClass.monk:
        return move.name == 'Cyclone Kick'
            ? _pickImpactVfx()
            : 'assets/Monk/spr_fireball_impact.png';
      case FighterClass.ninja:
        return _pickImpactVfx();
      case FighterClass.wizard:
        return move.name == 'Fireball'
            ? 'assets/Wizard/spr_magic_projectileimpact.png'
            : _pickImpactVfx();
    }
  }

  Future<void> _playCenterVfx(
    String asset, {
    Duration duration = const Duration(milliseconds: 260),
  }) async {
    setState(() {
      _centerVfxAsset = asset;
      _showCenterVfx = true;
    });

    await Future<void>.delayed(duration);
    if (!mounted) {
      return;
    }

    setState(() {
      _showCenterVfx = false;
    });
  }

  Future<void> _playAttackPose({
    required bool isPlayer,
    required bool isRanged,
  }) async {
    void setPose(CombatantPose pose) {
      setState(() {
        if (isPlayer) {
          _playerPose = pose;
        } else {
          _enemyPose = pose;
        }
      });
    }

    setPose(CombatantPose.run);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    setPose(CombatantPose.jumpMid);
    await Future<void>.delayed(const Duration(milliseconds: 110));
    setPose(isRanged ? CombatantPose.ranged : CombatantPose.melee);
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  Future<void> _playHitPose({required bool isPlayer}) async {
    setState(() {
      if (isPlayer) {
        _playerPose = _playerHp <= 0
            ? CombatantPose.death
            : _playerStunned
            ? CombatantPose.stunned
            : CombatantPose.hit;
      } else {
        _enemyPose = _enemyHp <= 0
            ? CombatantPose.death
            : _enemyStunned
            ? CombatantPose.stunned
            : CombatantPose.hit;
      }
    });

    final targetHp = isPlayer ? _playerHp : _enemyHp;
    if (targetHp <= 0) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) {
      return;
    }

    setState(() {
      if (isPlayer) {
        _playerPose = _playerStunned
            ? CombatantPose.stunned
            : CombatantPose.idle;
      } else {
        _enemyPose = _enemyStunned ? CombatantPose.stunned : CombatantPose.idle;
      }
    });
  }

  Future<_ResolvedMove> _resolveMove(
    BattleMove move,
    int defendingShield,
  ) async {
    var damage = move.rollDamage(_random);
    var heal = 0;
    var shieldGain = 0;
    var stunned = false;
    var critical = false;
    var doubleStrike = false;

    switch (move.effect) {
      case MoveEffect.none:
        break;
      case MoveEffect.selfHeal:
        heal = move.effectValue;
        break;
      case MoveEffect.selfShield:
        shieldGain = move.effectValue;
        break;
      case MoveEffect.stunChance:
        if (_random.nextDouble() <= move.effectChance) {
          stunned = true;
        }
        break;
      case MoveEffect.critChance:
        if (_random.nextDouble() <= move.effectChance) {
          damage += move.effectValue;
          critical = true;
        }
        break;
      case MoveEffect.doubleStrike:
        if (_random.nextDouble() <= move.effectChance) {
          damage += move.rollDamage(_random);
          doubleStrike = true;
        }
        break;
    }

    final blocked = min(defendingShield, damage);
    damage -= blocked;

    return _ResolvedMove(
      damage: damage,
      blocked: blocked,
      heal: heal,
      shieldGain: shieldGain,
      stunned: stunned,
      critical: critical,
      doubleStrike: doubleStrike,
    );
  }

  Future<void> _playerAttack(BattleMove move) async {
    if (!_canPlayerAct) {
      return;
    }

    if (_playerStunned) {
      setState(() {
        _playerStunned = false;
        _playerPose = CombatantPose.idle;
        _playerTurn = false;
        _status = '${_player.displayName} is stunned and misses the turn!';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _enemyTurn();
      return;
    }

    setState(() {
      _isAnimating = true;
      _commandMode = CommandMode.root;
    });

    final isRanged =
        move.name.contains('Toss') ||
        move.name.contains('Bolt') ||
        move.name.contains('Fireball');

    await _playAttackPose(isPlayer: true, isRanged: isRanged);

    final projectileAsset = _projectileForMove(_player, move);
    if (projectileAsset != null) {
      await _playCenterVfx(
        projectileAsset,
        duration: const Duration(milliseconds: 220),
      );
    }

    final mashCount = await _runM5MashChallenge(
      phase: 'attack',
      contextName: move.name,
    );
    final resolved = await _resolveMove(move, _enemyShield);
    final boost = _hasBoost ? 8 : 0;
    final m5Bonus = _attackBonusFromPresses(mashCount);
    final totalDamage = resolved.damage + boost + m5Bonus;

    setState(() {
      _enemyShield = max(0, _enemyShield - resolved.blocked);
      _enemyHp = max(0, _enemyHp - totalDamage);
      _enemyStunned = resolved.stunned;
      _playerHp = min(_player.maxHp, _playerHp + resolved.heal);
      _playerShield += resolved.shieldGain;
      _hasBoost = false;
      _playerTurn = false;

      _status =
          '${_player.displayName} used ${move.name}! '
          '$totalDamage dmg'
          '${resolved.blocked > 0 ? ' (${resolved.blocked} blocked)' : ''}'
          '${resolved.critical ? ' [CRIT]' : ''}'
          '${resolved.doubleStrike ? ' [DOUBLE]' : ''}'
          '${resolved.heal > 0 ? ' +${resolved.heal} HP' : ''}'
          '${resolved.shieldGain > 0 ? ' +${resolved.shieldGain} shield' : ''}'
          '${resolved.stunned ? ' and stunned ${_enemy.displayName}!' : ''}'
          '${m5Bonus > 0 ? ' [M5 +$m5Bonus from $mashCount presses]' : ''}';
    });

    await _playCenterVfx(_impactForMove(_player, move));
    await _playHitPose(isPlayer: false);

    if (_enemyHp <= 0) {
      setState(() {
        _enemyPose = CombatantPose.death;
        _status = '${_enemy.displayName} fainted! You win!';
        _isAnimating = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _playerPose = CombatantPose.idle;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _enemyTurn();
  }

  Future<void> _enemyTurn() async {
    if (_isBattleOver || !mounted) {
      return;
    }

    if (_enemyStunned) {
      setState(() {
        _enemyStunned = false;
        _enemyPose = CombatantPose.idle;
        _playerTurn = true;
        _isAnimating = false;
        _status = '${_enemy.displayName} is stunned and cannot act!';
      });
      return;
    }

    final move = _enemy.moves[_random.nextInt(_enemy.moves.length)];
    final isRanged =
        move.name.contains('Toss') ||
        move.name.contains('Bolt') ||
        move.name.contains('Fireball');

    await _playAttackPose(isPlayer: false, isRanged: isRanged);

    final projectileAsset = _projectileForMove(_enemy, move);
    if (projectileAsset != null) {
      await _playCenterVfx(
        projectileAsset,
        duration: const Duration(milliseconds: 220),
      );
    }

    final mashCount = await _runM5MashChallenge(
      phase: 'defense',
      contextName: move.name,
    );
    final resolved = await _resolveMove(move, _playerShield);
    final m5Block = _defenseBlockFromPresses(mashCount);
    final postMashDamage = max(0, resolved.damage - m5Block);

    setState(() {
      _playerShield = max(0, _playerShield - resolved.blocked);
      _playerHp = max(0, _playerHp - postMashDamage);
      _playerStunned = resolved.stunned;
      _enemyHp = min(_enemy.maxHp, _enemyHp + resolved.heal);
      _enemyShield += resolved.shieldGain;
      _playerTurn = true;
      _isAnimating = false;

      _status =
          '${_enemy.displayName} used ${move.name}! '
          '$postMashDamage dmg'
          '${resolved.blocked > 0 ? ' (${resolved.blocked} blocked)' : ''}'
          '${m5Block > 0 ? ' ($m5Block M5 block)' : ''}'
          '${resolved.critical ? ' [CRIT]' : ''}'
          '${resolved.doubleStrike ? ' [DOUBLE]' : ''}'
          '${resolved.heal > 0 ? ' +${resolved.heal} HP' : ''}'
          '${resolved.shieldGain > 0 ? ' +${resolved.shieldGain} shield' : ''}'
          '${resolved.stunned ? ' and stunned ${_player.displayName}!' : ''}';

      if (_playerHp <= 0) {
        _playerPose = CombatantPose.death;
        _status = '${_player.displayName} fainted!';
      }
    });

    await _playCenterVfx(_impactForMove(_enemy, move));
    await _playHitPose(isPlayer: true);

    if (!mounted || _isBattleOver) {
      return;
    }

    setState(() {
      _enemyPose = CombatantPose.idle;
    });
  }

  void _useItem() {
    if (!_canPlayerAct) {
      return;
    }

    if (_healingItems <= 0) {
      setState(() {
        _status = 'No items left!';
      });
      return;
    }

    setState(() {
      _healingItems -= 1;
      _playerHp = min(_player.maxHp, _playerHp + 25);
      _playerTurn = false;
      _status =
          '${_player.displayName} used Potion (+25 HP). Items left: $_healingItems';
    });

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _enemyTurn();
    });
  }

  Widget _buildHudBox({
    required String name,
    required int hp,
    required int maxHp,
    required int shield,
    required bool alignRight,
  }) {
    final hpRatio = (hp / maxHp).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: Colors.black87, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: alignRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 170,
            child: LinearProgressIndicator(
              value: hpRatio,
              minHeight: 8,
              backgroundColor: Colors.red.shade200,
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Text('HP: $hp/$maxHp  Shield: $shield'),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onTap,
    double fontSize = 15,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: Colors.black87, width: 2),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: fontSize),
        ),
      ),
    );
  }

  Widget _buildCommandPanel(bool isLandscape) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 3),
      ),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, panel) {
          final buttonFont = isLandscape ? 14.0 : 12.0;
          final statusFont = isLandscape ? 14.0 : 12.0;
          final gap = isLandscape ? 6.0 : 5.0;

          Widget rowButton(String text, VoidCallback? onTap) {
            return Expanded(
              child: _buildActionButton(
                label: text,
                onTap: onTap,
                fontSize: buttonFont,
              ),
            );
          }

          Widget rootLayout() {
            return Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      rowButton(
                        'Attacks',
                        _canPlayerAct
                            ? () => setState(
                                () => _commandMode = CommandMode.attacks,
                              )
                            : null,
                      ),
                      SizedBox(width: gap),
                      rowButton(
                        'Use Item ($_healingItems)',
                        _canPlayerAct ? _useItem : null,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      rowButton('M5 QTE (auto each turn)', null),
                      SizedBox(width: gap),
                      rowButton('Run', () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => CharacterSelectScreen(
                              enableHardware: widget.enableHardware,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget attacksLayout() {
            final moveButtons = _player.moves
                .map(
                  (move) => rowButton(
                    move.name,
                    _canPlayerAct ? () => _playerAttack(move) : null,
                  ),
                )
                .toList();

            while (moveButtons.length < 3) {
              moveButtons.add(const Expanded(child: SizedBox.shrink()));
            }

            return Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      moveButtons[0],
                      SizedBox(width: gap),
                      moveButtons[1],
                    ],
                  ),
                ),
                SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      moveButtons[2],
                      SizedBox(width: gap),
                      rowButton(
                        'Back',
                        () => setState(() => _commandMode = CommandMode.root),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: statusFont,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: gap),
              Expanded(
                child: _commandMode == CommandMode.root
                    ? rootLayout()
                    : attacksLayout(),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;

          return LayoutBuilder(
            builder: (context, constraints) {
              final commandPanelHeight = isLandscape
                  ? min(190.0, constraints.maxHeight * 0.3)
                  : min(215.0, constraints.maxHeight * 0.34);

              final playerSpriteHeight = isLandscape
                  ? constraints.maxHeight * 0.36
                  : constraints.maxHeight * 0.24;

              final enemySpriteHeight = isLandscape
                  ? constraints.maxHeight * 0.32
                  : constraints.maxHeight * 0.2;

              final battlefieldBottom =
                  commandPanelHeight + (isLandscape ? 6 : 14);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _backgroundAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: Colors.black),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.13)),

                  SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 10,
                          child: _buildHudBox(
                            name: _enemy.displayName,
                            hp: _enemyHp,
                            maxHp: _enemy.maxHp,
                            shield: _enemyShield,
                            alignRight: false,
                          ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: battlefieldBottom + (isLandscape ? 2 : 12),
                          child: _buildHudBox(
                            name: _player.displayName,
                            hp: _playerHp,
                            maxHp: _player.maxHp,
                            shield: _playerShield,
                            alignRight: true,
                          ),
                        ),

                        Positioned(
                          left:
                              constraints.maxWidth *
                              (isLandscape ? 0.08 : 0.03),
                          bottom: battlefieldBottom,
                          child: SpriteSheetActor(
                            assetPath: _spriteForPose(_player, _playerPose),
                            animationKey: 'player_${_playerPose.name}',
                            width:
                                constraints.maxWidth *
                                (isLandscape ? 0.32 : 0.45),
                            height: playerSpriteHeight,
                            stepTime: _stepTimeForPose(_playerPose),
                            loop: _isLoopingPose(_playerPose),
                            playing: true,
                          ),
                        ),

                        Positioned(
                          right:
                              constraints.maxWidth *
                              (isLandscape ? 0.12 : 0.06),
                          bottom: battlefieldBottom + (isLandscape ? 76 : 84),
                          child: SpriteSheetActor(
                            assetPath: _spriteForPose(_enemy, _enemyPose),
                            animationKey: 'enemy_${_enemyPose.name}',
                            width:
                                constraints.maxWidth *
                                (isLandscape ? 0.27 : 0.36),
                            height: enemySpriteHeight,
                            stepTime: _stepTimeForPose(_enemyPose),
                            flipX: true,
                            loop: _isLoopingPose(_enemyPose),
                            playing: true,
                          ),
                        ),

                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: commandPanelHeight,
                          child: _buildCommandPanel(isLandscape),
                        ),

                        if (!isLandscape)
                          Positioned(
                            top: 8,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              color: Colors.black.withValues(alpha: 0.45),
                              child: const Text(
                                'Best in landscape',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (!_isM5Ready)
                    Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          Text(
                            'Waiting for M5Core2 player to connect...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Match ID: $_matchId',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _showCenterVfx ? 1 : 0,
                        duration: const Duration(milliseconds: 100),
                        child: _centerVfxAsset == null
                            ? const SizedBox.shrink()
                            : SpriteSheetActor(
                                assetPath: _centerVfxAsset!,
                                width: min(220, constraints.maxWidth * 0.4),
                                height: min(220, constraints.maxHeight * 0.4),
                                stepTime: 0.06,
                                playing: _showCenterVfx,
                                loop: false,
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          setState(_startNewMatch);
        },
        tooltip: 'New random battle',
        child: const Icon(Icons.casino),
      ),
    );
  }
}

class _ResolvedMove {
  const _ResolvedMove({
    required this.damage,
    required this.blocked,
    required this.heal,
    required this.shieldGain,
    required this.stunned,
    required this.critical,
    required this.doubleStrike,
  });

  final int damage;
  final int blocked;
  final int heal;
  final int shieldGain;
  final bool stunned;
  final bool critical;
  final bool doubleStrike;
}
