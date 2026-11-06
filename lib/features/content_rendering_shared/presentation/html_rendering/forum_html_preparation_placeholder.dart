import 'package:flutter/material.dart';

/// Preparation is pending; renderer readiness is reported only by real content.
class ForumHtmlPreparationPlaceholder extends StatelessWidget {
  const ForumHtmlPreparationPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 48,
    child: Center(
      child: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
