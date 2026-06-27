enum ThreadPostTextConversionMode { none, simplified, traditional }

class ThreadPostBodyRenderSettings {
  const ThreadPostBodyRenderSettings({
    this.conversionMode = ThreadPostTextConversionMode.none,
    this.fontSize,
    this.lineHeight,
    this.paragraphSpacing,
    this.blockSpacing,
    this.textTransformerKey = '',
  });

  static const ThreadPostBodyRenderSettings defaults =
      ThreadPostBodyRenderSettings();

  final ThreadPostTextConversionMode conversionMode;
  final double? fontSize;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? blockSpacing;
  final String textTransformerKey;

  String get signature {
    return [
      conversionMode.name,
      fontSize?.toStringAsFixed(3) ?? '',
      lineHeight?.toStringAsFixed(3) ?? '',
      paragraphSpacing?.toStringAsFixed(3) ?? '',
      blockSpacing?.toStringAsFixed(3) ?? '',
      textTransformerKey,
    ].join('|');
  }

  ThreadPostBodyRenderSettings copyWith({
    ThreadPostTextConversionMode? conversionMode,
    double? fontSize,
    bool clearFontSize = false,
    double? lineHeight,
    bool clearLineHeight = false,
    double? paragraphSpacing,
    bool clearParagraphSpacing = false,
    double? blockSpacing,
    bool clearBlockSpacing = false,
    String? textTransformerKey,
  }) {
    return ThreadPostBodyRenderSettings(
      conversionMode: conversionMode ?? this.conversionMode,
      fontSize: clearFontSize ? null : (fontSize ?? this.fontSize),
      lineHeight: clearLineHeight ? null : (lineHeight ?? this.lineHeight),
      paragraphSpacing: clearParagraphSpacing
          ? null
          : (paragraphSpacing ?? this.paragraphSpacing),
      blockSpacing: clearBlockSpacing
          ? null
          : (blockSpacing ?? this.blockSpacing),
      textTransformerKey: textTransformerKey ?? this.textTransformerKey,
    );
  }
}
