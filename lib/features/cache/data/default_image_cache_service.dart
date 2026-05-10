import 'dart:io' as io;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/data/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';

abstract class ImageFileDownloader {
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
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
  }) async {
    final fileInfo = await cacheManager.downloadFile(
      sourceUrl,
      key: cacheKey,
      authHeaders: headers,
    );
    return fileInfo.file.path;
  }
}

class DefaultImageCacheService implements ImageCacheService {
  DefaultImageCacheService({
    required ImageCacheRepository repository,
    required Future<BaseCacheManager> cacheManagerFuture,
    required ImageCacheDirectoryResolver directoryResolver,
    ImageRequestHeaderBuilder? headerBuilder,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ImageFileDownloader downloader = const CacheManagerImageFileDownloader(),
  })  : _repository = repository,
        _cacheManagerFuture = cacheManagerFuture,
        _directoryResolver = directoryResolver,
        _headerBuilder = headerBuilder,
        _urlResolver = urlResolver,
        _downloader = downloader;

  final ImageCacheRepository _repository;
  final Future<BaseCacheManager> _cacheManagerFuture;
  final ImageCacheDirectoryResolver _directoryResolver;
  final ImageRequestHeaderBuilder? _headerBuilder;
  final SiteUrlResolver _urlResolver;
  final ImageFileDownloader _downloader;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    final cacheKey = request.cacheKey.trim();
    final sourceUrl = _urlResolver.resolve(request.sourceUrl) ?? request.sourceUrl.trim();
    if (cacheKey.isEmpty || sourceUrl.isEmpty) {
      return CachedImageResult.failed;
    }

    final now = DateTime.now();
    final existing = await _repository.getByKey(cacheKey);
    final existingPath = existing?.localPath?.trim();
    if (existingPath != null && existingPath.isNotEmpty) {
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
          ),
        );
        return CachedImageResult(
          success: true,
          cacheKey: cacheKey,
          localPath: file.path,
          bytes: bytes,
          fromCache: true,
        );
      }
    }

    final cacheManager = await _cacheManagerFuture;
    final cached = await cacheManager.getFileFromCache(cacheKey);
    if (cached != null && await io.File(cached.file.path).exists()) {
      final bytes = await io.File(cached.file.path).length();
      await _repository.upsert(
        _recordFromRequest(
          request,
          sourceUrl: sourceUrl,
          localPath: cached.file.path,
          bytes: bytes,
          now: now,
          createdAt: existing?.createdAt,
        ),
      );
      return CachedImageResult(
        success: true,
        cacheKey: cacheKey,
        localPath: cached.file.path,
        bytes: bytes,
        fromCache: true,
      );
    }

    try {
      final headers = await _buildHeaders(sourceUrl);
      final localPath = await _downloader.download(
        cacheManager: cacheManager,
        sourceUrl: sourceUrl,
        cacheKey: cacheKey,
        headers: headers.isEmpty ? null : headers,
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
        ),
      );
      return CachedImageResult(
        success: true,
        cacheKey: cacheKey,
        localPath: localPath,
        bytes: bytes,
      );
    } catch (_) {
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
    final path = record?.localPath?.trim();
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
    final fileName = '${_fileNameSafe(request.cacheKey)}${extension.isEmpty ? '.img' : extension}';
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
    for (final record in records) {
      await _deleteRecord(record);
      usage -= record.bytes;
      if (usage <= maxBytes) {
        break;
      }
    }
  }

  @override
  Future<void> clearUnprotected() async {
    final records = await _repository.listUnprotectedByAccessTime();
    for (final record in records) {
      await _deleteRecord(record);
    }
  }

  CachedImageRecord _recordFromRequest(
    ImageCacheRequest request, {
    required String sourceUrl,
    required String localPath,
    required int bytes,
    required DateTime now,
    DateTime? createdAt,
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
      protected: request.protected,
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
