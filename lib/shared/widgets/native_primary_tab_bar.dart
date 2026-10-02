import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

/// Primary sections on native content pages, independent of AppBar colors.
class NativePrimaryTabBar extends StatelessWidget {
  const NativePrimaryTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.onTap,
  });

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final labelStyle =
        (theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(
          fontWeight: FontWeight.w600,
        );
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return Material(
      color: palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = math.max(
            1.0,
            constraints.maxWidth / labels.length - 16,
          );
          var height = 48.0;
          // Let long translations and large text wrap without reducing the
          // touch target or squeezing the labels into a fixed-height AppBar.
          for (final label in labels) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: labelStyle),
              textScaler: textScaler,
              textDirection: direction,
              locale: Localizations.maybeLocaleOf(context),
            )..layout(maxWidth: labelWidth);
            height = math.max(height, (painter.height + 20).ceilToDouble());
            painter.dispose();
          }
          return TabBar(
            controller: controller,
            onTap: onTap,
            labelColor: palette.accent,
            unselectedLabelColor: palette.muted,
            labelStyle: labelStyle,
            unselectedLabelStyle: labelStyle.copyWith(
              fontWeight: FontWeight.w400,
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            textScaler: textScaler,
            indicator: NativePrimaryTabIndicator(color: palette.accent),
            indicatorSize: TabBarIndicatorSize.tab,
            automaticIndicatorColorAdjustment: false,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStatePropertyAll(palette.stateLayer),
            tabs: [
              for (final label in labels)
                Tab(
                  height: height,
                  child: Text(label, textAlign: TextAlign.center),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Keeps the underline short even when a tab occupies half the page width.
class NativePrimaryTabIndicator extends Decoration {
  const NativePrimaryTabIndicator({required this.color});

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ShortUnderlinePainter(color, onChanged);
}

class _ShortUnderlinePainter extends BoxPainter {
  _ShortUnderlinePainter(this.color, super.onChanged);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = Rect.fromLTWH(
      offset.dx + (size.width - 24) / 2,
      offset.dy + size.height - 9,
      24,
      3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
      Paint()..color = color,
    );
  }
}
