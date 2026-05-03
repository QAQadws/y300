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

class NovelReaderPreferences {
  const NovelReaderPreferences({
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.pagePadding,
    required this.themeMode,
    required this.fontFamily,
  });

  factory NovelReaderPreferences.defaults() {
    return const NovelReaderPreferences(
      fontSize: 18,
      lineHeight: 1.8,
      paragraphSpacing: 10,
      pagePadding: 16,
      themeMode: 'light',
      fontFamily: 'system',
    );
  }

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double pagePadding;
  final String themeMode;
  final String fontFamily;

  NovelReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? pagePadding,
    String? themeMode,
    String? fontFamily,
  }) {
    return NovelReaderPreferences(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      pagePadding: pagePadding ?? this.pagePadding,
      themeMode: themeMode ?? this.themeMode,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class NovelReadingProgress {
  const NovelReadingProgress({
    required this.novelId,
    required this.episodeId,
    required this.scrollOffset,
    required this.updatedAt,
  });

  final String novelId;
  final String episodeId;
  final double scrollOffset;
  final DateTime updatedAt;
}

class NovelEpisodeRefreshResult {
  const NovelEpisodeRefreshResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int totalCount;
}

class NovelRefreshSeed {
  const NovelRefreshSeed({
    required this.fid,
    required this.tid,
  });

  final String fid;
  final String tid;
}
