import 'package:flutter/material.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_tone_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

final class ForumHtmlRenderThemeFactory {
  const ForumHtmlRenderThemeFactory({
    RichTextToneResolver toneResolver = const MaterialRichTextToneResolver(),
  }) : _toneResolver = toneResolver;

  final RichTextToneResolver _toneResolver;

  ForumHtmlThemeContext fromThreadPalette({
    required ThreadDetailNativePalette palette,
    required Brightness brightness,
  }) {
    final surface = _opaqueOver(palette.card, palette.background);
    final foreground = _opaqueOver(palette.bodyText, surface);
    return ForumHtmlThemeContext(
      brightness: _brightness(brightness),
      surface: surface,
      foreground: foreground,
      link: _readableLink(
        requested: palette.accent,
        surface: surface,
        fallback: foreground,
      ),
      quoteSurface: _opaqueOver(palette.panelBackground, surface),
      quoteForeground: foreground,
      codeSurface: _opaqueOver(palette.cardElevated, surface),
      codeForeground: foreground,
    );
  }

  ForumHtmlThemeContext fromMaterialTheme({
    required ThemeData theme,
    required Color surface,
    Color? foreground,
  }) {
    final scheme = theme.colorScheme;
    final resolvedSurface = _opaqueOver(surface, scheme.surface);
    final resolvedForeground = _opaqueOver(
      foreground ?? scheme.onSurface,
      resolvedSurface,
    );
    final quoteSurface =
        Color.lerp(resolvedSurface, scheme.surfaceContainerHighest, 0.72) ??
        scheme.surfaceContainerHighest;
    final codeSurface =
        Color.lerp(resolvedSurface, scheme.surfaceContainerHighest, 0.48) ??
        scheme.surfaceContainerHighest;
    return ForumHtmlThemeContext(
      brightness: _brightness(scheme.brightness),
      surface: resolvedSurface,
      foreground: resolvedForeground,
      link: _readableLink(
        requested: scheme.primary,
        surface: resolvedSurface,
        fallback: resolvedForeground,
      ),
      quoteSurface: _opaqueOver(quoteSurface, resolvedSurface),
      quoteForeground: resolvedForeground,
      codeSurface: _opaqueOver(codeSurface, resolvedSurface),
      codeForeground: resolvedForeground,
    );
  }

  Color _readableLink({
    required Color requested,
    required Color surface,
    required Color fallback,
  }) {
    try {
      return _toneResolver.resolveReadableForeground(
        requested: requested,
        background: surface,
        fallback: fallback,
        minimumContrast:
            ForumHtmlColorAdaptationPolicy.standard.minimumTextContrast,
      );
    } on RichTextToneResolutionFailure {
      return fallback;
    }
  }

  Color _opaqueOver(Color color, Color background) {
    if ((color.toARGB32() >>> 24) == 0xFF) {
      return color;
    }
    return Color.alphaBlend(color, background);
  }

  ForumHtmlBrightness _brightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? ForumHtmlBrightness.dark
        : ForumHtmlBrightness.light;
  }
}
