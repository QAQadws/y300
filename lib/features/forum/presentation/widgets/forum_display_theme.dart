import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

@immutable
class ForumDisplayThemePalette {
  const ForumDisplayThemePalette({
    required this.background,
    required this.panel,
    required this.section,
    required this.sectionElevated,
    required this.card,
    required this.metricBackground,
    required this.disabled,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.warning,
    required this.onWarning,
    required this.title,
    required this.threadTitle,
    required this.author,
    required this.bodyText,
    required this.muted,
    required this.softText,
    required this.disabledText,
    required this.tag,
    required this.filterSelectedBackground,
    required this.filterSelectedForeground,
    required this.threadPressedOverlay,
    required this.avatarBackground,
    required this.avatarForeground,
    required this.surfaceContainer,
    required this.surfaceContainerLow,
    required this.surfaceContainerHigh,
    required this.stateLayer,
    required this.selectedContainer,
    required this.selectedForeground,
    required this.outlineSoft,
    required this.threadBadgeBackground,
    required this.threadBadgeForeground,
    required this.threadBadgeOutline,
  });

  final Color background;
  final Color panel;
  final Color section;
  final Color sectionElevated;
  final Color card;
  final Color metricBackground;
  final Color disabled;
  final Color border;
  final Color accent;
  final Color onAccent;
  final Color warning;
  final Color onWarning;
  final Color title;
  final Color threadTitle;
  final Color author;
  final Color bodyText;
  final Color muted;
  final Color softText;
  final Color disabledText;
  final Color tag;
  final Color filterSelectedBackground;
  final Color filterSelectedForeground;
  final Color threadPressedOverlay;
  final Color avatarBackground;
  final Color avatarForeground;
  final Color surfaceContainer;
  final Color surfaceContainerLow;
  final Color surfaceContainerHigh;
  final Color stateLayer;
  final Color selectedContainer;
  final Color selectedForeground;
  final Color outlineSoft;
  final Color threadBadgeBackground;
  final Color threadBadgeForeground;
  final Color threadBadgeOutline;

  static ForumDisplayThemePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final appBarBackground =
        theme.appBarTheme.backgroundColor ?? scheme.primary;
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? scheme.onPrimary;
    if (!isDark) {
      return ForumDisplayThemePalette(
        background: AppThemeTokens.scaffoldBackground,
        panel: AppThemeTokens.forumWebviewSectionBackground,
        section: AppThemeTokens.forumWebviewSectionBackground,
        sectionElevated: AppThemeTokens.forumWebviewSectionBackground,
        card: AppThemeTokens.forumWebviewSectionBackground,
        metricBackground: AppThemeTokens.navigationBarBackground.withValues(
          alpha: 0.58,
        ),
        disabled: scheme.surfaceContainerHighest,
        border: scheme.outlineVariant.withValues(alpha: 0.42),
        accent: AppThemeTokens.appBarBackground,
        onAccent: AppThemeTokens.appBarForeground,
        warning: Colors.redAccent.shade200,
        onWarning: Colors.white,
        title: AppThemeTokens.appBarBackground,
        threadTitle: const Color(0xFF2F2117),
        author: const Color(0xFF8A5A2B),
        bodyText: const Color(0xFF6F5B46),
        muted: const Color(0xFF7D6750),
        softText: const Color(0xFF8F949A),
        disabledText: const Color(0xFFBBAA91),
        tag: const Color(0xFF8A5A2B),
        filterSelectedBackground: AppThemeTokens.navigationBarBackground
            .withValues(alpha: 0.72),
        filterSelectedForeground: AppThemeTokens.appBarBackground,
        threadPressedOverlay: AppThemeTokens.appBarBackground.withValues(
          alpha: 0.06,
        ),
        avatarBackground: AppThemeTokens.navigationBarBackground,
        avatarForeground: AppThemeTokens.appBarBackground,
        surfaceContainer: AppThemeTokens.forumWebviewSectionBackground,
        surfaceContainerLow:
            Color.lerp(
              AppThemeTokens.scaffoldBackground,
              AppThemeTokens.forumWebviewSectionBackground,
              0.62,
            ) ??
            AppThemeTokens.forumWebviewSectionBackground,
        surfaceContainerHigh:
            Color.lerp(
              AppThemeTokens.navigationBarBackground,
              AppThemeTokens.forumWebviewSectionBackground,
              0.58,
            ) ??
            AppThemeTokens.navigationBarBackground,
        stateLayer: AppThemeTokens.appBarBackground.withValues(alpha: 0.08),
        selectedContainer: AppThemeTokens.navigationBarBackground.withValues(
          alpha: 0.74,
        ),
        selectedForeground: AppThemeTokens.appBarBackground,
        outlineSoft: scheme.outlineVariant.withValues(alpha: 0.28),
        threadBadgeBackground: appBarBackground,
        threadBadgeForeground: appBarForeground,
        threadBadgeOutline: appBarBackground.withValues(alpha: 0.72),
      );
    }
    return ForumDisplayThemePalette(
      background: theme.scaffoldBackgroundColor,
      panel: scheme.surfaceContainer,
      section: scheme.surfaceContainer,
      sectionElevated: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.64 : 0.46,
      ),
      card: scheme.surfaceContainerLowest,
      metricBackground: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.82 : 0.54,
      ),
      disabled: scheme.surfaceContainerHighest,
      border: scheme.outlineVariant.withValues(alpha: isDark ? 0.78 : 0.66),
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      warning: scheme.error,
      onWarning: scheme.onError,
      title: scheme.onSurface,
      threadTitle: scheme.onSurface,
      author: scheme.primary,
      bodyText: scheme.onSurfaceVariant,
      muted: scheme.onSurfaceVariant,
      softText: scheme.onSurfaceVariant.withValues(alpha: isDark ? 0.82 : 0.78),
      disabledText: scheme.onSurfaceVariant.withValues(
        alpha: isDark ? 0.44 : 0.52,
      ),
      tag: scheme.primary,
      filterSelectedBackground: scheme.primaryContainer,
      filterSelectedForeground: scheme.onPrimaryContainer,
      threadPressedOverlay: scheme.primary.withValues(
        alpha: isDark ? 0.10 : 0.06,
      ),
      avatarBackground: scheme.secondaryContainer,
      avatarForeground: scheme.onSecondaryContainer,
      surfaceContainer: scheme.surfaceContainer,
      surfaceContainerLow: scheme.surfaceContainerLowest,
      surfaceContainerHigh: scheme.surfaceContainerHighest,
      stateLayer: scheme.primary.withValues(alpha: 0.10),
      selectedContainer: scheme.secondaryContainer,
      selectedForeground: scheme.onSecondaryContainer,
      outlineSoft: scheme.outlineVariant.withValues(alpha: 0.44),
      threadBadgeBackground: appBarBackground,
      threadBadgeForeground: appBarForeground,
      threadBadgeOutline: appBarForeground.withValues(alpha: 0.22),
    );
  }
}
