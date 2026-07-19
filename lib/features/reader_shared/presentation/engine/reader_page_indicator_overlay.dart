import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_chrome_palette.dart';

class ReaderPageIndicatorOverlay extends StatelessWidget {
  const ReaderPageIndicatorOverlay({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    this.highlighted = false,
    this.positionLabel,
  });

  final bool visible;
  final int currentPage;
  final int totalPages;
  final bool highlighted;
  final String? positionLabel;

  @override
  Widget build(BuildContext context) {
    final palette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final current = currentPage.clamp(1, safeTotal).toInt();
    final label = positionLabel?.trim();
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const Key('comic-reader-page-indicator-overlay'),
        opacity: visible ? (highlighted ? 0.92 : 0.62) : 0,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.overlayScrim,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: Text(
                    label == null || label.isEmpty
                        ? '$current / $safeTotal'
                        : label,
                    key: const Key('comic-reader-page-indicator-text'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white),
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
