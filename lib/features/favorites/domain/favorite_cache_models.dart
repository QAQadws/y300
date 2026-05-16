import 'package:y300/features/thread/domain/thread_content_classifier.dart';

const String favoriteSyncKey = 'myfavthread';
const String favoriteComicAutoRefreshBackfillSyncKey =
    'favorite_comic_auto_refresh_backfill_v1';
const String favoriteDefaultCategoryId = 'default';
const String favoriteComicCategoryId = 'favorite:comic';
const String favoriteNovelCategoryId = 'favorite:novel';

enum FavoriteSyncMode {
  incremental,
  fullDiff,
}

class FavoriteSyncSnapshot {
  const FavoriteSyncSnapshot({
    required this.syncKey,
    required this.remoteCount,
    required this.localActiveCount,
    this.lastSyncedAt,
    this.lastFullSyncedAt,
    this.status,
    this.message,
  });

  final String syncKey;
  final int remoteCount;
  final int localActiveCount;
  final DateTime? lastSyncedAt;
  final DateTime? lastFullSyncedAt;
  final String? status;
  final String? message;
}

class FavoriteSyncResult {
  const FavoriteSyncResult({
    required this.mode,
    required this.remoteCount,
    required this.fetchedPages,
    required this.upsertedCount,
    required this.removedRecords,
    required this.detailLoadedCount,
    required this.failedDetailTids,
  });

  final FavoriteSyncMode mode;
  final int remoteCount;
  final int fetchedPages;
  final int upsertedCount;
  final List<FavoriteThreadCacheRecord> removedRecords;
  final int detailLoadedCount;
  final List<String> failedDetailTids;
}

class FavoriteThreadCacheRecord {
  const FavoriteThreadCacheRecord({
    required this.tid,
    this.favid,
    required this.title,
    this.description,
    this.author,
    required this.replies,
    this.url,
    this.dateline,
    this.remoteOrder,
    this.sourceFid,
    this.sourceTypeid,
    this.sourceTagName,
    required this.contentKind,
    this.workId,
    this.detailLoadedAt,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.removedAt,
    this.customCategoryId,
  });

  final String tid;
  final String? favid;
  final String title;
  final String? description;
  final String? author;
  final int replies;
  final String? url;
  final DateTime? dateline;
  final int? remoteOrder;
  final String? sourceFid;
  final String? sourceTypeid;
  final String? sourceTagName;
  final ThreadContentKind contentKind;
  final String? workId;
  final DateTime? detailLoadedAt;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? removedAt;
  final String? customCategoryId;

  bool get isActive => removedAt == null;

  String get shelfWorkId => FavoriteShelfWorkId.fromTid(tid);

  String get resolvedCategoryId {
    final custom = customCategoryId?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    switch (contentKind) {
      case ThreadContentKind.unknown:
        return favoriteDefaultCategoryId;
      case ThreadContentKind.comic:
        return favoriteComicCategoryId;
      case ThreadContentKind.novel:
        return favoriteNovelCategoryId;
      case ThreadContentKind.forum:
        return favoriteDefaultCategoryId;
    }
  }
}

class FavoriteCategoryRecord {
  const FavoriteCategoryRecord({
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
}

class FavoriteRouteTarget {
  const FavoriteRouteTarget({
    required this.tid,
    required this.title,
    required this.contentKind,
    this.workId,
  });

  final String tid;
  final String title;
  final ThreadContentKind contentKind;
  final String? workId;
}

class FavoriteShelfWorkId {
  FavoriteShelfWorkId._();

  static const String prefix = 'favorite:';

  static String fromTid(String tid) {
    return '$prefix${tid.trim()}';
  }

  static String? parseTid(String workId) {
    final trimmed = workId.trim();
    if (!trimmed.startsWith(prefix)) {
      return null;
    }
    final tid = trimmed.substring(prefix.length).trim();
    return tid.isEmpty ? null : tid;
  }
}

ThreadContentKind favoriteContentKindFromDb(String? value) {
  switch (value) {
    case 'comic':
      return ThreadContentKind.comic;
    case 'novel':
      return ThreadContentKind.novel;
    case 'forum':
      return ThreadContentKind.forum;
    case 'unknown':
      return ThreadContentKind.unknown;
    default:
      return ThreadContentKind.unknown;
  }
}

String favoriteContentKindToDb(ThreadContentKind kind) {
  switch (kind) {
    case ThreadContentKind.unknown:
      return 'unknown';
    case ThreadContentKind.comic:
      return 'comic';
    case ThreadContentKind.novel:
      return 'novel';
    case ThreadContentKind.forum:
      return 'forum';
  }
}
