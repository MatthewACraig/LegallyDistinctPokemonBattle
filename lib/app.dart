import 'package:flutter/material.dart';

import 'screens/character_select_screen.dart';

class BattleGameApp extends StatelessWidget {
  const BattleGameApp({
    super.key,
    this.enableHardware = true,
  });

  final bool enableHardware;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battle Arena',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: CharacterSelectScreen(enableHardware: enableHardware),
    );
  }
}
