import 'dart:io' as io;
import 'dart:ui';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

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
    implements ImageCacheService, ImageCacheDimensionRecorder {
  DefaultImageCacheService({
    required ImageCacheRepository repository,
    required Future<BaseCacheManager> cacheManagerFuture,
    required ImageCacheDirectoryResolver directoryResolver,
    ImageRequestHeaderBuilder? headerBuilder,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ImageFileDownloader downloader = const CacheManagerImageFileDownloader(),
    CacheDiagnosticRecorder diagnosticRecorder =
        const NoopCacheDiagnosticRecorder(),
  }) : _repository = repository,
       _cacheManagerFuture = cacheManagerFuture,
       _directoryResolver = directoryResolver,
       _headerBuilder = headerBuilder,
       _urlResolver = urlResolver,
       _downloader = downloader,
       _diagnosticRecorder = diagnosticRecorder;

  final ImageCacheRepository _repository;
  final Future<BaseCacheManager> _cacheManagerFuture;
  final ImageCacheDirectoryResolver _directoryResolver;
  final ImageRequestHeaderBuilder? _headerBuilder;
  final SiteUrlResolver _urlResolver;
  final ImageFileDownloader _downloader;
  final CacheDiagnosticRecorder _diagnosticRecorder;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    final cacheKey = request.cacheKey.trim();
    final sourceUrl =
        _urlResolver.resolve(request.sourceUrl) ?? request.sourceUrl.trim();
    if (cacheKey.isEmpty || sourceUrl.isEmpty) {
      _recordImageEvent(
        event: 'miss',
        request: request,
        cacheKey: cacheKey,
        reason: 'invalid_request',
        hit: false,
      );
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
        _recordImageEvent(
          event: 'hit',
          request: request,
          cacheKey: cacheKey,
          reason: 'indexed_file',
          hit: true,
          fields: <String, Object?>{'bytes': bytes},
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
      _recordImageEvent(
        event: 'miss',
        request: request,
        cacheKey: cacheKey,
        reason: 'indexed_file_missing',
        hit: false,
      );
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
      _recordImageEvent(
        event: 'hit',
        request: request,
        cacheKey: cacheKey,
        reason: 'cache_manager_file',
        hit: true,
        fields: <String, Object?>{'bytes': bytes},
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
      _recordImageEvent(
        event: sourceChanged ? 'refresh' : 'miss',
        request: request,
        cacheKey: cacheKey,
        reason: sourceChanged ? 'source_changed' : 'not_cached',
        hit: false,
      );
      final headers = await _buildHeaders(sourceUrl);
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
      _recordImageEvent(
        event: 'write',
        request: request,
        cacheKey: cacheKey,
        reason: 'downloaded',
        fields: <String, Object?>{'bytes': bytes},
      );
      return CachedImageResult(
        success: true,
        cacheKey: cacheKey,
        localPath: localPath,
        bytes: bytes,
        width: sourceChanged ? null : existing?.width,
        height: sourceChanged ? null : existing?.height,
      );
    } catch (_) {
      _recordImageEvent(
        event: 'miss',
        request: request,
        cacheKey: cacheKey,
        reason: 'download_failed',
        hit: false,
      );
      return CachedImageResult.failed;
    }
  }

  Future<Map<String, String>> _buildHeaders(String sourceUrl) async {
    final builder = _headerBuilder;
    if (builder == null) {
      return const <String, String>{};
    }
    return builder.buildHeaders(sourceUrl);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final record = await _repository.getByKey(normalized);
    if (record == null) {
      _diagnosticRecorder.record(
        CacheDiagnosticEvent(
          event: 'miss',
          namespace: CacheNamespace.image,
          bucket: StorageBucket.imageCache,
          cacheKey: normalized,
          reason: 'record_missing',
          hit: false,
        ),
      );
      return null;
    }
    final path = record.localPath?.trim();
    if (path == null || path.isEmpty) {
      _diagnosticRecorder.record(
        CacheDiagnosticEvent(
          event: 'miss',
          namespace: CacheNamespace.image,
          bucket: StorageBucket.imageCache,
          cacheKey: normalized,
          reason: 'path_missing',
          hit: false,
        ),
      );
      return null;
    }
    final file = io.File(path);
    if (!await file.exists()) {
      _diagnosticRecorder.record(
        CacheDiagnosticEvent(
          event: 'miss',
          namespace: CacheNamespace.image,
          bucket: StorageBucket.imageCache,
          cacheKey: normalized,
          reason: 'file_missing',
          hit: false,
        ),
      );
      return null;
    }
    final bytes = await file.length();
    await _repository.touch(normalized, DateTime.now());
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'hit',
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        cacheKey: normalized,
        reason: 'direct_lookup',
        hit: true,
        fields: <String, Object?>{'bytes': bytes},
      ),
    );
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
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'write',
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        cacheKey: request.cacheKey,
        ownerType: _cacheOwnerTypeFor(request.ownerType),
        ownerId: request.ownerId,
        reason: 'protected_copy',
        fields: <String, Object?>{'bytes': bytes, 'role': request.role.dbValue},
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
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'prune',
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        ownerType: _cacheOwnerTypeFor(ownerType),
        ownerId: ownerId,
        reason: 'owner_deleted',
        fields: <String, Object?>{'deleted': records.length},
      ),
    );
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
    var usage = await calculateUsageBytes();
    if (usage <= maxBytes) {
      return;
    }
    final records = await _repository.listUnprotectedByAccessTime();
    var deleted = 0;
    for (final record in records) {
      await _deleteRecord(record);
      deleted += 1;
      usage -= record.bytes;
      if (usage <= maxBytes) {
        break;
      }
    }
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'prune',
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        reason: 'max_bytes',
        fields: <String, Object?>{
          'deleted': deleted,
          'maxBytes': maxBytes,
          'remainingBytes': usage,
        },
      ),
    );
  }

  @override
  Future<void> clearUnprotected() async {
    final records = await _repository.listUnprotectedByAccessTime();
    for (final record in records) {
      await _deleteRecord(record);
    }
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: 'prune',
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        reason: 'clear_unprotected',
        fields: <String, Object?>{'deleted': records.length},
      ),
    );
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

  void _recordImageEvent({
    required String event,
    required ImageCacheRequest request,
    required String cacheKey,
    String? reason,
    bool? hit,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _diagnosticRecorder.record(
      CacheDiagnosticEvent(
        event: event,
        namespace: CacheNamespace.image,
        bucket: StorageBucket.imageCache,
        cacheKey: cacheKey.isEmpty ? request.cacheKey : cacheKey,
        ownerType: _cacheOwnerTypeFor(request.ownerType),
        ownerId: request.ownerId,
        hit: hit,
        reason: reason,
        fields: <String, Object?>{
          'role': request.role.dbValue,
          'retentionClass': request.effectiveRetentionClass,
          'protected': request.protected,
          ...fields,
        },
      ),
    );
  }

  CacheOwnerType? _cacheOwnerTypeFor(ImageCacheOwnerType ownerType) {
    for (final candidate in CacheOwnerType.values) {
      if (candidate.id == ownerType.dbValue) {
        return candidate;
      }
    }
    return null;
  }
}
