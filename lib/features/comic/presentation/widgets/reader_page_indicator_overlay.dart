import 'package:flutter/material.dart';

class ReaderPageIndicatorOverlay extends StatelessWidget {
  const ReaderPageIndicatorOverlay({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    this.highlighted = false,
  });

  final bool visible;
  final int currentPage;
  final int totalPages;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final current = currentPage.clamp(1, safeTotal).toInt();
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
                  color: Colors.black.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Text(
                    '$current / $safeTotal',
                    key: const Key('comic-reader-page-indicator-text'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
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
