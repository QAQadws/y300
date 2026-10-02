import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

class NovelReaderChapterInteractionsButton extends StatelessWidget {
  const NovelReaderChapterInteractionsButton({
    super.key,
    required this.visible,
    required this.busy,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onPointerDown,
    this.surfaceKey = const Key('novel-reader-chapter-interactions-button'),
    this.elevation = 2,
  });

  final bool visible;
  final bool busy;
  final VoidCallback onPressed;
  final VoidCallback? onPointerDown;
  final Color backgroundColor;
  final Color foregroundColor;
  final Key surfaceKey;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final label = busy
        ? l10n.novelOpeningChapterInteractions
        : l10n.novelViewChapterInteractionsSemantics;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return AnimatedSwitcher(
      duration: duration,
      child: !visible
          ? const SizedBox.shrink(
              key: Key('novel-reader-chapter-interactions-hidden'),
            )
          : Listener(
              key: surfaceKey,
              onPointerDown: (_) => onPointerDown?.call(),
              child: Semantics(
                button: true,
                enabled: !busy,
                label: label,
                child: Tooltip(
                  message: label,
                  triggerMode: TooltipTriggerMode.manual,
                  excludeFromSemantics: true,
                  child: Material(
                    color: backgroundColor.withValues(
                      alpha: highContrast ? 0.82 : 0.5,
                    ),
                    elevation: elevation,
                    animationDuration: Duration.zero,
                    shadowColor: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: busy ? null : onPressed,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: busy
                              ? SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foregroundColor.withValues(
                                      alpha: highContrast ? 1 : 0.72,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.rate_review_outlined,
                                  size: 24,
                                  color: foregroundColor.withValues(
                                    alpha: highContrast ? 1 : 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
