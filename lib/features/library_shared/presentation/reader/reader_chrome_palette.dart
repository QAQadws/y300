import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

/// Semantic colors for reader chrome shared by comic and novel readers.
///
/// Reading content preferences remain outside this palette; it only controls
/// menus, overlays, progress controls, and transient chrome surfaces.
@immutable
final class ReaderChromePalette {
  const ReaderChromePalette({
    required this.chromeBackground,
    required this.chromeForeground,
    required this.progressTrackBackground,
    required this.overlayScrim,
    required this.transitionCardBackground,
    required this.imageLoadingPlaceholderBackground,
    required this.onChromeVariant,
  });

  final Color chromeBackground;
  final Color chromeForeground;
  final Color progressTrackBackground;
  final Color overlayScrim;
  final Color transitionCardBackground;
  final Color imageLoadingPlaceholderBackground;
  final Color onChromeVariant;
}

final class ReaderChromePaletteResolver {
  const ReaderChromePaletteResolver();

  ReaderChromePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final appTheme = theme.extension<Y300ThemeExtension>();
    final chromeBase =
        appTheme?.readerChromeBackground ?? scheme.surfaceContainer;
    final chromeForeground =
        appTheme?.readerChromeForeground ?? scheme.onSurface;
    final progressTrack =
        appTheme?.readerProgressTrackBackground ??
        scheme.surfaceContainerHighest;
    final overlayScrim =
        appTheme?.readerOverlayScrim ??
        Colors.black.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.48 : 0.24,
        );

    return ReaderChromePalette(
      chromeBackground: chromeBase.withValues(alpha: 0.94),
      chromeForeground: chromeForeground,
      progressTrackBackground: progressTrack,
      overlayScrim: overlayScrim,
      transitionCardBackground: Color.alphaBlend(
        chromeBase.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.92 : 0.88,
        ),
        scheme.surface,
      ),
      imageLoadingPlaceholderBackground: Color.alphaBlend(
        progressTrack.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.54 : 0.38,
        ),
        scheme.surface,
      ),
      onChromeVariant: scheme.onSurfaceVariant,
    );
  }
}
