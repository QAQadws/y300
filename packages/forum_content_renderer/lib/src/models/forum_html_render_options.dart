/// Rendering values projected from Host preferences, without persistence or
/// text conversion policy.
final class ForumHtmlRenderOptions {
  const ForumHtmlRenderOptions({
    required this.fontScale,
    required this.lineHeightScale,
    required this.paragraphSpacing,
    required this.preserveAuthorFontSize,
    this.enablePlainTextLinks = false,
  });

  final double fontScale;
  final double lineHeightScale;
  final double paragraphSpacing;
  final bool preserveAuthorFontSize;

  /// Display-only HTTP(S) linking. Readers using prepared HTML as semantic
  /// content keep the default to preserve their document and anchor identity.
  final bool enablePlainTextLinks;

  ForumHtmlRenderOptions copyWith({
    double? fontScale,
    double? lineHeightScale,
    double? paragraphSpacing,
    bool? preserveAuthorFontSize,
    bool? enablePlainTextLinks,
  }) {
    return ForumHtmlRenderOptions(
      fontScale: fontScale ?? this.fontScale,
      lineHeightScale: lineHeightScale ?? this.lineHeightScale,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      preserveAuthorFontSize:
          preserveAuthorFontSize ?? this.preserveAuthorFontSize,
      enablePlainTextLinks: enablePlainTextLinks ?? this.enablePlainTextLinks,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumHtmlRenderOptions &&
        fontScale == other.fontScale &&
        lineHeightScale == other.lineHeightScale &&
        paragraphSpacing == other.paragraphSpacing &&
        preserveAuthorFontSize == other.preserveAuthorFontSize &&
        enablePlainTextLinks == other.enablePlainTextLinks;
  }

  @override
  int get hashCode => Object.hash(
    fontScale,
    lineHeightScale,
    paragraphSpacing,
    preserveAuthorFontSize,
    enablePlainTextLinks,
  );
}
