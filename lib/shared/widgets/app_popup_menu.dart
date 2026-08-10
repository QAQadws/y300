import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Application popup menu with content-driven width and aligned labels.
///
/// Flutter's stock popup route rounds its width to 56dp steps and aligns every
/// item to the leading edge while still reserving a 112dp minimum width. That
/// leaves short CJK labels with excessive trailing whitespace. This wrapper
/// measures localized labels and supplies an exact, responsive width instead.
class AppPopupMenuButton<T> extends StatelessWidget {
  const AppPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.icon,
    this.enabled = true,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final Widget? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final entries = itemBuilder(context);
    final labels = <String>[
      for (final entry in entries)
        if (entry is AppPopupMenuItem<T>) entry.label,
    ];

    return PopupMenuButton<T>(
      constraints: labels.isEmpty
          ? null
          : AppPopupMenuLayout.constraintsFor(context, labels),
      tooltip: tooltip,
      icon: icon,
      enabled: enabled,
      onSelected: onSelected,
      onCanceled: onCanceled,
      itemBuilder: (_) => entries,
    );
  }
}

/// Leading-aligned, single-line popup action used with [AppPopupMenuButton].
class AppPopupMenuItem<T> extends PopupMenuItem<T> {
  AppPopupMenuItem({
    super.key,
    required String label,
    super.value,
    super.onTap,
    super.enabled = true,
  }) : label = label,
       super(
         padding: const EdgeInsets.symmetric(horizontal: 16),
         child: _AppPopupMenuLabel(label),
       );

  final String label;
}

final class AppPopupMenuLayout {
  const AppPopupMenuLayout._();

  static const double horizontalItemPadding = 32;
  static const double minimumWidth = 80;
  static const double maximumWidth = 240;
  static const double screenMargin = 16;

  static BoxConstraints constraintsFor(
    BuildContext context,
    Iterable<String> labels,
  ) {
    final theme = Theme.of(context);
    final popupTheme = PopupMenuTheme.of(context);
    final labelStyle = theme.useMaterial3
        ? popupTheme.labelTextStyle?.resolve(const <WidgetState>{}) ??
              theme.textTheme.labelLarge ??
              const TextStyle(fontSize: 14)
        : popupTheme.textStyle ??
              theme.textTheme.titleMedium ??
              const TextStyle(fontSize: 16);
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    var widestLabel = 0.0;

    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      widestLabel = math.max(widestLabel, painter.width);
    }

    final availableWidth = math.max(
      minimumWidth,
      MediaQuery.sizeOf(context).width - screenMargin * 2,
    );
    final upperBound = math.min(maximumWidth, availableWidth);
    final width = (widestLabel + horizontalItemPadding)
        .ceilToDouble()
        .clamp(minimumWidth, upperBound)
        .toDouble();
    return BoxConstraints.tightFor(width: width);
  }
}

class _AppPopupMenuLabel extends StatelessWidget {
  const _AppPopupMenuLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
      ),
    );
  }
}
