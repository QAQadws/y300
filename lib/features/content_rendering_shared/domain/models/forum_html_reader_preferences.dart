import 'package:flutter/foundation.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

@immutable
class ForumHtmlReaderPreferences {
  const ForumHtmlReaderPreferences({
    required this.typography,
    required this.conversionMode,
    this.preserveAuthorFontSize = true,
    this.fontFamily = 'system',
  });

  factory ForumHtmlReaderPreferences.defaults() =>
      const ForumHtmlReaderPreferences(
        typography: RichTextTypography(
          fontScale: 1.15,
          lineHeightScale: 1.5,
          paragraphSpacing: defaultParagraphSpacing,
        ),
        conversionMode: TextConversionMode.none,
      );

  /// Paragraph spacing is intentionally an internal rendering default.
  ///
  /// There is no production control for it, so it must not become a hidden
  /// device preference that users cannot inspect or reset.
  static const double defaultParagraphSpacing = 12;

  final RichTextTypography typography;
  final TextConversionMode conversionMode;
  final bool preserveAuthorFontSize;

  /// Stable local font choice, never an external path or engine family name.
  final String fontFamily;

  ForumHtmlReaderPreferences copyWith({
    RichTextTypography? typography,
    TextConversionMode? conversionMode,
    bool? preserveAuthorFontSize,
    String? fontFamily,
  }) {
    return ForumHtmlReaderPreferences(
      typography: typography ?? this.typography,
      conversionMode: conversionMode ?? this.conversionMode,
      preserveAuthorFontSize:
          preserveAuthorFontSize ?? this.preserveAuthorFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumHtmlReaderPreferences &&
        typography == other.typography &&
        conversionMode == other.conversionMode &&
        preserveAuthorFontSize == other.preserveAuthorFontSize &&
        fontFamily == other.fontFamily;
  }

  @override
  int get hashCode => Object.hash(
    typography,
    conversionMode,
    preserveAuthorFontSize,
    fontFamily,
  );
}
