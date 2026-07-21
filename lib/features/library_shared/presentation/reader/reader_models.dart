import 'package:flutter/material.dart';

@immutable
class ReaderChromeInsets {
  const ReaderChromeInsets({
    this.top = 0,
    this.bottom = 0,
    this.safeAreaBottom = 0,
    this.pageIndicatorReservedHeight = 0,
  }) : assert(top >= 0),
       assert(bottom >= 0),
       assert(safeAreaBottom >= 0),
       assert(pageIndicatorReservedHeight >= 0);

  const ReaderChromeInsets.zero() : this();

  final double top;
  final double bottom;
  final double safeAreaBottom;
  final double pageIndicatorReservedHeight;

  double get topInset => top;

  double get persistentBottomInset => bottom + safeAreaBottom;

  double get bottomInset => persistentBottomInset + pageIndicatorReservedHeight;

  @override
  bool operator ==(Object other) {
    return other is ReaderChromeInsets &&
        other.top == top &&
        other.bottom == bottom &&
        other.safeAreaBottom == safeAreaBottom &&
        other.pageIndicatorReservedHeight == pageIndicatorReservedHeight;
  }

  @override
  int get hashCode =>
      Object.hash(top, bottom, safeAreaBottom, pageIndicatorReservedHeight);
}

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
  }) : value = null,
       min = 0,
       max = null,
       divisions = null,
       leadingLabel = null,
       trailingLabel = null,
       sliderEnabled = true;

  const ReaderProgressConfig.discrete({
    required this.current,
    required this.total,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
    this.onPrevious,
    this.onNext,
    this.previousEnabled = true,
    this.nextEnabled = true,
    this.sliderEnabled = true,
    this.interactionLocked = false,
    this.previousTooltip = '上一章',
    this.nextTooltip = '下一章',
    this.previousIcon = Icons.skip_previous,
    this.nextIcon = Icons.skip_next,
    this.leadingLabel,
    this.trailingLabel,
  }) : value = null,
       min = 0,
       max = null,
       divisions = null;

  const ReaderProgressConfig.continuous({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.leadingLabel,
    required this.trailingLabel,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeStart,
    this.onPrevious,
    this.onNext,
    this.previousEnabled = true,
    this.nextEnabled = true,
    this.sliderEnabled = true,
    this.interactionLocked = false,
    this.previousTooltip = '上一章',
    this.nextTooltip = '下一章',
    this.previousIcon = Icons.skip_previous,
    this.nextIcon = Icons.skip_next,
  }) : current = null,
       total = null;

  final int? current;
  final int? total;
  final double? value;
  final double min;
  final double? max;
  final int? divisions;
  final String? leadingLabel;
  final String? trailingLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool previousEnabled;
  final bool nextEnabled;
  final bool sliderEnabled;
  final bool interactionLocked;
  final String previousTooltip;
  final String nextTooltip;
  final IconData previousIcon;
  final IconData nextIcon;
}
