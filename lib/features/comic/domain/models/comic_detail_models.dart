class ComicDetail {
  const ComicDetail({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    this.sourceTypeId,
    this.sourceTagName,
    required this.title,
    this.sourceTitle,
    this.customTitle,
    required this.author,
    this.sourceAuthor,
    this.customAuthor,
    required this.translationGroup,
    this.sourceTranslationGroup,
    this.customTranslationGroup,
    this.customSearchTitle,
    required this.coverImageUrl,
    this.customCoverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.customCoverSourceEpisodeId,
    this.customCoverSourceImageIndex,
    this.customCoverSourceImageUrl,
    required this.updatedAt,
    required this.episodeCount,
  });

  final String comicId;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  /// 最终展示标题。用户自定义标题存在时由仓储提前合成为该值。
  final String title;
  /// 来源解析标题与用户覆盖标题分开保存，刷新来源信息时不能覆盖用户值。
  final String? sourceTitle;
  final String? customTitle;
  /// 最终展示作者。用户自定义作者存在时由仓储提前合成为该值。
  final String? author;
  final String? sourceAuthor;
  final String? customAuthor;
  /// 最终展示汉化组。用户自定义汉化组存在时由仓储提前合成为该值。
  final String? translationGroup;
  final String? sourceTranslationGroup;
  final String? customTranslationGroup;
  /// 更新搜索关键词的用户覆盖值；为空时刷新链路按标题优先级兜底。
  final String? customSearchTitle;
  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final String? customCoverSourceEpisodeId;
  final int? customCoverSourceImageIndex;
  final String? customCoverSourceImageUrl;
  final DateTime updatedAt;
  final int episodeCount;

  String get displayTitle => title;
  String? get displayAuthor => author;
  String? get displayTranslationGroup => translationGroup;

  String get effectiveSourceTitle {
    final source = sourceTitle?.trim();
    return source == null || source.isEmpty ? title : source;
  }

  String? get effectiveSourceAuthor => _firstNonBlank(sourceAuthor, author);

  String? get effectiveSourceTranslationGroup {
    return _firstNonBlank(sourceTranslationGroup, translationGroup);
  }
}

String? _firstNonBlank(String? preferred, String? fallback) {
  final first = preferred?.trim();
  if (first != null && first.isNotEmpty) {
    return first;
  }
  final second = fallback?.trim();
  return second == null || second.isEmpty ? null : second;
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
