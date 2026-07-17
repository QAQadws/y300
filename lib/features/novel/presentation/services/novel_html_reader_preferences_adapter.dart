import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

class NovelHtmlReaderPreferencesAdapter {
  const NovelHtmlReaderPreferencesAdapter();

  ForumHtmlReaderPreferences map(NovelReaderPreferences preferences) {
    return ForumHtmlReaderPreferences(
      typography: RichTextTypography(
        fontScale: preferences.fontSize / 14,
        lineHeightScale: preferences.lineHeight,
        paragraphSpacing: preferences.paragraphSpacing,
      ),
      conversionMode: _conversionMode(preferences.conversionMode),
      preserveAuthorFontSize: true,
    );
  }

  TextConversionMode _conversionMode(NovelReaderConversionMode mode) {
    switch (mode) {
      case NovelReaderConversionMode.none:
        return TextConversionMode.none;
      case NovelReaderConversionMode.toSimplified:
        return TextConversionMode.toSimplified;
      case NovelReaderConversionMode.toTraditional:
        return TextConversionMode.toTraditional;
    }
  }
}
