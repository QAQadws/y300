import 'package:y300/features/library_shared/domain/models/library_models.dart';

/// 统一作品级状态。
class LibraryWorkState {
  const LibraryWorkState({
    required this.moduleKey,
    required this.workId,
    this.lastReadEpisodeId,
    this.lastReadAt,
    this.checkUpdatedAt,
    this.fetchedUpdatedAt,
    this.introText,
    required this.createdAt,
    required this.updatedAt,
  });

  final LibraryModuleKey moduleKey;
  final String workId;
  final String? lastReadEpisodeId;
  final DateTime? lastReadAt;
  final DateTime? checkUpdatedAt;
  final DateTime? fetchedUpdatedAt;
  final String? introText;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 统一章节级状态。
class LibraryEpisodeState {
  const LibraryEpisodeState({
    required this.moduleKey,
    required this.episodeId,
    required this.workId,
    this.isRead = false,
    this.isDownloaded = false,
    this.isBookmarked = false,
    this.readAt,
    this.downloadedAt,
  });

  final LibraryModuleKey moduleKey;
  final String episodeId;
  final String workId;
  final bool isRead;
  final bool isDownloaded;
  final bool isBookmarked;
  final DateTime? readAt;
  final DateTime? downloadedAt;
}

/// 统一显示偏好（模块级）。
class LibraryModuleDisplaySettings {
  const LibraryModuleDisplaySettings({
    required this.moduleKey,
    required this.displayMode,
    required this.gridColumns,
    required this.updatedAt,
  });

  final LibraryModuleKey moduleKey;
  final LibraryDisplayMode displayMode;
  final int gridColumns;
  final DateTime updatedAt;
}

/// 标签模型。
class LibraryTag {
  const LibraryTag({
    required this.tagId,
    required this.name,
    required this.createdAt,
  });

  final String tagId;
  final String name;
  final DateTime createdAt;
}

