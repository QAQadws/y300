class ComicRecord {
  const ComicRecord({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    required this.sourceTypeId,
    required this.sourceTagName,
    required this.title,
    required this.author,
    required this.translationGroup,
    required this.coverImageUrl,
    required this.customCoverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    required this.createdAt,
    required this.updatedAt,
    required this.lastReadEpisodeId,
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
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final int createdAt;
  final int updatedAt;
  final String? lastReadEpisodeId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'comic_id': comicId,
      'source_tid': sourceTid,
      'source_fid': sourceFid,
      'source_typeid': sourceTypeId,
      'source_tag_name': sourceTagName,
      'title': title,
      'author': author,
      'translation_group': translationGroup,
      'cover_image_url': coverImageUrl,
      'custom_cover_image_url': customCoverImageUrl,
      'cover_local_path': coverLocalPath,
      'custom_cover_local_path': customCoverLocalPath,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_read_episode_id': lastReadEpisodeId,
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
      author: map['author'] as String?,
      translationGroup: map['translation_group'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      customCoverImageUrl: map['custom_cover_image_url'] as String?,
      coverLocalPath: map['cover_local_path'] as String?,
      customCoverLocalPath: map['custom_cover_local_path'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      lastReadEpisodeId: map['last_read_episode_id'] as String?,
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
  });

  final String episodeId;
  final String comicId;
  final String? episodeTitle;
  final String sourceTid;
  final String sourceUrl;
  final int orderIndex;
  final String? publishTimeText;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episode_id': episodeId,
      'comic_id': comicId,
      'episode_title': episodeTitle,
      'source_tid': sourceTid,
      'source_url': sourceUrl,
      'order_index': orderIndex,
      'publish_time_text': publishTimeText,
    };
  }
}

class EpisodeImageRecord {
  const EpisodeImageRecord({
    required this.episodeId,
    required this.imageUrl,
    required this.imageIndex,
    this.stableCacheKey,
    this.lastSourceUrl,
    this.localPath,
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
