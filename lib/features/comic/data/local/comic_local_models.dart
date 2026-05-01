class ComicRecord {
  const ComicRecord({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    required this.title,
    required this.author,
    required this.coverImageUrl,
    required this.customCoverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.lastReadEpisodeId,
  });

  final String comicId;
  final String sourceTid;
  final String sourceFid;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final int createdAt;
  final int updatedAt;
  final String? lastReadEpisodeId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'comic_id': comicId,
      'source_tid': sourceTid,
      'source_fid': sourceFid,
      'title': title,
      'author': author,
      'cover_image_url': coverImageUrl,
      'custom_cover_image_url': customCoverImageUrl,
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
      title: map['title'] as String,
      author: map['author'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      customCoverImageUrl: map['custom_cover_image_url'] as String?,
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
    this.cacheLocalPath,
    this.cacheStatus = 'none',
  });

  final String episodeId;
  final String imageUrl;
  final int imageIndex;
  final String? cacheLocalPath;
  final String cacheStatus;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episode_id': episodeId,
      'image_url': imageUrl,
      'image_index': imageIndex,
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
