import 'package:flutter/material.dart';

import '../models/game_mode.dart';
import 'character_select_screen.dart';

class GameModeScreen extends StatelessWidget {
  const GameModeScreen({super.key, required this.enableHardware});

  final bool enableHardware;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Battle Mode')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose mode:',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _ModeCard(
              title: 'Same Team',
              subtitle: 'Flutter attacks, M5 helps with timing/mash assists',
              onTap: () => _goToCharacterSelect(context, GameMode.sameTeam),
            ),
            const SizedBox(height: 14),
            _ModeCard(
              title: 'PvP',
              subtitle:
                  'Flutter vs M5. Turns alternate and both sides mash for damage/block.',
              onTap: () => _goToCharacterSelect(context, GameMode.pvp),
            ),
          ],
        ),
      ),
    );
  }

  void _goToCharacterSelect(BuildContext context, GameMode mode) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CharacterSelectScreen(
          enableHardware: enableHardware,
          gameMode: mode,
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 12),
            FilledButton(onPressed: onTap, child: const Text('Select')),
          ],
        ),
      ),
    );
  }
}
