import 'package:flutter/material.dart';

class HistoryDaySectionHeader extends StatelessWidget {
  const HistoryDaySectionHeader({
    super.key,
    required this.dateKey,
    required this.label,
  });

  final String dateKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey<String>('history-day-$dateKey'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
