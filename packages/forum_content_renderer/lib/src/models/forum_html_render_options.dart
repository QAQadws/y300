/// Rendering values projected from Host preferences, without persistence or
/// text conversion policy.
final class ForumHtmlRenderOptions {
  const ForumHtmlRenderOptions({
    required this.fontScale,
    required this.lineHeightScale,
    required this.paragraphSpacing,
    required this.preserveAuthorFontSize,
  });

  final double fontScale;
  final double lineHeightScale;
  final double paragraphSpacing;
  final bool preserveAuthorFontSize;

  ForumHtmlRenderOptions copyWith({
    double? fontScale,
    double? lineHeightScale,
    double? paragraphSpacing,
    bool? preserveAuthorFontSize,
  }) {
    return ForumHtmlRenderOptions(
      fontScale: fontScale ?? this.fontScale,
      lineHeightScale: lineHeightScale ?? this.lineHeightScale,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      preserveAuthorFontSize:
          preserveAuthorFontSize ?? this.preserveAuthorFontSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumHtmlRenderOptions &&
        fontScale == other.fontScale &&
        lineHeightScale == other.lineHeightScale &&
        paragraphSpacing == other.paragraphSpacing &&
        preserveAuthorFontSize == other.preserveAuthorFontSize;
  }

  @override
  int get hashCode => Object.hash(
    fontScale,
    lineHeightScale,
    paragraphSpacing,
    preserveAuthorFontSize,
  );
}
