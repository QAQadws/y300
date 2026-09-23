import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

class NovelReaderChapterInteractionsButton extends StatelessWidget {
  const NovelReaderChapterInteractionsButton({
    super.key,
    required this.busy,
    required this.onPressed,
    this.onPointerDown,
  });

  final bool busy;
  final VoidCallback onPressed;
  final VoidCallback? onPointerDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Listener(
      onPointerDown: (_) => onPointerDown?.call(),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.rate_review_outlined),
        label: Text(
          busy
              ? l10n.novelOpeningChapterInteractions
              : l10n.novelViewChapterInteractions,
          semanticsLabel: busy
              ? l10n.novelOpeningChapterInteractions
              : l10n.novelViewChapterInteractionsSemantics,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
