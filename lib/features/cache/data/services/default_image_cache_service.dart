import 'dart:io' as io;
import 'dart:ui';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

abstract class ImageFileDownloader {
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
    bool force = false,
  });
}

class CacheManagerImageFileDownloader implements ImageFileDownloader {
  const CacheManagerImageFileDownloader();

  @override
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
    bool force = false,
  }) async {
    final fileInfo = await cacheManager.downloadFile(
      sourceUrl,
      key: cacheKey,
      authHeaders: headers,
      force: force,
    );
    return fileInfo.file.path;
  }
}

class DefaultImageCacheService
    implements
        ImageCacheService,
        ImageCacheOwnerDimensionLookup,
        ImageCacheDimensionRecorder,
        CacheBudgetParticipant {
  DefaultImageCacheService({
    required ImageCacheRepository repository,
    required Future<BaseCacheManager> cacheManagerFuture,
    required ImageCacheDirectoryResolver directoryResolver,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ImageFileDownloader downloader = const CacheManagerImageFileDownloader(),
    CacheMutationReporter mutationReporter = const NoopCacheMutationReporter(),
  }) : _repository = repository,
       _cacheManagerFuture = cacheManagerFuture,
       _directoryResolver = directoryResolver,
       _urlResolver = urlResolver,
       _downloader = downloader,
       _mutationReporter = mutationReporter;

  final ImageCacheRepository _repository;
  final Future<BaseCacheManager> _cacheManagerFuture;
  final ImageCacheDirectoryResolver _directoryResolver;
  final SiteUrlResolver _urlResolver;
  final ImageFileDownloader _downloader;
  final CacheMutationReporter _mutationReporter;
  final Map<String, Future<CachedImageResult>> _ensureTasks =
      <String, Future<CachedImageResult>>{};

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    final cacheKey = request.cacheKey.trim();
    final sourceUrl =
        _urlResolver.resolve(request.sourceUrl) ?? request.sourceUrl.trim();
    final identity = '$cacheKey\n$sourceUrl';
    final existing = _ensureTasks[identity];
    if (existing != null) {
      return existing;
    }
    late final Future<CachedImageResult> task;
    task = _ensureCached(request).whenComplete(() {
      if (identical(_ensureTasks[identity], task)) {
        _ensureTasks.remove(identity);
      }
    });
    _ensureTasks[identity] = task;
    return task;
  }

  Future<CachedImageResult> _ensureCached(ImageCacheRequest request) async {
    final cacheKey = request.cacheKey.trim();
    final sourceUrl =
        _urlResolver.resolve(request.sourceUrl) ?? request.sourceUrl.trim();
    if (cacheKey.isEmpty || sourceUrl.isEmpty) {
      return CachedImageResult.failed;
    }

    final now = DateTime.now();
    final existing = await _repository.getByKey(cacheKey);
    final existingSourceUrl = existing?.lastSourceUrl?.trim();
    final sourceChanged =
        existingSourceUrl != null &&
        existingSourceUrl.isNotEmpty &&
        existingSourceUrl != sourceUrl;
    final existingPath = existing?.localPath?.trim();
    if (!sourceChanged && existingPath != null && existingPath.isNotEmpty) {
      final file = io.File(existingPath);
      if (await file.exists()) {
        final bytes = await file.length();
        await _repository.upsert(
          _recordFromRequest(
            request,
            sourceUrl: sourceUrl,
            localPath: file.path,
            bytes: bytes,
            now: now,
            createdAt: existing?.createdAt,
            width: existing?.width,
            height: existing?.height,
          ),
        );
        return CachedImageResult(
          success: true,
          cacheKey: cacheKey,
          localPath: file.path,
          bytes: bytes,
          fromCache: true,
          width: existing?.width,
          height: existing?.height,
        );
      }
    }

    final cacheManager = await _cacheManagerFuture;
    final cached = await cacheManager.getFileFromCache(cacheKey);
    if (!sourceChanged &&
        cached != null &&
        await io.File(cached.file.path).exists()) {
      final bytes = await io.File(cached.file.path).length();
      await _repository.upsert(
        _recordFromRequest(
          request,
          sourceUrl: sourceUrl,
          localPath: cached.file.path,
          bytes: bytes,
          now: now,
          createdAt: existing?.createdAt,
          width: existing?.width,
          height: existing?.height,
        ),
      );
      return CachedImageResult(
        success: true,
        cacheKey: cacheKey,
        localPath: cached.file.path,
        bytes: bytes,
        fromCache: true,
        width: existing?.width,
        height: existing?.height,
      );
    }

    try {
      final referer = request.referer;
      final headers = referer == null
          ? const <String, String>{}
          : <String, String>{'Referer': referer};
      final localPath = await _downloader.download(
        cacheManager: cacheManager,
        sourceUrl: sourceUrl,
        cacheKey: cacheKey,
        headers: headers.isEmpty ? null : headers,
        force: sourceChanged,
      );
      final bytes = await io.File(localPath).length();
      await _repository.upsert(
        _recordFromRequest(
          request,
          sourceUrl: sourceUrl,
          localPath: localPath,
          bytes: bytes,
          now: now,
          createdAt: existing?.createdAt,
          width: sourceChanged ? null : existing?.width,
          height: sourceChanged ? null : existing?.height,
        ),
      );
      _mutationReporter.reportMutation(CacheNamespace.image);
      return CachedImageResult(
        success: true,
        cacheKey: cacheKey,
        localPath: localPath,
        bytes: bytes,
        width: sourceChanged ? null : existing?.width,
        height: sourceChanged ? null : existing?.height,
      );
    } catch (_) {
      return CachedImageResult.failed;
    }
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final record = await _repository.getByKey(normalized);
    if (record == null) {
      return null;
    }
    final path = record.localPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = io.File(path);
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.length();
    await _repository.touch(normalized, DateTime.now());
    return CachedImageResult(
      success: true,
      cacheKey: normalized,
      localPath: path,
      bytes: bytes,
      fromCache: true,
      width: record.width,
      height: record.height,
    );
  }

  @override
  Future<Size?> getLastKnownDimensions({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
    required ImageCacheRole role,
    String? preferredCacheKey,
  }) async {
    final normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.isEmpty) {
      return null;
    }
    final preferredKey = preferredCacheKey?.trim();
    if (preferredKey != null && preferredKey.isNotEmpty) {
      final preferred = await _repository.getByKey(preferredKey);
      final preferredSize = _dimensionsForRecord(
        preferred,
        ownerType: ownerType,
        ownerId: normalizedOwnerId,
        role: role,
      );
      if (preferredSize != null) {
        return preferredSize;
      }
    }

    final records =
        <CachedImageRecord>[
          ...await _repository.listByOwner(
            ownerType: ownerType.dbValue,
            ownerId: normalizedOwnerId,
          ),
        ]..sort((left, right) {
          final updated = left.updatedAt.compareTo(right.updatedAt);
          if (updated != 0) {
            return updated;
          }
          final created = left.createdAt.compareTo(right.createdAt);
          if (created != 0) {
            return created;
          }
          return left.cacheKey.compareTo(right.cacheKey);
        });
    for (final record in records.reversed) {
      final size = _dimensionsForRecord(
        record,
        ownerType: ownerType,
        ownerId: normalizedOwnerId,
        role: role,
      );
      if (size != null) {
        return size;
      }
    }
    return null;
  }

  Size? _dimensionsForRecord(
    CachedImageRecord? record, {
    required ImageCacheOwnerType ownerType,
    required String ownerId,
    required ImageCacheRole role,
  }) {
    if (record == null ||
        record.ownerType != ownerType.dbValue ||
        record.ownerId != ownerId ||
        record.role != role.dbValue) {
      return null;
    }
    final width = record.width;
    final height = record.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }

  @override
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  }) async {
    final normalized = cacheKey.trim();
    final width = size.width.round();
    final height = size.height.round();
    if (normalized.isEmpty || width <= 0 || height <= 0) {
      return;
    }
    await _repository.updateDimensions(
      cacheKey: normalized,
      width: width,
      height: height,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    final source = io.File(request.sourcePath);
    if (!await source.exists()) {
      return CachedImageResult.failed;
    }
    final protectedDir = await _directoryResolver.resolveProtectedDirectory();
    final extension = p.extension(source.path).trim();
    final fileName =
        '${_fileNameSafe(request.cacheKey)}${extension.isEmpty ? '.img' : extension}';
    final target = io.File(p.join(protectedDir, fileName));
    await target.parent.create(recursive: true);
    await source.copy(target.path);

    final bytes = await target.length();
    final now = DateTime.now();
    await _repository.upsert(
      CachedImageRecord(
        cacheKey: request.cacheKey,
        ownerType: request.ownerType.dbValue,
        ownerId: request.ownerId,
        episodeId: request.episodeId,
        imageIndex: request.imageIndex,
        role: request.role.dbValue,
        localPath: target.path,
        bytes: bytes,
        protected: true,
        retentionClass: request.retentionClass,
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: target.path,
      bytes: bytes,
    );
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    final records = await _repository.listByOwner(
      ownerType: ownerType.dbValue,
      ownerId: ownerId,
    );
    for (final record in records) {
      await _deleteRecord(record);
    }
    return records.length;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) {
    return _repository.calculateUsageBytes(includeProtected: includeProtected);
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    if (maxBytes <= 0) {
      await clearUnprotected();
      return;
    }
    var usage = (await loadUsage()).budgetedBytes;
    if (usage <= maxBytes) {
      return;
    }
    final records = await _repository.listUnprotectedByAccessTime();
    for (final record in records.where(_isRegularRecord)) {
      await _deleteRecord(record);
      usage -= record.bytes;
      if (usage <= maxBytes) {
        break;
      }
    }
  }

  @override
  Future<void> clearUnprotected() async {
    await clearRegular();
  }

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    if (roles.isEmpty) {
      return 0;
    }
    final records = await _repository.listUnprotectedByRoles(
      roles: roles.map((r) => r.dbValue).toList(growable: false),
    );
    for (final record in records) {
      await _deleteRecord(record);
    }
    return records.length;
  }

  @override
  String get participantId => 'image';

  @override
  Future<CacheParticipantUsage> loadUsage() async {
    final groups = await _repository.calculateUsageGroups();
    var regularBytes = 0;
    var longTermBytes = 0;
    for (final group in groups) {
      if (group.protected || _isProtectedRetention(group.retentionClass)) {
        continue;
      }
      if (group.retentionClass == ImageRetentionClass.sticky.dbValue) {
        longTermBytes += group.bytes;
      } else {
        regularBytes += group.bytes;
      }
    }
    return CacheParticipantUsage(
      clearableBytes: regularBytes,
      budgetedBytes: regularBytes,
      longTermBytes: longTermBytes,
    );
  }

  @override
  Future<List<CacheEvictionCandidate>> loadEvictionCandidates() async {
    final records = await _repository.listUnprotectedByAccessTime();
    return records
        .where(_isRegularRecord)
        .map((record) {
          return CacheEvictionCandidate(
            participantId: participantId,
            cacheKey: record.cacheKey,
            bytes: record.bytes,
            lastAccessedAt: record.lastAccessedAt ?? record.updatedAt,
            priority: record.retentionClass == ImageRetentionClass.recentReader
                ? CacheEvictionPriority.recentReaderImage
                : CacheEvictionPriority.regularImage,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<bool> deleteCandidate(CacheEvictionCandidate candidate) async {
    if (candidate.participantId != participantId) {
      return false;
    }
    final record = await _repository.getByKey(candidate.cacheKey);
    if (record == null || !_isRegularRecord(record)) {
      return false;
    }
    await _deleteRecord(record);
    return true;
  }

  @override
  Future<CacheParticipantClearResult> clearRegular() async {
    final records = await _repository.listUnprotectedByAccessTime();
    final clearable = records.where(_isRegularRecord).toList(growable: false);
    var deletedBytes = 0;
    for (final record in clearable) {
      await _deleteRecord(record);
      deletedBytes += record.bytes;
    }
    return CacheParticipantClearResult(
      deletedEntries: clearable.length,
      deletedBytes: deletedBytes,
    );
  }

  bool _isRegularRecord(CachedImageRecord record) {
    return !record.protected &&
        record.retentionClass != ImageRetentionClass.sticky &&
        record.retentionClass != ImageRetentionClass.protected &&
        record.retentionClass != ImageRetentionClass.downloaded;
  }

  bool _isProtectedRetention(String retentionClass) {
    return retentionClass == ImageRetentionClass.protected.dbValue ||
        retentionClass == ImageRetentionClass.downloaded.dbValue;
  }

  CachedImageRecord _recordFromRequest(
    ImageCacheRequest request, {
    required String sourceUrl,
    required String localPath,
    required int bytes,
    required DateTime now,
    DateTime? createdAt,
    int? width,
    int? height,
  }) {
    return CachedImageRecord(
      cacheKey: request.cacheKey,
      ownerType: request.ownerType.dbValue,
      ownerId: request.ownerId,
      episodeId: request.episodeId,
      imageIndex: request.imageIndex,
      role: request.role.dbValue,
      lastSourceUrl: sourceUrl,
      localPath: localPath,
      bytes: bytes,
      width: width,
      height: height,
      protected: request.protected,
      retentionClass: request.effectiveRetentionClass,
      createdAt: createdAt ?? now,
      updatedAt: now,
      lastAccessedAt: now,
    );
  }

  Future<void> _deleteRecord(CachedImageRecord record) async {
    final localPath = record.localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      final file = io.File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    try {
      final cacheManager = await _cacheManagerFuture;
      await cacheManager.removeFile(record.cacheKey);
    } catch (_) {
      // The SQLite record is authoritative for pruning.  Cache-manager metadata
      // may already be gone, so failure here should not block cleanup.
    }
    await _repository.deleteByKey(record.cacheKey);
  }

  String _fileNameSafe(String value) {
    return value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }
}
