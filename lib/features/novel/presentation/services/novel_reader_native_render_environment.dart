import 'package:flutter/material.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

import 'novel_reader_display_resolvers.dart';
import 'novel_reader_native_typography_adapter.dart';
import 'novel_forum_html_render_theme_factory.dart';

/// One native layout input captured from a coherent, loaded font snapshot.
/// No Context, Theme, provider or native layout survives in this value.
final class NovelReaderNativeRenderEnvironment {
  const NovelReaderNativeRenderEnvironment._(
    this.reader,
    this.textScaler,
    this.backgroundColor,
    this.avoidIsolatedLines,
    this.keepHeadingWithNext,
  );

  factory NovelReaderNativeRenderEnvironment.capture(
    BuildContext context, {
    required NovelReaderPreferences preferences,
    required ResolvedFont resolvedFont,
    ForumBodyStylePolicy? policy,
  }) {
    if (preferences.fontFamily != resolvedFont.id ||
        (resolvedFont.isSystem && resolvedFont.fontFamily != null) ||
        (!resolvedFont.isSystem &&
            (resolvedFont.fontFamily == null ||
                resolvedFont.fontFamily!.trim().isEmpty))) {
      throw StateError('Native reader font snapshot is not resolved');
    }
    final theme = Theme.of(context);
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      resolvedFont: resolvedFont,
      theme: theme,
      palette: palette,
    );
    // A fresh Theme baseline prevents copyWith(null)/inherited DefaultTextStyle
    // from retaining the previously selected imported family on system fallback.
    final nativeTypography = resolveNovelReaderNativeTypography(
      preferences,
      policy,
    );
    final textStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .merge(typography.body)
        .copyWith(
          inherit: false,
          locale: Localizations.maybeLocaleOf(context),
          letterSpacing: nativeTypography.letterSpacing,
          wordSpacing: nativeTypography.wordSpacing,
          fontWeight: nativeTypography.fontWeight,
        );
    return NovelReaderNativeRenderEnvironment._(
      ForumBodyReaderStyle(
        textStyle: textStyle,
        fontRevision: resolvedFont.cacheKey,
        linkColor: palette.link,
        textAlign: nativeTypography.textAlign ?? typography.textAlign,
        textDirection: Directionality.of(context),
        paragraphBefore: nativeTypography.paragraphBefore,
        paragraphAfter: nativeTypography.paragraphAfter,
        firstLineIndent: nativeTypography.indent,
        compressBlankLines: preferences.compressBlankLines,
        removeSourceIndent: preferences.removeSourceIndent,
        roleFontScales: nativeTypography.roleFontScales,
        rubyFontScale: nativeTypography.rubyFontScale,
        showRubyAnnotations: preferences.showRubyAnnotations,
        policy: nativeTypography.policy,
        theme: const NovelForumHtmlRenderThemeFactory().fromPalette(palette),
      ),
      // Unlike the old fwfh compatibility path, native paragraphs use scale()
      // at every effective author/reader font size. Do not flatten to one factor.
      MediaQuery.textScalerOf(context),
      palette.background,
      preferences.avoidIsolatedLines &&
          preferences.flowMode != NovelReaderFlowMode.vertical,
      preferences.keepHeadingWithNext &&
          preferences.flowMode != NovelReaderFlowMode.vertical,
    );
  }

  final ForumBodyReaderStyle reader;
  final TextScaler textScaler;
  final Color backgroundColor;
  final bool avoidIsolatedLines;
  final bool keepHeadingWithNext;
}
