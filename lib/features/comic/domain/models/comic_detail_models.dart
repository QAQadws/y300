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
    this.customCoverFocusX,
    this.customCoverFocusY,
    required this.updatedAt,
    required this.episodeCount,
    this.catalogUrl,
    this.customCatalogUrl,
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

  /// 自定义封面焦点（归一化到 [-1,1]，对齐 Flutter [Alignment]；null 表示居中）。
  /// 非破坏性：原图保持不变，仅记录裁剪/对齐焦点，由显示层按 cover 对齐应用。
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final DateTime updatedAt;
  final int episodeCount;

  /// 帖子解析或搜索发现的来源目录 URL。
  final String? catalogUrl;

  /// 用户手动配置的目录 URL；存在时刷新策略优先使用该值。
  final String? customCatalogUrl;

  String? get effectiveCatalogUrl {
    return _firstNonBlank(customCatalogUrl, catalogUrl);
  }

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
    this.isManual = false,
    this.isHidden = false,
  });

  final String episodeId;
  final String comicId;
  final String? episodeTitle;
  final String sourceTid;
  final String sourceUrl;
  final int orderIndex;
  final String? publishTimeText;

  /// 用户手动添加的章节；解析章节为 false。只有手动章节可以被移除。
  final bool isManual;

  /// 用户隐藏的章节。隐藏章节默认不进入详情列表与阅读器章节导航。
  final bool isHidden;
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
    this.width,
    this.height,
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
  final int? width;
  final int? height;
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
