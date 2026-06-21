import 'package:flutter/material.dart';

class ScoreChip extends StatelessWidget {
  final int score;
  final Color? color;

  const ScoreChip({super.key, required this.score, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c),
      ),
      child: Text(
        '$score נק׳',
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
