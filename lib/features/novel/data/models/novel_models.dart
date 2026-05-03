/// 小说书架条目（阶段0基础模型）。
class NovelItem {
  const NovelItem({
    required this.novelId,
    required this.sourceTid,
    required this.sourceFid,
    required this.title,
    this.author,
    this.coverImageUrl,
    required this.updatedAt,
    required this.episodeCount,
  });

  final String novelId;
  final String sourceTid;
  final String sourceFid;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final DateTime updatedAt;
  final int episodeCount;
}

/// 小说章节条目（阶段0基础模型）。
class NovelEpisodeItem {
  const NovelEpisodeItem({
    required this.episodeId,
    required this.novelId,
    required this.sourceTid,
    this.sourcePid,
    this.sourcePage,
    required this.episodeTitle,
    required this.orderIndex,
    this.datelineText,
  });

  final String episodeId;
  final String novelId;
  final String sourceTid;
  final String? sourcePid;
  final int? sourcePage;
  final String episodeTitle;
  final int orderIndex;
  final String? datelineText;
}

/// 小说章节正文（阶段0基础模型）。
class NovelChapterContent {
  const NovelChapterContent({
    required this.episodeId,
    required this.rawHtml,
    required this.plainText,
    required this.paragraphs,
  });

  final String episodeId;
  final String rawHtml;
  final String plainText;
  final List<String> paragraphs;
}

/// 小说阅读器偏好（阶段0基础模型）。
class NovelReaderPreferences {
  const NovelReaderPreferences({
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.pagePadding,
    required this.themeMode,
    required this.fontFamily,
  });

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double pagePadding;
  final String themeMode;
  final String fontFamily;
}
