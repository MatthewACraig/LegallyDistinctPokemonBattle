import 'package:flutter/material.dart';

class CombatantCard extends StatelessWidget {
  const CombatantCard({
    super.key,
    required this.label,
    required this.hp,
    required this.maxHp,
  });

  final String label;
  final int hp;
  final int maxHp;

  @override
  Widget build(BuildContext context) {
    final progress = hp / maxHp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text('HP: $hp / $maxHp'),
          ],
        ),
      ),
    );
  }
}
