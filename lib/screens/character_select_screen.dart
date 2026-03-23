import 'package:flutter/material.dart';

import '../models/fighter_class.dart';
import '../widgets/sprite_sheet_actor.dart';
import 'battle_screen.dart';

class CharacterSelectScreen extends StatelessWidget {
  const CharacterSelectScreen({
    super.key,
    required this.enableHardware,
  });

  final bool enableHardware;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Class')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick your fighter:',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                itemCount: fighterClasses.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, index) {
                  final fighter = fighterClasses[index];
                  return _CharacterCard(
                    fighter: fighter,
                    onSelect: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BattleScreen(
                            enableHardware: enableHardware,
                            playerClass: fighter.type,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.fighter,
    required this.onSelect,
  });

  final FighterClassData fighter;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SpriteSheetActor(
                  assetPath: fighter.idleSprite,
                  stepTime: 0.1,
                  loop: true,
                  playing: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fighter.displayName,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Text(
              'HP: ${fighter.maxHp}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSelect,
              style: FilledButton.styleFrom(
                backgroundColor: fighter.primaryColor,
              ),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }
}
