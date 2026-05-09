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
    this.coverLocalPath,
    this.customCoverLocalPath,
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
  final String? coverLocalPath;
  final String? customCoverLocalPath;
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
    this.stableCacheKey,
    this.lastSourceUrl,
    this.localPath,
    this.bytes = 0,
    this.mimeType,
    this.lastAccessedAt,
    this.protected = false,
    this.cacheLocalPath,
  });

  final String episodeId;
  final String imageUrl;
  final int imageIndex;
  final String cacheStatus;
  final String? stableCacheKey;
  final String? lastSourceUrl;
  final String? localPath;
  final int bytes;
  final String? mimeType;
  final DateTime? lastAccessedAt;
  final bool protected;
  final String? cacheLocalPath;

  String get effectiveSourceUrl {
    final source = lastSourceUrl?.trim();
    return source == null || source.isEmpty ? imageUrl : source;
  }

  String? get effectiveLocalPath {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) {
      return local;
    }
    final legacy = cacheLocalPath?.trim();
    return legacy == null || legacy.isEmpty ? null : legacy;
  }
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
