import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_corner_dock.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_quick_scroll_preferences_controller.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_quick_scroll_button.dart';
import 'package:y300/l10n/app_localizations.dart';

class ThreadDetailQuickScrollDock extends ConsumerWidget {
  const ThreadDetailQuickScrollDock({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final side = ref
        .watch(threadQuickScrollPreferencesControllerProvider)
        .value;
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: coordinator,
      builder: (context, _) => ReaderCornerDock(
        side: side == null
            ? null
            : side == ThreadQuickScrollDockSide.left
            ? ReaderCornerDockSide.left
            : ReaderCornerDockSide.right,
        visible: hasContent && coordinator.isScrollable,
        onSideChanged: (next) => ref
            .read(threadQuickScrollPreferencesControllerProvider.notifier)
            .setSide(
              next == ReaderCornerDockSide.left
                  ? ThreadQuickScrollDockSide.left
                  : ThreadQuickScrollDockSide.right,
            ),
        dragHint: l10n.threadQuickScrollDragHint,
        moveLeftLabel: l10n.threadQuickScrollMoveLeft,
        moveRightLabel: l10n.threadQuickScrollMoveRight,
        saveFailedLabel: l10n.threadQuickScrollPositionSaveFailed,
        child: ThreadDetailQuickScrollButton(
          coordinator: coordinator,
          hasContent: side != null && hasContent,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        feedbackBuilder: (elevation) => ThreadDetailQuickScrollButton(
          surfaceKey: const Key('thread-quick-scroll-drag-feedback'),
          coordinator: coordinator,
          hasContent: hasContent,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: elevation,
        ),
      ),
    );
  }
}
