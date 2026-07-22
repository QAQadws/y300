import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';

class ThreadDetailQuickScrollButton extends StatelessWidget {
  const ThreadDetailQuickScrollButton({
    super.key,
    required this.coordinator,
    required this.hasContent,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final ThreadDetailQuickScrollCoordinator coordinator;
  final bool hasContent;
  final Color backgroundColor;
  final Color foregroundColor;

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
                  key: const Key('thread-detail-quick-scroll-button'),
                  coordinator: coordinator,
                  animationsDisabled: animationsDisabled,
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
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
  });

  final ThreadDetailQuickScrollCoordinator coordinator;
  final bool animationsDisabled;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final pointsToTop = coordinator.target == ThreadDetailQuickScrollTarget.top;
    final label = pointsToTop ? '滚动到顶部' : '滚动到底部';
    final rotationDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 180);
    const borderRadius = BorderRadius.all(Radius.circular(8));

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: backgroundColor.withValues(alpha: 0.72),
          elevation: 2,
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
