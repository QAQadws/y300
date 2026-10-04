import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

/// Persists the existing portable favorite snapshot after the sync state is saved.
class FavoriteSnapshotWriter {
  const FavoriteSnapshotWriter({
    required LocalFavoriteRepository localRepository,
    DownloadStorageService? downloadStorageService,
  }) : _localRepository = localRepository,
       _downloadStorageService = downloadStorageService;

  final LocalFavoriteRepository _localRepository;
  final DownloadStorageService? _downloadStorageService;

  Future<void> write({required int remoteCount}) async {
    final storage = _downloadStorageService;
    if (storage == null) {
      return;
    }
    final records = await _localRepository.getActiveThreadsForSnapshot();
    await storage.writeFavoritesSnapshot(<String, Object?>{
      'schemaVersion': 1,
      'remoteCount': remoteCount,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'threads': records.map(_favoriteSnapshotRow).toList(growable: false),
    });
  }

  Map<String, Object?> _favoriteSnapshotRow(FavoriteThreadCacheRecord record) {
    return <String, Object?>{
      'tid': record.tid,
      'favid': record.remoteFavoriteId,
      'title': record.title,
      'author': record.authorName,
      'fid': record.sourceFid,
      'typeid': record.sourceTypeid,
      'tagName': record.sourceTagName,
      'contentKind': favoriteContentKindToDb(record.contentKind),
      'workId': record.workId,
      'removed': record.removedAt != null,
      'dateline': record.favoritedAt?.millisecondsSinceEpoch == null
          ? null
          : record.favoritedAt!.millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond,
    };
  }
}
