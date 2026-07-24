import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

@immutable
class ThreadDetailNativePalette {
  const ThreadDetailNativePalette({
    required this.background,
    required this.card,
    required this.cardElevated,
    required this.metricBackground,
    required this.chipBackground,
    required this.panelBackground,
    required this.accent,
    required this.onAccent,
    required this.title,
    required this.author,
    required this.bodyText,
    required this.muted,
    required this.softText,
    required this.border,
    required this.outlineSoft,
    required this.stateLayer,
    required this.avatarBackground,
    required this.avatarForeground,
    required this.pollTrack,
  });

  final Color background;
  final Color card;
  final Color cardElevated;
  final Color metricBackground;
  final Color chipBackground;
  final Color panelBackground;
  final Color accent;
  final Color onAccent;
  final Color title;
  final Color author;
  final Color bodyText;
  final Color muted;
  final Color softText;
  final Color border;
  final Color outlineSoft;
  final Color stateLayer;
  final Color avatarBackground;
  final Color avatarForeground;
  final Color pollTrack;

  static ThreadDetailNativePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final appBarBackground =
        theme.appBarTheme.backgroundColor ?? scheme.primary;
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? scheme.onPrimary;

    if (!isDark) {
      final listTagChipBackground =
          (Color.lerp(
                    AppThemeTokens.navigationBarBackground,
                    AppThemeTokens.forumWebviewSectionBackground,
                    0.58,
                  ) ??
                  AppThemeTokens.navigationBarBackground)
              .withValues(alpha: 0.42);
      return ThreadDetailNativePalette(
        background: AppThemeTokens.scaffoldBackground,
        card: AppThemeTokens.forumWebviewSectionBackground,
        cardElevated: AppThemeTokens.forumWebviewSectionBackground,
        metricBackground: AppThemeTokens.navigationBarBackground.withValues(
          alpha: 0.58,
        ),
        chipBackground: listTagChipBackground,
        panelBackground: AppThemeTokens.navigationBarBackground.withValues(
          alpha: 0.18,
        ),
        accent: appBarBackground,
        onAccent: appBarForeground,
        title: AppThemeTokens.appBarBackground,
        author: const Color(0xFF8A5A2B),
        bodyText: const Color(0xFF4F3A2A),
        muted: const Color(0xFF7D6750),
        softText: const Color(0xFF8F7A62),
        border: scheme.outlineVariant.withValues(alpha: 0.28),
        outlineSoft: scheme.outlineVariant.withValues(alpha: 0.22),
        stateLayer: AppThemeTokens.appBarBackground.withValues(alpha: 0.07),
        avatarBackground: AppThemeTokens.navigationBarBackground,
        avatarForeground: AppThemeTokens.appBarBackground,
        pollTrack: AppThemeTokens.scaffoldBackground.withValues(alpha: 0.86),
      );
    }

    return ThreadDetailNativePalette(
      background: theme.scaffoldBackgroundColor,
      card: scheme.surfaceContainer,
      cardElevated: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
      metricBackground: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
      chipBackground: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      panelBackground: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      title: scheme.onSurface,
      author: scheme.primary,
      bodyText: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      softText: scheme.onSurfaceVariant.withValues(alpha: 0.78),
      border: scheme.outlineVariant.withValues(alpha: 0.52),
      outlineSoft: scheme.outlineVariant.withValues(alpha: 0.36),
      stateLayer: scheme.primary.withValues(alpha: 0.10),
      avatarBackground: scheme.secondaryContainer,
      avatarForeground: scheme.onSecondaryContainer,
      pollTrack: scheme.surfaceContainerLowest,
    );
  }
}
