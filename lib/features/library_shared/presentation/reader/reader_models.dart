import 'package:flutter/material.dart';

class ReaderToolbarAction {
  const ReaderToolbarAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.dismissMenu = true,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  /// Whether the reader overlay should close before invoking the action.
  ///
  /// Persistent controls such as a mode cycle can keep the menu open so the
  /// user can repeat the action without reopening the overlay.
  final bool dismissMenu;
}

class ReaderTopBarConfig {
  const ReaderTopBarConfig({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.onBack,
    this.onTitleTap,
  });

  final String title;
  final String subtitle;
  final List<ReaderToolbarAction> actions;
  final VoidCallback onBack;
  final VoidCallback? onTitleTap;
}

class ReaderBottomBarConfig {
  const ReaderBottomBarConfig({required this.actions, this.progress});

  final List<ReaderToolbarAction> actions;
  final ReaderProgressConfig? progress;
}

class ReaderProgressConfig {
  const ReaderProgressConfig({
    required this.current,
    required this.total,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
    this.onPrevious,
    this.onNext,
    this.previousEnabled = true,
    this.nextEnabled = true,
    this.interactionLocked = false,
    this.previousTooltip = '上一章',
    this.nextTooltip = '下一章',
    this.previousIcon = Icons.skip_previous,
    this.nextIcon = Icons.skip_next,
  });

  final int current;
  final int total;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool previousEnabled;
  final bool nextEnabled;
  final bool interactionLocked;
  final String previousTooltip;
  final String nextTooltip;
  final IconData previousIcon;
  final IconData nextIcon;
}
