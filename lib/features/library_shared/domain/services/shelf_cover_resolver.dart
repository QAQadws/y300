import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';

enum ShelfResolvedCoverStatus {
  local,
  stale,
  remoteOnly,
  missing,
}

class ShelfResolvedCover {
  const ShelfResolvedCover({
    required this.workId,
    required this.status,
    this.localPath,
    this.remoteUrl,
    this.cacheKey,
  });

  final String workId;
  final ShelfResolvedCoverStatus status;
  final String? localPath;
  final String? remoteUrl;
  final String? cacheKey;

  bool get hasUsableLocalPath {
    final value = localPath?.trim();
    return value != null && value.isNotEmpty && status == ShelfResolvedCoverStatus.local;
  }
}

/// Fast cover resolver for shelf metadata.
///
/// It never downloads. The resolver only chooses the best immediately usable
/// candidate and optionally asks ImageCacheService for already-known metadata.
/// Download/write-back remains owned by ShelfCoverWarmupAdapter implementations.
class ShelfCoverResolver {
  const ShelfCoverResolver({
    ImageCacheService? imageCacheService,
  }) : _imageCacheService = imageCacheService;

  final ImageCacheService? _imageCacheService;

  Future<ShelfResolvedCover> resolveFast({
    required LibraryWorkItem item,
    ShelfCoverWarmupRequest? request,
  }) async {
    final customLocal = item.customCoverLocalPath?.trim();
    if (customLocal != null && customLocal.isNotEmpty) {
      return ShelfResolvedCover(
        workId: item.workId,
        status: ShelfResolvedCoverStatus.local,
        localPath: customLocal,
        remoteUrl: item.customCoverImageUrl,
        cacheKey: request?.cacheKey,
      );
    }

    final coverLocal = item.coverLocalPath?.trim();
    if (coverLocal != null && coverLocal.isNotEmpty) {
      return ShelfResolvedCover(
        workId: item.workId,
        status: ShelfResolvedCoverStatus.local,
        localPath: coverLocal,
        remoteUrl: item.coverImageUrl,
        cacheKey: request?.cacheKey,
      );
    }

    final cacheKey = request?.cacheKey.trim();
    final cached = cacheKey == null || cacheKey.isEmpty ? null : await _imageCacheService?.getCached(cacheKey);
    final cachedPath = cached?.localPath?.trim();
    if (cachedPath != null && cachedPath.isNotEmpty) {
      return ShelfResolvedCover(
        workId: item.workId,
        status: ShelfResolvedCoverStatus.local,
        localPath: cachedPath,
        remoteUrl: request?.sourceUrl ?? _preferredRemote(item),
        cacheKey: cacheKey,
      );
    }

    final remote = request?.sourceUrl.trim();
    if (remote != null && remote.isNotEmpty) {
      return ShelfResolvedCover(
        workId: item.workId,
        status: cacheKey == null ? ShelfResolvedCoverStatus.remoteOnly : ShelfResolvedCoverStatus.stale,
        remoteUrl: remote,
        cacheKey: cacheKey,
      );
    }

    final itemRemote = _preferredRemote(item);
    if (itemRemote != null) {
      return ShelfResolvedCover(
        workId: item.workId,
        status: cacheKey == null ? ShelfResolvedCoverStatus.remoteOnly : ShelfResolvedCoverStatus.stale,
        remoteUrl: itemRemote,
        cacheKey: cacheKey,
      );
    }

    return ShelfResolvedCover(
      workId: item.workId,
      status: ShelfResolvedCoverStatus.missing,
      cacheKey: cacheKey,
    );
  }

  String? _preferredRemote(LibraryWorkItem item) {
    final custom = item.customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = item.coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}
