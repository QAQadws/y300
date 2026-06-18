import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

/// Semantic colors used by shared shelf widgets.
///
/// The resolver accepts plain [ThemeData] so shelf widgets can be tested with a
/// regular MaterialApp while still consuming Y300's richer theme extension when
/// the app theme is mounted.
@immutable
final class ShelfThemePalette {
  const ShelfThemePalette({
    required this.categoryBarBackground,
    required this.categorySelectedBackground,
    required this.categorySelectedForeground,
    required this.categoryDivider,
    required this.selectedBorder,
    required this.listItemBackground,
    required this.taskProgressBackground,
    required this.coverPlaceholderBackground,
  });

  final Color categoryBarBackground;
  final Color categorySelectedBackground;
  final Color categorySelectedForeground;
  final Color categoryDivider;
  final Color selectedBorder;
  final Color listItemBackground;
  final Color taskProgressBackground;
  final Color coverPlaceholderBackground;
}

final class ShelfThemePaletteResolver {
  const ShelfThemePaletteResolver();

  ShelfThemePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final appTheme = theme.extension<Y300ThemeExtension>();
    final categoryBarBackground =
        appTheme?.shelfCategoryBarBackground ?? scheme.surface;
    final selectedBackground =
        appTheme?.shelfCategorySelectedBackground ?? scheme.primary;
    final coverPlaceholderBackground =
        appTheme?.coverPlaceholderBackground ?? scheme.surfaceContainerHighest;

    return ShelfThemePalette(
      categoryBarBackground: categoryBarBackground,
      categorySelectedBackground: selectedBackground,
      categorySelectedForeground:
          appTheme?.shelfCategorySelectedForeground ?? scheme.onPrimary,
      categoryDivider: appTheme?.shelfCategoryDivider ?? scheme.outlineVariant,
      selectedBorder: selectedBackground,
      listItemBackground: _blendForContainer(
        foreground: coverPlaceholderBackground,
        background: scheme.surface,
        alpha: theme.brightness == Brightness.dark ? 0.52 : 0.28,
      ),
      taskProgressBackground: _blendForContainer(
        foreground: categoryBarBackground,
        background: scheme.surface,
        alpha: theme.brightness == Brightness.dark ? 0.88 : 0.72,
      ),
      coverPlaceholderBackground: coverPlaceholderBackground,
    );
  }

  Color _blendForContainer({
    required Color foreground,
    required Color background,
    required double alpha,
  }) {
    return Color.alphaBlend(
      foreground.withValues(alpha: alpha),
      background,
    );
  }
}
