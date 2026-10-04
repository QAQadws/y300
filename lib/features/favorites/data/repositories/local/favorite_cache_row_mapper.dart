import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';

/// Shared decoding for SQLite rows; no database access or workflow state.
abstract final class FavoriteCacheRowMapper {
  static FavoriteSyncSnapshot syncSnapshot(Map<String, Object?> row) {
    return FavoriteSyncSnapshot(
      syncKey: row['sync_key'] as String,
      remoteCount: row['remote_count'] as int? ?? 0,
      localActiveCount: row['local_active_count'] as int? ?? 0,
      lastSyncedAt: dateTime(row['last_synced_at']),
      lastFullSyncedAt: dateTime(row['last_full_synced_at']),
      status: row['status'] as String?,
      message: row['message'] as String?,
    );
  }

  static FavoriteThreadCacheRecord record(Map<String, Object?> row) {
    return FavoriteThreadCacheRecord(
      tid: row['tid'] as String,
      remoteFavoriteId: row['favid'] as String?,
      title: row['title'] as String,
      description: row['description'] as String?,
      authorName: row['author'] as String?,
      replyCount: row['replies'] as int? ?? 0,
      favoritedAt: datelineDate(row['dateline']),
      remoteOrder: row['remote_order'] as int?,
      sourceFid: row['source_fid'] as String?,
      sourceTypeid: row['source_typeid'] as String?,
      sourceTagName: row['source_tag_name'] as String?,
      contentKind: favoriteContentKindFromDb(row['content_kind'] as String?),
      workId: row['work_id'] as String?,
      detailLoadedAt: dateTime(row['detail_loaded_at']),
      detailState: favoriteDetailStateFromDb(row['detail_state'] as String?),
      firstSeenAt:
          dateTime(row['first_seen_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt:
          dateTime(row['last_seen_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      removedAt: dateTime(row['removed_at']),
      customCategoryId: row['custom_category_id'] as String?,
    );
  }

  static DateTime? dateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static DateTime? datelineDate(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    final millis = value < 1000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static String nonEmpty(String value, {required String fallback}) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static String? normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
