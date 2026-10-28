import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A quiet return action that leaves the underlying conversation visible.
class ConversationLatestButton extends StatelessWidget {
  const ConversationLatestButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).y300NativeContent;
    return IconButton(
      tooltip: AppLocalizations.of(context).messageLatest,
      onPressed: onPressed,
      icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 22),
      style: IconButton.styleFrom(
        // Only the surface fades; the arrow stays legible over message bubbles.
        backgroundColor: palette.card.withValues(alpha: 0.35),
        foregroundColor: palette.body,
        overlayColor: palette.subtleStateLayer,
        side: BorderSide(
          color: palette.muted.withValues(alpha: 0.16),
          width: 0.75,
        ),
        shape: const CircleBorder(),
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
