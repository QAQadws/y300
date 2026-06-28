import 'package:flutter/foundation.dart';

enum ThreadPostTextConversionMode { none, simplified, traditional }

@immutable
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

  /// Stable string fingerprint — kept for legacy comparisons during migration.
  /// Prefer value equality (==) for new code.
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

  @override
  bool operator ==(Object other) {
    if (other is! ThreadPostBodyRenderSettings) return false;
    return conversionMode == other.conversionMode &&
        fontSize == other.fontSize &&
        lineHeight == other.lineHeight &&
        paragraphSpacing == other.paragraphSpacing &&
        blockSpacing == other.blockSpacing &&
        textTransformerKey == other.textTransformerKey;
  }

  @override
  int get hashCode => Object.hash(
    conversionMode,
    fontSize,
    lineHeight,
    paragraphSpacing,
    blockSpacing,
    textTransformerKey,
  );

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
