import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

abstract interface class NativePageCacheInvalidationService {
  Future<void> invalidateThread(String tid);

  Future<void> invalidateForumHome();

  Future<void> invalidateForumDisplay(String fid);
}

class DefaultNativePageCacheInvalidationService
    implements NativePageCacheInvalidationService {
  const DefaultNativePageCacheInvalidationService({
    required DocumentCacheService documentCache,
    required ParsedSnapshotCacheService snapshotCache,
  }) : _documentCache = documentCache,
       _snapshotCache = snapshotCache;

  final DocumentCacheService _documentCache;
  final ParsedSnapshotCacheService _snapshotCache;

  @override
  Future<void> invalidateThread(String tid) async {
    final trimmed = tid.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _deleteOwnerPrefix(
      ownerType: CacheOwnerType.thread,
      ownerIdPrefix: 'tid=$trimmed',
    );
  }

  @override
  Future<void> invalidateForumHome() {
    return _deleteOwner(ownerType: CacheOwnerType.forum, ownerId: 'home');
  }

  @override
  Future<void> invalidateForumDisplay(String fid) async {
    final trimmed = fid.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _deleteOwnerPrefix(
      ownerType: CacheOwnerType.forumDisplay,
      ownerIdPrefix: 'fid=$trimmed',
    );
  }

  Future<void> _deleteOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    await Future.wait<void>([
      _safeDeleteDocuments(ownerType: ownerType, ownerId: ownerId),
      _safeDeleteSnapshots(ownerType: ownerType, ownerId: ownerId),
    ]);
  }

  Future<void> _deleteOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    await Future.wait<void>([
      _safeDeleteDocumentsByPrefix(
        ownerType: ownerType,
        ownerIdPrefix: ownerIdPrefix,
      ),
      _safeDeleteSnapshotsByPrefix(
        ownerType: ownerType,
        ownerIdPrefix: ownerIdPrefix,
      ),
    ]);
  }

  Future<void> _safeDeleteDocuments({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    try {
      await _documentCache.deleteByOwner(
        ownerType: ownerType,
        ownerId: ownerId,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _safeDeleteSnapshots({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    try {
      await _snapshotCache.deleteByOwner(
        ownerType: ownerType,
        ownerId: ownerId,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _safeDeleteDocumentsByPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    try {
      await _documentCache.deleteByOwnerPrefix(
        ownerType: ownerType,
        ownerIdPrefix: ownerIdPrefix,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _safeDeleteSnapshotsByPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    try {
      await _snapshotCache.deleteByOwnerPrefix(
        ownerType: ownerType,
        ownerIdPrefix: ownerIdPrefix,
      );
    } catch (_) {
      return;
    }
  }
}
