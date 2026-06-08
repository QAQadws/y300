import 'package:flutter/material.dart';

class ReaderToolbarAction {
  const ReaderToolbarAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
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
  const ReaderBottomBarConfig({
    required this.progress,
    required this.actions,
  });

  final ReaderProgressConfig progress;
  final List<ReaderToolbarAction> actions;
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
}
