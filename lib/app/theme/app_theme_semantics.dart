import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_palette.dart';

/// Semantic colors shared by native forum, thread, and profile surfaces.
@immutable
final class Y300NativeContentColors {
  const Y300NativeContentColors({
    required this.background,
    required this.card,
    required this.elevatedCard,
    required this.metricBackground,
    required this.panelBackground,
    required this.accent,
    required this.onAccent,
    required this.title,
    required this.itemTitle,
    required this.author,
    required this.body,
    required this.supportingText,
    required this.muted,
    required this.soft,
    required this.neutralText,
    required this.tertiaryText,
    required this.disabled,
    required this.stateLayer,
    required this.subtleStateLayer,
    required this.avatarBackground,
    required this.avatarForeground,
    required this.selectionBackground,
    required this.selectionForeground,
    required this.notificationBadgeBackground,
    required this.translucentSurface,
  });

  final Color background;
  final Color card;
  final Color elevatedCard;
  final Color metricBackground;
  final Color panelBackground;
  final Color accent;
  final Color onAccent;
  final Color title;
  final Color itemTitle;
  final Color author;
  final Color body;
  final Color supportingText;
  final Color muted;
  final Color soft;
  final Color neutralText;
  final Color tertiaryText;
  final Color disabled;
  final Color stateLayer;
  final Color subtleStateLayer;
  final Color avatarBackground;
  final Color avatarForeground;
  final Color selectionBackground;
  final Color selectionForeground;
  final Color notificationBadgeBackground;
  final Color translucentSurface;

  factory Y300NativeContentColors.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = theme.appBarTheme.backgroundColor ?? scheme.primary;
    final onAccent = theme.appBarTheme.foregroundColor ?? scheme.onPrimary;
    return Y300NativeContentColors(
      background: theme.scaffoldBackgroundColor,
      card: scheme.surfaceContainer,
      elevatedCard: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.68 : 0.54,
      ),
      metricBackground: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.72 : 0.58,
      ),
      panelBackground: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.28 : 0.22,
      ),
      accent: accent,
      onAccent: onAccent,
      title: accent,
      itemTitle: scheme.onSurface,
      author: scheme.primary,
      body: scheme.onSurface,
      supportingText: scheme.onSurfaceVariant,
      muted: scheme.onSurfaceVariant,
      soft: scheme.onSurfaceVariant.withValues(alpha: isDark ? 0.78 : 0.82),
      neutralText: scheme.onSurfaceVariant.withValues(
        alpha: isDark ? 0.78 : 0.82,
      ),
      tertiaryText: scheme.onSurfaceVariant.withValues(
        alpha: isDark ? 0.74 : 0.78,
      ),
      disabled: scheme.onSurfaceVariant.withValues(alpha: isDark ? 0.44 : 0.52),
      stateLayer: scheme.primary.withValues(alpha: isDark ? 0.10 : 0.07),
      subtleStateLayer: scheme.primary.withValues(alpha: isDark ? 0.10 : 0.06),
      avatarBackground: scheme.secondaryContainer,
      avatarForeground: scheme.onSecondaryContainer,
      selectionBackground: scheme.secondaryContainer,
      selectionForeground: scheme.onSecondaryContainer,
      notificationBadgeBackground: scheme.secondaryContainer,
      translucentSurface: scheme.surfaceContainerLowest.withValues(alpha: 0.68),
    );
  }

  Y300NativeContentColors lerp(Y300NativeContentColors other, double t) {
    return Y300NativeContentColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      elevatedCard: Color.lerp(elevatedCard, other.elevatedCard, t)!,
      metricBackground: Color.lerp(
        metricBackground,
        other.metricBackground,
        t,
      )!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      title: Color.lerp(title, other.title, t)!,
      itemTitle: Color.lerp(itemTitle, other.itemTitle, t)!,
      author: Color.lerp(author, other.author, t)!,
      body: Color.lerp(body, other.body, t)!,
      supportingText: Color.lerp(supportingText, other.supportingText, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      neutralText: Color.lerp(neutralText, other.neutralText, t)!,
      tertiaryText: Color.lerp(tertiaryText, other.tertiaryText, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      stateLayer: Color.lerp(stateLayer, other.stateLayer, t)!,
      subtleStateLayer: Color.lerp(
        subtleStateLayer,
        other.subtleStateLayer,
        t,
      )!,
      avatarBackground: Color.lerp(
        avatarBackground,
        other.avatarBackground,
        t,
      )!,
      avatarForeground: Color.lerp(
        avatarForeground,
        other.avatarForeground,
        t,
      )!,
      selectionBackground: Color.lerp(
        selectionBackground,
        other.selectionBackground,
        t,
      )!,
      selectionForeground: Color.lerp(
        selectionForeground,
        other.selectionForeground,
        t,
      )!,
      notificationBadgeBackground: Color.lerp(
        notificationBadgeBackground,
        other.notificationBadgeBackground,
        t,
      )!,
      translucentSurface: Color.lerp(
        translucentSurface,
        other.translucentSurface,
        t,
      )!,
    );
  }
}

/// Cross-feature semantic colors that do not map cleanly to Material roles.
@immutable
final class Y300ThemeExtension extends ThemeExtension<Y300ThemeExtension> {
  const Y300ThemeExtension({
    required this.shelfCategoryBarBackground,
    required this.shelfCategorySelectedBackground,
    required this.shelfCategorySelectedForeground,
    required this.shelfCategoryDivider,
    required this.readerChromeBackground,
    required this.readerChromeForeground,
    required this.readerProgressTrackBackground,
    required this.readerOverlayScrim,
    required this.contentHighlightBackground,
    required this.coverPlaceholderBackground,
    required this.nativeContent,
  });

  factory Y300ThemeExtension.light(AppThemePalette palette) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground: palette.surfaceContainer,
      shelfCategorySelectedBackground: palette.primary,
      shelfCategorySelectedForeground: palette.onPrimary,
      shelfCategoryDivider: palette.outlineVariant,
      readerChromeBackground: palette.surfaceContainer,
      readerChromeForeground: palette.onSurface,
      readerProgressTrackBackground: palette.surfaceContainerHighest,
      readerOverlayScrim: Colors.black.withValues(alpha: 0.18),
      contentHighlightBackground: const Color(0x66FFD54F),
      coverPlaceholderBackground: palette.surfaceContainerHighest,
      nativeContent: _nativeContent(palette),
    );
  }

  factory Y300ThemeExtension.dark(AppThemePalette palette) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground: palette.surfaceContainer,
      shelfCategorySelectedBackground: palette.primary,
      shelfCategorySelectedForeground: palette.onPrimary,
      shelfCategoryDivider: palette.outlineVariant,
      readerChromeBackground: palette.surfaceContainer,
      readerChromeForeground: palette.onSurface,
      readerProgressTrackBackground: palette.surfaceContainerHighest,
      readerOverlayScrim: Colors.black.withValues(alpha: 0.44),
      contentHighlightBackground: const Color(0x668A6500),
      coverPlaceholderBackground: palette.surfaceContainerHighest,
      nativeContent: _nativeContent(palette),
    );
  }

  final Color shelfCategoryBarBackground;
  final Color shelfCategorySelectedBackground;
  final Color shelfCategorySelectedForeground;
  final Color shelfCategoryDivider;
  final Color readerChromeBackground;
  final Color readerChromeForeground;
  final Color readerProgressTrackBackground;
  final Color readerOverlayScrim;
  final Color contentHighlightBackground;
  final Color coverPlaceholderBackground;
  final Y300NativeContentColors nativeContent;

  @override
  Y300ThemeExtension copyWith({
    Color? shelfCategoryBarBackground,
    Color? shelfCategorySelectedBackground,
    Color? shelfCategorySelectedForeground,
    Color? shelfCategoryDivider,
    Color? readerChromeBackground,
    Color? readerChromeForeground,
    Color? readerProgressTrackBackground,
    Color? readerOverlayScrim,
    Color? contentHighlightBackground,
    Color? coverPlaceholderBackground,
    Y300NativeContentColors? nativeContent,
  }) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground:
          shelfCategoryBarBackground ?? this.shelfCategoryBarBackground,
      shelfCategorySelectedBackground:
          shelfCategorySelectedBackground ??
          this.shelfCategorySelectedBackground,
      shelfCategorySelectedForeground:
          shelfCategorySelectedForeground ??
          this.shelfCategorySelectedForeground,
      shelfCategoryDivider: shelfCategoryDivider ?? this.shelfCategoryDivider,
      readerChromeBackground:
          readerChromeBackground ?? this.readerChromeBackground,
      readerChromeForeground:
          readerChromeForeground ?? this.readerChromeForeground,
      readerProgressTrackBackground:
          readerProgressTrackBackground ?? this.readerProgressTrackBackground,
      readerOverlayScrim: readerOverlayScrim ?? this.readerOverlayScrim,
      contentHighlightBackground:
          contentHighlightBackground ?? this.contentHighlightBackground,
      coverPlaceholderBackground:
          coverPlaceholderBackground ?? this.coverPlaceholderBackground,
      nativeContent: nativeContent ?? this.nativeContent,
    );
  }

  @override
  Y300ThemeExtension lerp(ThemeExtension<Y300ThemeExtension>? other, double t) {
    if (other is! Y300ThemeExtension) {
      return this;
    }
    return Y300ThemeExtension(
      shelfCategoryBarBackground: Color.lerp(
        shelfCategoryBarBackground,
        other.shelfCategoryBarBackground,
        t,
      )!,
      shelfCategorySelectedBackground: Color.lerp(
        shelfCategorySelectedBackground,
        other.shelfCategorySelectedBackground,
        t,
      )!,
      shelfCategorySelectedForeground: Color.lerp(
        shelfCategorySelectedForeground,
        other.shelfCategorySelectedForeground,
        t,
      )!,
      shelfCategoryDivider: Color.lerp(
        shelfCategoryDivider,
        other.shelfCategoryDivider,
        t,
      )!,
      readerChromeBackground: Color.lerp(
        readerChromeBackground,
        other.readerChromeBackground,
        t,
      )!,
      readerChromeForeground: Color.lerp(
        readerChromeForeground,
        other.readerChromeForeground,
        t,
      )!,
      readerProgressTrackBackground: Color.lerp(
        readerProgressTrackBackground,
        other.readerProgressTrackBackground,
        t,
      )!,
      readerOverlayScrim: Color.lerp(
        readerOverlayScrim,
        other.readerOverlayScrim,
        t,
      )!,
      contentHighlightBackground: Color.lerp(
        contentHighlightBackground,
        other.contentHighlightBackground,
        t,
      )!,
      coverPlaceholderBackground: Color.lerp(
        coverPlaceholderBackground,
        other.coverPlaceholderBackground,
        t,
      )!,
      nativeContent: nativeContent.lerp(other.nativeContent, t),
    );
  }

  static Y300NativeContentColors _nativeContent(AppThemePalette palette) {
    if (palette.family == AppThemeFamily.warmPaper &&
        palette.brightness == Brightness.light) {
      return Y300NativeContentColors(
        background: palette.scaffoldBackground,
        card: palette.surfaceContainer,
        elevatedCard: palette.surfaceContainer,
        metricBackground: palette.secondaryContainer.withValues(alpha: 0.58),
        panelBackground: palette.secondaryContainer.withValues(alpha: 0.18),
        accent: palette.appBarBackground,
        onAccent: palette.appBarForeground,
        title: palette.appBarBackground,
        itemTitle: palette.onSurface,
        author: palette.primary,
        body: const Color(0xFF4F3A2A),
        supportingText: const Color(0xFF6F5B46),
        muted: const Color(0xFF7D6750),
        soft: const Color(0xFF8F7A62),
        neutralText: const Color(0xFF8F949A),
        tertiaryText: const Color(0xFF9A8E82),
        disabled: const Color(0xFFBBAA91),
        stateLayer: palette.appBarBackground.withValues(alpha: 0.07),
        subtleStateLayer: palette.appBarBackground.withValues(alpha: 0.06),
        avatarBackground: palette.secondaryContainer,
        avatarForeground: palette.appBarBackground,
        selectionBackground: palette.secondaryContainer,
        selectionForeground: palette.appBarBackground,
        notificationBadgeBackground: const Color(0xFFF7DDC2),
        translucentSurface: Colors.white.withValues(alpha: 0.68),
      );
    }

    final isDark = palette.brightness == Brightness.dark;
    return Y300NativeContentColors(
      background: palette.scaffoldBackground,
      card: palette.surfaceContainer,
      elevatedCard: palette.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.68 : 0.54,
      ),
      metricBackground: palette.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.72 : 0.58,
      ),
      panelBackground: palette.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.28 : 0.22,
      ),
      accent: palette.primary,
      onAccent: palette.onPrimary,
      title: palette.appBarBackground,
      itemTitle: palette.onSurface,
      author: palette.primary,
      body: palette.onSurface,
      supportingText: palette.onSurfaceVariant,
      muted: palette.onSurfaceVariant,
      soft: palette.onSurfaceVariant.withValues(alpha: isDark ? 0.78 : 0.82),
      neutralText: palette.onSurfaceVariant.withValues(
        alpha: isDark ? 0.78 : 0.82,
      ),
      tertiaryText: palette.onSurfaceVariant.withValues(
        alpha: isDark ? 0.74 : 0.78,
      ),
      disabled: palette.onSurfaceVariant.withValues(
        alpha: isDark ? 0.44 : 0.52,
      ),
      stateLayer: palette.primary.withValues(alpha: isDark ? 0.10 : 0.07),
      subtleStateLayer: palette.primary.withValues(alpha: isDark ? 0.10 : 0.06),
      avatarBackground: palette.secondaryContainer,
      avatarForeground: palette.onSecondaryContainer,
      selectionBackground: palette.secondaryContainer,
      selectionForeground: palette.onSecondaryContainer,
      notificationBadgeBackground: palette.secondaryContainer,
      translucentSurface: palette.surfaceContainerLowest.withValues(
        alpha: 0.68,
      ),
    );
  }
}

extension Y300ThemeContext on BuildContext {
  Y300ThemeExtension get y300Theme {
    return Theme.of(this).extension<Y300ThemeExtension>()!;
  }
}

extension Y300ThemeData on ThemeData {
  Y300NativeContentColors get y300NativeContent {
    return extension<Y300ThemeExtension>()?.nativeContent ??
        Y300NativeContentColors.fromTheme(this);
  }
}
