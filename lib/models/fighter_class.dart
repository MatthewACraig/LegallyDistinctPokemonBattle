import 'package:flutter/material.dart';

import 'battle_move.dart';

enum FighterClass {
  knight,
  monk,
  ninja,
  wizard,
}

class FighterClassData {
  const FighterClassData({
    required this.type,
    required this.displayName,
    required this.primaryColor,
    required this.maxHp,
    required this.idleSprite,
    required this.hitSprite,
    required this.deathSprite,
    required this.runSprite,
    required this.jumpUpSprite,
    required this.jumpMidSprite,
    required this.jumpDownSprite,
    required this.meleeAttackSprite,
    required this.rangedAttackSprite,
    this.projectileSprite,
    required this.moves,
  });

  final FighterClass type;
  final String displayName;
  final Color primaryColor;
  final int maxHp;
  final String idleSprite;
  final String hitSprite;
  final String deathSprite;
  final String runSprite;
  final String jumpUpSprite;
  final String jumpMidSprite;
  final String jumpDownSprite;
  final String meleeAttackSprite;
  final String rangedAttackSprite;
  final String? projectileSprite;
  final List<BattleMove> moves;
}

const List<FighterClassData> fighterClasses = [
  FighterClassData(
    type: FighterClass.knight,
    displayName: 'Knight',
    primaryColor: Colors.blueGrey,
    maxHp: 120,
    idleSprite: 'assets/Knight/spr_knight_idle.png',
    hitSprite: 'assets/Knight/spr_knight_hit.png',
    deathSprite: 'assets/Knight/spr_knight_death.png',
    runSprite: 'assets/Knight/spr_knight_run.png',
    jumpUpSprite: 'assets/Knight/spr_knight_jumpup.png',
    jumpMidSprite: 'assets/Knight/spr_knight_jumpmid.png',
    jumpDownSprite: 'assets/Knight/spr_knight_jumpdown.png',
    meleeAttackSprite: 'assets/Knight/spr_knight_meleeattack.png',
    rangedAttackSprite: 'assets/Knight/spr_knight_rangedattack.png',
    moves: [
      BattleMove(name: 'Broadsword Slash', minDamage: 13, maxDamage: 20),
      BattleMove(
        name: 'Shield Bash',
        minDamage: 9,
        maxDamage: 15,
        effect: MoveEffect.selfShield,
        effectValue: 10,
      ),
      BattleMove(
        name: 'Vanguard Strike',
        minDamage: 12,
        maxDamage: 18,
        effect: MoveEffect.critChance,
        effectValue: 10,
        effectChance: 0.35,
      ),
    ],
  ),
  FighterClassData(
    type: FighterClass.monk,
    displayName: 'Monk',
    primaryColor: Colors.orange,
    maxHp: 105,
    idleSprite: 'assets/Monk/spr_monk_idle.png',
    hitSprite: 'assets/Monk/spr_monk_hit.png',
    deathSprite: 'assets/Monk/spr_monk_death.png',
    runSprite: 'assets/Monk/spr_monk_run.png',
    jumpUpSprite: 'assets/Monk/spr_monk_jump_up.png',
    jumpMidSprite: 'assets/Monk/spr_monk_jump_mid.png',
    jumpDownSprite: 'assets/Monk/spr_monk_jump_down.png',
    meleeAttackSprite: 'assets/Monk/spr_monk_melee_attack.png',
    rangedAttackSprite: 'assets/Monk/spr_monk_ranged_attack.png',
    projectileSprite: 'assets/Monk/spr_fireball_loop.png',
    moves: [
      BattleMove(
        name: 'Chi Palm',
        minDamage: 10,
        maxDamage: 16,
        effect: MoveEffect.selfHeal,
        effectValue: 8,
      ),
      BattleMove(name: 'Cyclone Kick', minDamage: 12, maxDamage: 19),
      BattleMove(
        name: 'Breathing Stance',
        minDamage: 6,
        maxDamage: 11,
        effect: MoveEffect.selfShield,
        effectValue: 12,
      ),
    ],
  ),
  FighterClassData(
    type: FighterClass.ninja,
    displayName: 'Ninja',
    primaryColor: Colors.deepPurple,
    maxHp: 95,
    idleSprite: 'assets/Ninja/spr_ninja_idle.png',
    hitSprite: 'assets/Ninja/spr_ninja_hit.png',
    deathSprite: 'assets/Ninja/spr_ninja_death.png',
    runSprite: 'assets/Ninja/spr_ninja_run.png',
    jumpUpSprite: 'assets/Ninja/spr_ninja_jump_up.png',
    jumpMidSprite: 'assets/Ninja/spr_ninja_jump_mid-spin.png',
    jumpDownSprite: 'assets/Ninja/spr_ninja_jump_down.png',
    meleeAttackSprite: 'assets/Ninja/spr_ninja_melee_attack.png',
    rangedAttackSprite: 'assets/Ninja/spr_ninja_ranged_attack.png',
    projectileSprite: 'assets/Ninja/spr_kunai.png',
    moves: [
      BattleMove(
        name: 'Twin Daggers',
        minDamage: 8,
        maxDamage: 13,
        effect: MoveEffect.doubleStrike,
        effectChance: 0.45,
      ),
      BattleMove(
        name: 'Kunai Toss',
        minDamage: 11,
        maxDamage: 17,
        effect: MoveEffect.stunChance,
        effectChance: 0.35,
      ),
      BattleMove(
        name: 'Assassinate',
        minDamage: 13,
        maxDamage: 22,
        effect: MoveEffect.critChance,
        effectValue: 12,
        effectChance: 0.3,
      ),
    ],
  ),
  FighterClassData(
    type: FighterClass.wizard,
    displayName: 'Wizard',
    primaryColor: Colors.cyan,
    maxHp: 90,
    idleSprite: 'assets/Wizard/spr_wizard_idle.png',
    hitSprite: 'assets/Wizard/spr_wizard_hit.png',
    deathSprite: 'assets/Wizard/spr_wizard_death.png',
    runSprite: 'assets/Wizard/spr_wizard_run.png',
    jumpUpSprite: 'assets/Wizard/spr_wizard_jumpup.png',
    jumpMidSprite: 'assets/Wizard/spr_wizard_jumpmid.png',
    jumpDownSprite: 'assets/Wizard/spr_wizard_jumpdown.png',
    meleeAttackSprite: 'assets/Wizard/spr_wizard_meleeattack.png',
    rangedAttackSprite: 'assets/Wizard/spr_wizard_rangedattack.png',
    projectileSprite: 'assets/Wizard/spr_magic_projectile.png',
    moves: [
      BattleMove(name: 'Arcane Bolt', minDamage: 11, maxDamage: 18),
      BattleMove(
        name: 'Fireball',
        minDamage: 13,
        maxDamage: 21,
        effect: MoveEffect.stunChance,
        effectChance: 0.3,
      ),
      BattleMove(
        name: 'Mana Shield',
        minDamage: 7,
        maxDamage: 11,
        effect: MoveEffect.selfShield,
        effectValue: 13,
      ),
    ],
  ),
];
