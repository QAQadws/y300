import 'package:flutter/foundation.dart';

/// Cross-reader shared typography triple: font scale, line-height scale,
/// paragraph spacing. Used by both thread and novel readers.
///
/// Value object: == / hashCode cover all fields, making instances directly
/// usable as render-cache-key components without manual signature strings.
@immutable
class RichTextTypography {
  const RichTextTypography({
    required this.fontScale,
    required this.lineHeightScale,
    required this.paragraphSpacing,
  });

  /// Standard defaults matching the app's baseline reading style.
  static const RichTextTypography standard = RichTextTypography(
    fontScale: 1.0,
    lineHeightScale: 1.5,
    paragraphSpacing: 12,
  );

  /// Multiplier applied to the theme's body font size.
  final double fontScale;

  /// Multiplier applied to the base line height.
  final double lineHeightScale;

  /// Space between paragraphs in logical pixels.
  final double paragraphSpacing;

  RichTextTypography copyWith({
    double? fontScale,
    double? lineHeightScale,
    double? paragraphSpacing,
  }) {
    return RichTextTypography(
      fontScale: fontScale ?? this.fontScale,
      lineHeightScale: lineHeightScale ?? this.lineHeightScale,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RichTextTypography &&
      fontScale == other.fontScale &&
      lineHeightScale == other.lineHeightScale &&
      paragraphSpacing == other.paragraphSpacing;

  @override
  int get hashCode => Object.hash(fontScale, lineHeightScale, paragraphSpacing);
}
