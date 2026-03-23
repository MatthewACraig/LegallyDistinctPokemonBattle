import 'dart:math';

enum MoveEffect {
  none,
  selfHeal,
  selfShield,
  stunChance,
  critChance,
  doubleStrike,
}

class BattleMove {
  const BattleMove({
    required this.name,
    required this.minDamage,
    required this.maxDamage,
    this.effect = MoveEffect.none,
    this.effectValue = 0,
    this.effectChance = 1,
  });

  final String name;
  final int minDamage;
  final int maxDamage;
  final MoveEffect effect;
  final int effectValue;
  final double effectChance;

  int rollDamage(Random random) {
    return minDamage + random.nextInt(maxDamage - minDamage + 1);
  }
}
