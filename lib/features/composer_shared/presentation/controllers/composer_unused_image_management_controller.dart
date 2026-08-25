import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';

final composerUnusedImageThumbnailIntervalProvider = Provider<Duration>((_) {
  return const Duration(milliseconds: 600);
});

final composerUnusedImageManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<
      ComposerUnusedImageManagementController,
      ComposerUnusedImageManagementState
    >(ComposerUnusedImageManagementController.new);

final class ComposerUnusedImageManagementState {
  ComposerUnusedImageManagementState({
    required List<ComposerUnusedImage> images,
    Map<String, String> thumbnailPaths = const <String, String>{},
    Set<String> loadingThumbnailAids = const <String>{},
    Set<String> failedThumbnailAids = const <String>{},
    Set<String> deletingAids = const <String>{},
  }) : images = List<ComposerUnusedImage>.unmodifiable(images),
       thumbnailPaths = Map<String, String>.unmodifiable(thumbnailPaths),
       loadingThumbnailAids = Set<String>.unmodifiable(loadingThumbnailAids),
       failedThumbnailAids = Set<String>.unmodifiable(failedThumbnailAids),
       deletingAids = Set<String>.unmodifiable(deletingAids);

  final List<ComposerUnusedImage> images;
  final Map<String, String> thumbnailPaths;
  final Set<String> loadingThumbnailAids;
  final Set<String> failedThumbnailAids;
  final Set<String> deletingAids;

  bool containsAid(String aid) => images.any((image) => image.aid == aid);

  ComposerUnusedImageManagementState copyWith({
    List<ComposerUnusedImage>? images,
    Map<String, String>? thumbnailPaths,
    Set<String>? loadingThumbnailAids,
    Set<String>? failedThumbnailAids,
    Set<String>? deletingAids,
  }) {
    return ComposerUnusedImageManagementState(
      images: images ?? this.images,
      thumbnailPaths: thumbnailPaths ?? this.thumbnailPaths,
      loadingThumbnailAids: loadingThumbnailAids ?? this.loadingThumbnailAids,
      failedThumbnailAids: failedThumbnailAids ?? this.failedThumbnailAids,
      deletingAids: deletingAids ?? this.deletingAids,
    );
  }
}

class ComposerUnusedImageManagementController
    extends AsyncNotifier<ComposerUnusedImageManagementState> {
  var _generation = 0;
  var _disposed = false;
  final Set<String> _serverDeletedAids = <String>{};
  final Set<String> _queuedThumbnailAids = <String>{};
  final Set<String> _decodeRepairAttemptedAids = <String>{};
  Future<void> _thumbnailQueueTail = Future<void>.value();
  var _hasScheduledThumbnailTask = false;

  ComposerUnusedImageRepository get _unusedImageRepository =>
      ref.read(composerUnusedImageRepositoryProvider);
  ComposerDraftRepository get _draftRepository =>
      ref.read(composerDraftRepositoryProvider);
  ImageCacheService get _imageCacheService =>
      ref.read(imageCacheServiceProvider);
  Duration get _thumbnailInterval =>
      ref.read(composerUnusedImageThumbnailIntervalProvider);

  @override
  Future<ComposerUnusedImageManagementState> build() async {
    ref.onDispose(() {
      _disposed = true;
      _generation += 1;
      _queuedThumbnailAids.clear();
      _decodeRepairAttemptedAids.clear();
    });
    final generation = _beginGeneration();
    final loaded = await _loadCatalog(
      generation: generation,
      repository: _unusedImageRepository,
      cacheService: _imageCacheService,
    );
    _scheduleDownloads(loaded.networkMisses, generation);
    return loaded.state;
  }

  Future<void> refreshCatalog() async {
    final current = state.asData?.value;
    if (current != null && current.deletingAids.isNotEmpty) {
      return;
    }
    final generation = _beginGeneration();
    final repository = _unusedImageRepository;
    final cacheService = _imageCacheService;
    state = const AsyncLoading<ComposerUnusedImageManagementState>();
    final loaded = await AsyncValue.guard(
      () => _loadCatalog(
        generation: generation,
        repository: repository,
        cacheService: cacheService,
      ),
    );
    if (!_isCurrent(generation)) {
      return;
    }
    switch (loaded) {
      case AsyncData<_LoadedUnusedImageCatalog>(:final value):
        state = AsyncData(value.state);
        _scheduleDownloads(value.networkMisses, generation);
      case AsyncError<_LoadedUnusedImageCatalog>(
        :final error,
        :final stackTrace,
      ):
        state = AsyncError(error, stackTrace);
      case AsyncLoading<_LoadedUnusedImageCatalog>():
        break;
    }
  }

  Future<bool> deleteImage(String aid) async {
    final normalizedAid = aid.trim();
    final current = state.asData?.value;
    if (normalizedAid.isEmpty ||
        current == null ||
        !current.containsAid(normalizedAid) ||
        current.deletingAids.contains(normalizedAid)) {
      return false;
    }

    final repository = _unusedImageRepository;
    final draftRepository = _draftRepository;
    final cacheService = _imageCacheService;
    state = AsyncData(
      current.copyWith(
        deletingAids: <String>{...current.deletingAids, normalizedAid},
      ),
    );

    final result = await repository.deleteUnusedImage(normalizedAid);
    final deleted = switch (result) {
      ApiSuccess<ComposerUnusedImageDeleteResult>(:final data) => data.deleted,
      ApiFailure<ComposerUnusedImageDeleteResult>() => false,
    };
    if (!deleted) {
      _removeDeletingAid(normalizedAid);
      return false;
    }

    _serverDeletedAids.add(normalizedAid);
    final afterDelete = state.asData?.value;
    if (afterDelete != null) {
      final thumbnailPaths = Map<String, String>.of(afterDelete.thumbnailPaths)
        ..remove(normalizedAid);
      final loadingAids = Set<String>.of(afterDelete.loadingThumbnailAids)
        ..remove(normalizedAid);
      final failedAids = Set<String>.of(afterDelete.failedThumbnailAids)
        ..remove(normalizedAid);
      final deletingAids = Set<String>.of(afterDelete.deletingAids)
        ..remove(normalizedAid);
      state = AsyncData(
        afterDelete.copyWith(
          images: afterDelete.images
              .where((image) => image.aid != normalizedAid)
              .toList(growable: false),
          thumbnailPaths: thumbnailPaths,
          loadingThumbnailAids: loadingAids,
          failedThumbnailAids: failedAids,
          deletingAids: deletingAids,
        ),
      );
    }

    // The remote delete is already authoritative. Local cleanup is best
    // effort and must never put a now-invalid card back into the UI.
    await _invalidateDraftAidBestEffort(draftRepository, normalizedAid);
    await _deleteThumbnailBestEffort(cacheService, normalizedAid);
    return true;
  }

  void reportThumbnailDecodeFailure({
    required String aid,
    required String localPath,
  }) {
    if (_disposed || !ref.mounted) {
      return;
    }
    final normalizedAid = aid.trim();
    final normalizedPath = localPath.trim();
    final current = state.asData?.value;
    if (normalizedAid.isEmpty ||
        normalizedPath.isEmpty ||
        current == null ||
        current.thumbnailPaths[normalizedAid]?.trim() != normalizedPath ||
        !current.containsAid(normalizedAid) ||
        _serverDeletedAids.contains(normalizedAid)) {
      return;
    }

    final thumbnailPaths = Map<String, String>.of(current.thumbnailPaths)
      ..remove(normalizedAid);
    final loadingAids = Set<String>.of(current.loadingThumbnailAids);
    final failedAids = Set<String>.of(current.failedThumbnailAids);
    final shouldRepair = _decodeRepairAttemptedAids.add(normalizedAid);
    if (shouldRepair) {
      loadingAids.add(normalizedAid);
      failedAids.remove(normalizedAid);
    } else {
      loadingAids.remove(normalizedAid);
      failedAids.add(normalizedAid);
    }
    state = AsyncData(
      current.copyWith(
        thumbnailPaths: thumbnailPaths,
        loadingThumbnailAids: loadingAids,
        failedThumbnailAids: failedAids,
      ),
    );
    if (!shouldRepair) {
      return;
    }

    final image = current.images.firstWhere(
      (candidate) => candidate.aid == normalizedAid,
    );
    _enqueueThumbnailDownload(
      image: image,
      generation: _generation,
      invalidateFirst: true,
    );
  }

  Future<_LoadedUnusedImageCatalog> _loadCatalog({
    required int generation,
    required ComposerUnusedImageRepository repository,
    required ImageCacheService cacheService,
  }) async {
    final result = await repository.loadUnusedImages();
    if (result case ApiFailure<List<ComposerUnusedImage>>(:final error)) {
      throw error;
    }
    if (!_isCurrent(generation)) {
      throw const _StaleUnusedImageCatalog();
    }
    final images = result.dataOrNull!
        .where((image) => !_serverDeletedAids.contains(image.aid))
        .toList(growable: false);
    final thumbnailPaths = <String, String>{};
    final misses = <ComposerUnusedImage>[];
    for (final image in images) {
      CachedImageResult? cached;
      try {
        cached = await cacheService.getCached(
          ForumImageCacheRequests.composerUnusedAttachment(
            aid: image.aid,
            url: image.thumbnailUri.toString(),
          ).cacheKey,
        );
      } catch (_) {
        cached = null;
      }
      if (!_isCurrent(generation)) {
        throw const _StaleUnusedImageCatalog();
      }
      final path = cached?.localPath?.trim();
      if (cached?.success == true && path != null && path.isNotEmpty) {
        thumbnailPaths[image.aid] = path;
      } else {
        misses.add(image);
      }
    }
    return _LoadedUnusedImageCatalog(
      state: ComposerUnusedImageManagementState(
        images: images,
        thumbnailPaths: thumbnailPaths,
        loadingThumbnailAids: misses.map((image) => image.aid).toSet(),
      ),
      networkMisses: misses,
    );
  }

  void _scheduleDownloads(List<ComposerUnusedImage> images, int generation) {
    if (images.isEmpty) {
      return;
    }
    final cacheService = _imageCacheService;
    final interval = _thumbnailInterval;
    unawaited(
      Future<void>.delayed(Duration.zero).then((_) {
        if (!_isCurrent(generation)) {
          return;
        }
        for (final image in images) {
          _enqueueThumbnailDownload(
            image: image,
            generation: generation,
            cacheService: cacheService,
            interval: interval,
          );
        }
      }),
    );
  }

  void _enqueueThumbnailDownload({
    required ComposerUnusedImage image,
    required int generation,
    bool invalidateFirst = false,
    ImageCacheService? cacheService,
    Duration? interval,
  }) {
    if (!_isCurrent(generation) || !_queuedThumbnailAids.add(image.aid)) {
      return;
    }
    final resolvedCacheService = cacheService ?? _imageCacheService;
    final resolvedInterval = interval ?? _thumbnailInterval;
    final delayBeforeStart = _hasScheduledThumbnailTask;
    _hasScheduledThumbnailTask = true;
    final previous = _thumbnailQueueTail;
    late final Future<void> task;
    task = previous
        .then((_) async {
          if (delayBeforeStart && resolvedInterval > Duration.zero) {
            await Future<void>.delayed(resolvedInterval);
          }
          if (!_isCurrent(generation)) {
            return;
          }
          final current = state.asData?.value;
          if (current == null ||
              !current.containsAid(image.aid) ||
              _serverDeletedAids.contains(image.aid)) {
            return;
          }
          if (invalidateFirst) {
            await _deleteThumbnailBestEffort(resolvedCacheService, image.aid);
            if (!_isCurrent(generation) ||
                state.asData?.value.containsAid(image.aid) != true ||
                _serverDeletedAids.contains(image.aid)) {
              return;
            }
          }
          final request = ForumImageCacheRequests.composerUnusedAttachment(
            aid: image.aid,
            url: image.thumbnailUri.toString(),
            referer: image.thumbnailRefererUri.toString(),
          );
          CachedImageResult result;
          try {
            result = await resolvedCacheService.ensureCached(request);
          } catch (_) {
            result = CachedImageResult.failed;
          }
          if (!_isCurrent(generation)) {
            return;
          }
          if (_serverDeletedAids.contains(image.aid) ||
              state.asData?.value.containsAid(image.aid) != true) {
            await _deleteThumbnailBestEffort(resolvedCacheService, image.aid);
          } else {
            _queuedThumbnailAids.remove(image.aid);
            _recordThumbnailResult(image.aid, result);
          }
        })
        .whenComplete(() {
          if (_isCurrent(generation)) {
            _queuedThumbnailAids.remove(image.aid);
          }
        });
    _thumbnailQueueTail = task;
  }

  void _recordThumbnailResult(String aid, CachedImageResult result) {
    final current = state.asData?.value;
    if (current == null || !current.containsAid(aid)) {
      return;
    }
    final loadingAids = Set<String>.of(current.loadingThumbnailAids)
      ..remove(aid);
    final failedAids = Set<String>.of(current.failedThumbnailAids);
    final thumbnailPaths = Map<String, String>.of(current.thumbnailPaths);
    final path = result.localPath?.trim();
    if (result.success && path != null && path.isNotEmpty) {
      thumbnailPaths[aid] = path;
      failedAids.remove(aid);
    } else {
      thumbnailPaths.remove(aid);
      failedAids.add(aid);
    }
    state = AsyncData(
      current.copyWith(
        thumbnailPaths: thumbnailPaths,
        loadingThumbnailAids: loadingAids,
        failedThumbnailAids: failedAids,
      ),
    );
  }

  void _removeDeletingAid(String aid) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        deletingAids: Set<String>.of(current.deletingAids)..remove(aid),
      ),
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  int _beginGeneration() {
    _generation += 1;
    _queuedThumbnailAids.clear();
    _decodeRepairAttemptedAids.clear();
    _thumbnailQueueTail = Future<void>.value();
    _hasScheduledThumbnailTask = false;
    return _generation;
  }

  Future<void> _invalidateDraftAidBestEffort(
    ComposerDraftRepository repository,
    String aid,
  ) async {
    try {
      await repository.invalidateAttachmentAids(aids: <String>{aid});
    } catch (_) {
      // A later draft-open reconciliation will retry against the server list.
    }
  }

  Future<void> _deleteThumbnailBestEffort(
    ImageCacheService cacheService,
    String aid,
  ) async {
    try {
      await cacheService.deleteByOwner(
        ownerType: ImageCacheOwnerType.composer,
        ownerId: aid,
      );
    } catch (_) {
      // The shared cache remains clearable and will be pruned by its budget.
    }
  }
}

final class _LoadedUnusedImageCatalog {
  const _LoadedUnusedImageCatalog({
    required this.state,
    required this.networkMisses,
  });

  final ComposerUnusedImageManagementState state;
  final List<ComposerUnusedImage> networkMisses;
}

final class _StaleUnusedImageCatalog implements Exception {
  const _StaleUnusedImageCatalog();
}
