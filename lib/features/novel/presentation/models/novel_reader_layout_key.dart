class NovelReaderLayoutKey {
  const NovelReaderLayoutKey({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.viewportWidthPx,
    required this.viewportHeightPx,
    required this.bodyFontSizeX10,
    required this.bodyLineHeightX100,
    required this.headingFontSizeX10,
    required this.headingLineHeightX100,
    required this.paragraphSpacingX10,
    required this.pagePaddingX10,
    required this.contentMaxWidthX10,
    required this.fontWeight,
    required this.fontFamily,
    required this.textAlign,
    required this.firstLineIndentX10,
  });

  final String episodeId;
  final String rawHtmlHash;
  final int viewportWidthPx;
  final int viewportHeightPx;
  final int bodyFontSizeX10;
  final int bodyLineHeightX100;
  final int headingFontSizeX10;
  final int headingLineHeightX100;
  final int paragraphSpacingX10;
  final int pagePaddingX10;
  final int contentMaxWidthX10;
  final int fontWeight;
  final String fontFamily;
  final String textAlign;
  final int firstLineIndentX10;

  bool hasSameContentIdentity(NovelReaderLayoutKey other) {
    return episodeId == other.episodeId && rawHtmlHash == other.rawHtmlHash;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderLayoutKey &&
        other.episodeId == episodeId &&
        other.rawHtmlHash == rawHtmlHash &&
        other.viewportWidthPx == viewportWidthPx &&
        other.viewportHeightPx == viewportHeightPx &&
        other.bodyFontSizeX10 == bodyFontSizeX10 &&
        other.bodyLineHeightX100 == bodyLineHeightX100 &&
        other.headingFontSizeX10 == headingFontSizeX10 &&
        other.headingLineHeightX100 == headingLineHeightX100 &&
        other.paragraphSpacingX10 == paragraphSpacingX10 &&
        other.pagePaddingX10 == pagePaddingX10 &&
        other.contentMaxWidthX10 == contentMaxWidthX10 &&
        other.fontWeight == fontWeight &&
        other.fontFamily == fontFamily &&
        other.textAlign == textAlign &&
        other.firstLineIndentX10 == firstLineIndentX10;
  }

  @override
  int get hashCode => Object.hash(
    episodeId,
    rawHtmlHash,
    viewportWidthPx,
    viewportHeightPx,
    bodyFontSizeX10,
    bodyLineHeightX100,
    headingFontSizeX10,
    headingLineHeightX100,
    paragraphSpacingX10,
    pagePaddingX10,
    contentMaxWidthX10,
    fontWeight,
    fontFamily,
    textAlign,
    firstLineIndentX10,
  );
}
