class ComicRecord {
  const ComicRecord({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    required this.sourceTypeId,
    required this.sourceTagName,
    required this.title,
    required this.sourceTitle,
    required this.customTitle,
    required this.author,
    required this.sourceAuthor,
    required this.customAuthor,
    required this.translationGroup,
    required this.sourceTranslationGroup,
    required this.customTranslationGroup,
    required this.customSearchTitle,
    required this.coverImageUrl,
    required this.customCoverImageUrl,
    this.coverRevision = 0,
    this.customCoverRevision = 0,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.customCoverSourceEpisodeId,
    this.customCoverSourceImageIndex,
    this.customCoverSourceImageUrl,
    this.customCoverFocusX,
    this.customCoverFocusY,
    this.metadataUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastReadEpisodeId,
    this.catalogUrl,
    this.customCatalogUrl,
  });

  final String comicId;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final String title;
  final String? sourceTitle;
  final String? customTitle;
  final String? author;
  final String? sourceAuthor;
  final String? customAuthor;
  final String? translationGroup;
  final String? sourceTranslationGroup;
  final String? customTranslationGroup;
  final String? customSearchTitle;
  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final int coverRevision;
  final int customCoverRevision;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final String? customCoverSourceEpisodeId;
  final int? customCoverSourceImageIndex;
  final String? customCoverSourceImageUrl;
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final int? metadataUpdatedAt;
  final int createdAt;
  final int updatedAt;
  final String? lastReadEpisodeId;
  final String? catalogUrl;
  final String? customCatalogUrl;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'comic_id': comicId,
      'source_tid': sourceTid,
      'source_fid': sourceFid,
      'source_typeid': sourceTypeId,
      'source_tag_name': sourceTagName,
      'title': title,
      'source_title': sourceTitle,
      'custom_title': customTitle,
      'author': author,
      'source_author': sourceAuthor,
      'custom_author': customAuthor,
      'translation_group': translationGroup,
      'source_translation_group': sourceTranslationGroup,
      'custom_translation_group': customTranslationGroup,
      'custom_search_title': customSearchTitle,
      'cover_image_url': coverImageUrl,
      'custom_cover_image_url': customCoverImageUrl,
      'cover_revision': coverRevision,
      'custom_cover_revision': customCoverRevision,
      'cover_local_path': coverLocalPath,
      'custom_cover_local_path': customCoverLocalPath,
      'custom_cover_source_episode_id': customCoverSourceEpisodeId,
      'custom_cover_source_image_index': customCoverSourceImageIndex,
      'custom_cover_source_image_url': customCoverSourceImageUrl,
      'custom_cover_focus_x': customCoverFocusX,
      'custom_cover_focus_y': customCoverFocusY,
      'metadata_updated_at': metadataUpdatedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_read_episode_id': lastReadEpisodeId,
      'catalog_url': catalogUrl,
      'custom_catalog_url': customCatalogUrl,
    };
  }

  factory ComicRecord.fromMap(Map<String, Object?> map) {
    return ComicRecord(
      comicId: map['comic_id'] as String,
      sourceTid: map['source_tid'] as String,
      sourceFid: map['source_fid'] as String,
      sourceTypeId: map['source_typeid'] as String?,
      sourceTagName: map['source_tag_name'] as String?,
      title: map['title'] as String,
      sourceTitle: map['source_title'] as String?,
      customTitle: map['custom_title'] as String?,
      author: map['author'] as String?,
      sourceAuthor: map['source_author'] as String?,
      customAuthor: map['custom_author'] as String?,
      translationGroup: map['translation_group'] as String?,
      sourceTranslationGroup: map['source_translation_group'] as String?,
      customTranslationGroup: map['custom_translation_group'] as String?,
      customSearchTitle: map['custom_search_title'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      customCoverImageUrl: map['custom_cover_image_url'] as String?,
      coverRevision: map['cover_revision'] as int? ?? 0,
      customCoverRevision: map['custom_cover_revision'] as int? ?? 0,
      coverLocalPath: map['cover_local_path'] as String?,
      customCoverLocalPath: map['custom_cover_local_path'] as String?,
      customCoverSourceEpisodeId:
          map['custom_cover_source_episode_id'] as String?,
      customCoverSourceImageIndex:
          map['custom_cover_source_image_index'] as int?,
      customCoverSourceImageUrl:
          map['custom_cover_source_image_url'] as String?,
      customCoverFocusX: (map['custom_cover_focus_x'] as num?)?.toDouble(),
      customCoverFocusY: (map['custom_cover_focus_y'] as num?)?.toDouble(),
      metadataUpdatedAt: map['metadata_updated_at'] as int?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      lastReadEpisodeId: map['last_read_episode_id'] as String?,
      catalogUrl: map['catalog_url'] as String?,
      customCatalogUrl: map['custom_catalog_url'] as String?,
    );
  }
}

class EpisodeRecord {
  const EpisodeRecord({
    required this.episodeId,
    required this.comicId,
    required this.episodeTitle,
    required this.sourceTid,
    required this.sourceUrl,
    required this.orderIndex,
    required this.publishTimeText,
    this.sourceEpisodeTitle,
    this.customEpisodeTitle,
    this.isManual = false,
    this.isHidden = false,
  });

  /// 来源章节名与用户自定义章节名分开存，[episodeTitle] 存两者解析后的展示值。
  ///
  /// 与漫画标题同构：清空自定义名要能退回来源名，就必须留着来源名本身。
  /// 展示值同时落库而不是每次读取时算，是为了让既有读取点（详情、阅读器导航、
  /// 下载、统计）继续只认 `episode_title` 一列。
  factory EpisodeRecord.resolved({
    required String episodeId,
    required String comicId,
    required String sourceTid,
    required String sourceUrl,
    required int orderIndex,
    required String? publishTimeText,
    String? sourceEpisodeTitle,
    String? customEpisodeTitle,
    bool isManual = false,
    bool isHidden = false,
  }) {
    return EpisodeRecord(
      episodeId: episodeId,
      comicId: comicId,
      episodeTitle: resolveEpisodeDisplayTitle(
        customEpisodeTitle: customEpisodeTitle,
        sourceEpisodeTitle: sourceEpisodeTitle,
      ),
      sourceTid: sourceTid,
      sourceUrl: sourceUrl,
      orderIndex: orderIndex,
      publishTimeText: publishTimeText,
      sourceEpisodeTitle: sourceEpisodeTitle,
      customEpisodeTitle: customEpisodeTitle,
      isManual: isManual,
      isHidden: isHidden,
    );
  }

  final String episodeId;
  final String comicId;
  final String? episodeTitle;
  final String sourceTid;
  final String sourceUrl;
  final int orderIndex;
  final String? publishTimeText;

  /// 解析得到的章节名。用户清空自定义名后回退到这里。
  final String? sourceEpisodeTitle;

  /// 用户重命名的章节名。为空表示未自定义。
  final String? customEpisodeTitle;

  /// 用户手动添加的章节。只有手动章节允许被移除。
  final bool isManual;

  /// 用户隐藏的章节。隐藏只影响展示与阅读导航，不删除任何数据。
  final bool isHidden;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episode_id': episodeId,
      'comic_id': comicId,
      'episode_title': episodeTitle,
      'source_episode_title': sourceEpisodeTitle,
      'custom_episode_title': customEpisodeTitle,
      'source_tid': sourceTid,
      'source_url': sourceUrl,
      'order_index': orderIndex,
      'publish_time_text': publishTimeText,
      'is_manual': isManual ? 1 : 0,
      'is_hidden': isHidden ? 1 : 0,
    };
  }
}

/// 章节展示名：自定义优先，其次来源名，都为空时返回 null 交给上层兜底。
///
/// 返回 null 而不是就地拼一个「章节 tid」：兜底文案属于展示层策略，
/// 现有读取点已各自处理空标题，存储层再塞一个默认值会盖掉它们的口径。
String? resolveEpisodeDisplayTitle({
  required String? customEpisodeTitle,
  required String? sourceEpisodeTitle,
}) {
  final custom = customEpisodeTitle?.trim();
  if (custom != null && custom.isNotEmpty) {
    return custom;
  }
  final source = sourceEpisodeTitle?.trim();
  if (source != null && source.isNotEmpty) {
    return source;
  }
  return null;
}

class EpisodeImageRecord {
  const EpisodeImageRecord({
    required this.episodeId,
    required this.imageUrl,
    required this.imageIndex,
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
    this.cacheStatus = 'none',
  });

  final String episodeId;
  final String imageUrl;
  final int imageIndex;
  final String? stableCacheKey;
  final String? lastSourceUrl;
  final String? localPath;
  final int? width;
  final int? height;
  final int bytes;
  final String? mimeType;
  final int? lastAccessedAt;
  final bool protected;
  final String? cacheLocalPath;
  final String cacheStatus;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episode_id': episodeId,
      'image_url': imageUrl,
      'image_index': imageIndex,
      'stable_cache_key': stableCacheKey,
      'last_source_url': lastSourceUrl ?? imageUrl,
      'local_path': localPath,
      'width': width,
      'height': height,
      'bytes': bytes,
      'mime_type': mimeType,
      'last_accessed_at': lastAccessedAt,
      'protected': protected ? 1 : 0,
      'cache_local_path': cacheLocalPath,
      'cache_status': cacheStatus,
    };
  }
}

class ShelfItemRecord {
  const ShelfItemRecord({
    required this.categoryId,
    required this.comicId,
    required this.addedAt,
    required this.sortOrder,
  });

  final String categoryId;
  final String comicId;
  final int addedAt;
  final int sortOrder;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'category_id': categoryId,
      'comic_id': comicId,
      'added_at': addedAt,
      'sort_order': sortOrder,
    };
  }
}
