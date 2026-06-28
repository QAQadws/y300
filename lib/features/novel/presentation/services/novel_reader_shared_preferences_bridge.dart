import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

/// Bridges novel-specific preferences onto the shared reader_shared value
/// objects, so the novel reader reuses the same typography and text-conversion
/// abstractions as the thread reader (composition over duplication).
extension NovelReaderPreferencesSharedBridge on NovelReaderPreferences {
  /// Shared text-conversion direction mapped from the novel preference enum.
  TextConversionMode get sharedConversionMode {
    switch (conversionMode) {
      case NovelReaderConversionMode.none:
        return TextConversionMode.none;
      case NovelReaderConversionMode.toSimplified:
        return TextConversionMode.toSimplified;
      case NovelReaderConversionMode.toTraditional:
        return TextConversionMode.toTraditional;
    }
  }

  /// Maps the absolute novel typography fields onto the shared scale-based
  /// [RichTextTypography].
  ///
  /// Novel preferences store absolute font size / line height (historically),
  /// while the shared value object uses scales relative to an 18pt / 1.5×
  /// baseline. We derive scales so both readers share one cache-key shape;
  /// the novel render layer keeps using its own absolute fields directly, this
  /// bridge only exists for shared-cache / shared-component consumers.
  RichTextTypography get sharedTypography {
    const baseFontSize = 18.0;
    const baseLineHeight = 1.5;
    return RichTextTypography(
      fontScale: fontSize / baseFontSize,
      lineHeightScale: lineHeight / baseLineHeight,
      paragraphSpacing: paragraphSpacing,
    );
  }
}
