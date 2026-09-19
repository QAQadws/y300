import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/l10n/app_localizations.dart';

class ThreadDetailQuickScrollButton extends StatelessWidget {
  const ThreadDetailQuickScrollButton({
    super.key,
    required this.coordinator,
    required this.hasContent,
    required this.backgroundColor,
    required this.foregroundColor,
    this.elevation = 2,
    this.surfaceKey = const Key('thread-detail-quick-scroll-button'),
  });

  final ThreadDetailQuickScrollCoordinator coordinator;
  final bool hasContent;
  final Color backgroundColor;
  final Color foregroundColor;
  final double elevation;
  final Key surfaceKey;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 160);

    return AnimatedBuilder(
      animation: coordinator,
      builder: (context, _) {
        final visible = hasContent && coordinator.isScrollable;
        return AnimatedSwitcher(
          duration: transitionDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: visible
              ? _QuickScrollButtonSurface(
                  key: surfaceKey,
                  coordinator: coordinator,
                  animationsDisabled: animationsDisabled,
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
                  elevation: elevation,
                )
              : const SizedBox.shrink(
                  key: Key('thread-detail-quick-scroll-button-hidden'),
                ),
        );
      },
    );
  }
}

class _QuickScrollButtonSurface extends StatelessWidget {
  const _QuickScrollButtonSurface({
    super.key,
    required this.coordinator,
    required this.animationsDisabled,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.elevation,
  });

  final ThreadDetailQuickScrollCoordinator coordinator;
  final bool animationsDisabled;
  final Color backgroundColor;
  final Color foregroundColor;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final pointsToTop = coordinator.target == ThreadDetailQuickScrollTarget.top;
    final l10n = AppLocalizations.of(context);
    final label = pointsToTop
        ? l10n.threadDetailScrollTop
        : l10n.threadDetailScrollBottom;
    final rotationDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 180);
    const borderRadius = BorderRadius.all(Radius.circular(8));

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        // Long press belongs to the draggable host; hover still shows a tooltip.
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: Material(
          color: backgroundColor.withValues(alpha: 0.72),
          elevation: elevation,
          animationDuration: Duration.zero,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: coordinator.isNavigating
                ? null
                : () {
                    unawaited(
                      coordinator.navigate(animate: !animationsDisabled),
                    );
                  },
            borderRadius: borderRadius,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: AnimatedRotation(
                  key: const Key('thread-detail-quick-scroll-arrow'),
                  turns: pointsToTop ? 0.5 : 0,
                  duration: rotationDuration,
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 24,
                    color: foregroundColor.withValues(alpha: 0.72),
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
