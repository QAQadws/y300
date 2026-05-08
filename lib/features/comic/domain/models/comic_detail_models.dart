class ComicDetail {
  const ComicDetail({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    this.sourceTypeId,
    this.sourceTagName,
    required this.title,
    required this.author,
    required this.translationGroup,
    required this.coverImageUrl,
    required this.updatedAt,
    required this.episodeCount,
  });

  final String comicId;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final String title;
  final String? author;
  final String? translationGroup;
  final String? coverImageUrl;
  final DateTime updatedAt;
  final int episodeCount;
}

class ComicEpisodeItem {
  const ComicEpisodeItem({
    required this.episodeId,
    required this.comicId,
    required this.episodeTitle,
    required this.sourceTid,
    required this.sourceUrl,
    required this.orderIndex,
    required this.publishTimeText,
  });

  final String episodeId;
  final String comicId;
  final String? episodeTitle;
  final String sourceTid;
  final String sourceUrl;
  final int orderIndex;
  final String? publishTimeText;
}

class ComicEpisodeRefreshResult {
  const ComicEpisodeRefreshResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int totalCount;
}

class ComicEpisodeImageItem {
  const ComicEpisodeImageItem({
    required this.episodeId,
    required this.imageUrl,
    required this.imageIndex,
    required this.cacheStatus,
    this.cacheLocalPath,
  });

  final String episodeId;
  final String imageUrl;
  final int imageIndex;
  final String cacheStatus;
  final String? cacheLocalPath;
}

class ComicReadingProgress {
  const ComicReadingProgress({
    required this.comicId,
    required this.episodeId,
    required this.imageIndex,
    required this.scrollOffset,
    required this.updatedAt,
  });

  final String comicId;
  final String episodeId;
  final int imageIndex;
  final double scrollOffset;
  final DateTime updatedAt;
}
