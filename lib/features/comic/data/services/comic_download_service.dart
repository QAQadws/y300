import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';

abstract class ComicDownloadService {
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  });

  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  });

  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  });
}

class DefaultComicDownloadService
    implements ComicDownloadService, ComicDownloadAvailabilityChecker {
  DefaultComicDownloadService({
    required ComicRepository repository,
    required Future<ComicReaderService> readerServiceFuture,
    required DownloadStorageService storageService,
    ImageCacheService? imageCacheService,
    LibraryCoverStore? coverStore,
    ComicDownloadImageRequestGovernor? imageRequestGovernor,
    io.Directory? readerExtractionRoot,
  }) : _repository = repository,
       _readerServiceFuture = readerServiceFuture,
       _storageService = storageService,
       _imageCacheService = imageCacheService,
       _coverStore = coverStore,
       _imageRequestGovernor =
           imageRequestGovernor ?? DefaultComicDownloadImageRequestGovernor(),
       _readerExtractionRoot =
           readerExtractionRoot ??
           io.Directory(
             p.join(io.Directory.systemTemp.path, 'y300_download_reader'),
           );

  final ComicRepository _repository;
  final Future<ComicReaderService> _readerServiceFuture;
  final DownloadStorageService _storageService;
  final ImageCacheService? _imageCacheService;
  final LibraryCoverStore? _coverStore;
  final ComicDownloadImageRequestGovernor _imageRequestGovernor;
  final io.Directory _readerExtractionRoot;
  final Map<String, Future<List<io.File>>> _readerExtractionTasks =
      <String, Future<List<io.File>>>{};

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final detail = await _requireDetail(comicId);
    final episodes = await _repository.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    final episodeIndex = episodes.indexWhere(
      (item) => item.episodeId == episodeId,
    );
    if (episodeIndex < 0) {
      throw const ComicDownloadFailedException(
        ComicDownloadFailureCode.episodeUnavailable,
      );
    }
    final episode = episodes[episodeIndex];
    final existing = await _storageService.findDownloadedComicEpisode(
      workId: comicId,
      title: detail.title,
      episodeId: episodeId,
    );
    if (existing != null && await _isValidDownloadedEpisode(existing)) {
      cancellationToken?.throwIfCancellationRequested();
      await observer?.onImagesResolved(existing.imageFiles.length);
      await observer?.onImageCompleted(
        completedImages: existing.imageFiles.length,
        totalImages: existing.imageFiles.length,
      );
      cancellationToken?.throwIfCancellationRequested();
      return existing;
    }
    if (existing != null) {
      final invalidFile = io.File(existing.cbzPath);
      if (await invalidFile.exists()) {
        await invalidFile.delete();
      }
    }

    final comicDir = await _storageService.prepareComicDirectory(
      workId: detail.comicId,
      title: detail.title,
    );
    final cbzFile = _storageService.numberedFileName(
      index: episodeIndex,
      title: episode.episodeTitle ?? episode.sourceTid,
      extension: '.cbz',
    );
    final finalCbz = io.File(p.join(comicDir.path, cbzFile));
    final partialCbz = io.File('${finalCbz.path}.part');
    await _cleanupInterruptedArtifacts(
      comicDir: comicDir,
      episodeId: episodeId,
      finalCbz: finalCbz,
      partialCbz: partialCbz,
    );

    final images = await _ensureEpisodeImages(episode: episode);
    if (images.isEmpty) {
      throw const ComicDownloadFailedException(
        ComicDownloadFailureCode.noImages,
      );
    }
    await observer?.onImagesResolved(images.length);
    cancellationToken?.throwIfCancellationRequested();

    await _copyCoverIfPossible(
      detail: detail,
      comicDir: comicDir,
      cancellationToken: cancellationToken,
    );

    final tempDir = io.Directory(
      p.join(
        comicDir.path,
        '.tmp',
        '${_storageService.safeFileName(episodeId)}-'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await tempDir.create(recursive: true);

    final imageFiles = <String>[];
    var committed = false;
    try {
      for (final image in images) {
        cancellationToken?.throwIfCancellationRequested();
        final source = await _resolveImageFile(
          detail: detail,
          image: image,
          cancellationToken: cancellationToken,
        );
        final extension = _imageExtension(
          localPath: source.path,
          mimeType: image.mimeType,
          sourceUrl: image.effectiveSourceUrl,
        );
        final fileName =
            '${(image.imageIndex + 1).toString().padLeft(3, '0')}$extension';
        await source.copy(p.join(tempDir.path, fileName));
        imageFiles.add(fileName);
        await observer?.onImageCompleted(
          completedImages: imageFiles.length,
          totalImages: images.length,
        );
      }
      cancellationToken?.throwIfCancellationRequested();

      final encoder = ZipFileEncoder();
      await encoder.zipDirectory(tempDir, filename: partialCbz.path);
      cancellationToken?.throwIfCancellationRequested();
      if (await finalCbz.exists()) {
        await finalCbz.delete();
      }
      await partialCbz.rename(finalCbz.path);
      cancellationToken?.throwIfCancellationRequested();

      await _writeMeta(
        detail: detail,
        episodes: episodes,
        downloaded: _ComicDownloadedChapterDraft(
          episode: episode,
          episodeIndex: episodeIndex,
          cbzFile: cbzFile,
          imageFiles: imageFiles,
        ),
        comicDir: comicDir,
      );
      committed = true;

      return DownloadedComicEpisode(
        workId: comicId,
        episodeId: episodeId,
        cbzPath: finalCbz.path,
        imageFiles: imageFiles,
      );
    } finally {
      if (!committed && await finalCbz.exists()) {
        await finalCbz.delete();
      }
      if (await partialCbz.exists()) {
        await partialCbz.delete();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  @override
  Future<bool> hasValidEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      return false;
    }
    final existing = await _storageService.findDownloadedComicEpisode(
      workId: comicId,
      title: detail.title,
      episodeId: episodeId,
    );
    return existing != null && await _isValidDownloadedEpisode(existing);
  }

  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      return;
    }
    final downloaded = await _storageService.findDownloadedComicEpisode(
      workId: comicId,
      title: detail.title,
      episodeId: episodeId,
    );
    if (downloaded != null) {
      final cbz = io.File(downloaded.cbzPath);
      if (await cbz.exists()) {
        await cbz.delete();
      }
    }
    await _removeChapterFromMeta(detail: detail, episodeId: episodeId);
  }

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      return const <ComicEpisodeImageItem>[];
    }
    final downloaded = await _storageService.findDownloadedComicEpisode(
      workId: comicId,
      title: detail.title,
      episodeId: episodeId,
    );
    if (downloaded == null) {
      return const <ComicEpisodeImageItem>[];
    }

    final extracted = await _extractCbzForReading(downloaded);
    if (extracted.isEmpty) {
      return const <ComicEpisodeImageItem>[];
    }

    final dbImages = await _repository.getEpisodeImages(episodeId: episodeId);
    return extracted
        .asMap()
        .entries
        .map((entry) {
          final dbImage = entry.key < dbImages.length
              ? dbImages[entry.key]
              : null;
          return ComicEpisodeImageItem(
            episodeId: episodeId,
            imageUrl: dbImage?.imageUrl ?? entry.value.uri.toString(),
            imageIndex: entry.key,
            cacheStatus: 'downloaded',
            stableCacheKey: dbImage?.stableCacheKey,
            lastSourceUrl: dbImage?.lastSourceUrl,
            localPath: entry.value.path,
            bytes: entry.value.lengthSync(),
            mimeType: dbImage?.mimeType,
            lastAccessedAt: DateTime.now(),
            protected: true,
            cacheLocalPath: entry.value.path,
          );
        })
        .toList(growable: false);
  }

  Future<ComicDetail> _requireDetail(String comicId) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      throw const ComicDownloadFailedException(
        ComicDownloadFailureCode.workUnavailable,
      );
    }
    return detail;
  }

  Future<List<ComicEpisodeImageItem>> _ensureEpisodeImages({
    required ComicEpisodeItem episode,
  }) async {
    var images = await _repository.getEpisodeImages(
      episodeId: episode.episodeId,
    );
    if (images.isNotEmpty) {
      return images;
    }
    final readerService = await _readerServiceFuture;
    final result = await readerService.fetchEpisodeImages(episode.sourceTid);
    final fetched = switch (result) {
      ComicEpisodeImagesFetched(:final imageUrls) => imageUrls,
      ComicEpisodeImagesFetchFailed(:final reason, :final message) =>
        throw ComicDownloadFailedException(
          ComicDownloadFailureCode.imageDownloadFailed,
          detail: message?.trim().isNotEmpty == true ? message : reason.name,
        ),
    };
    if (fetched.isEmpty) {
      return const <ComicEpisodeImageItem>[];
    }
    await _repository.saveEpisodeImages(
      episodeId: episode.episodeId,
      imageUrls: fetched,
    );
    images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    return images;
  }

  Future<io.File> _resolveImageFile({
    required ComicDetail detail,
    required ComicEpisodeImageItem image,
    ComicDownloadCancellationToken? cancellationToken,
  }) async {
    final local = image.effectiveLocalPath;
    if (local != null) {
      final file = io.File(local);
      if (await file.exists()) {
        return file;
      }
    }

    final cacheKey =
        image.stableCacheKey ??
        ImageCacheKeys.comicPage(
          comicId: detail.comicId,
          episodeId: image.episodeId,
          imageIndex: image.imageIndex,
        );
    final cached = await _imageCacheService?.getCached(cacheKey);
    final cachedPath = cached?.localPath?.trim();
    if (cached?.success == true &&
        cachedPath != null &&
        cachedPath.isNotEmpty &&
        await io.File(cachedPath).exists()) {
      await _updateImageCacheMetadata(
        image: image,
        stableCacheKey: cacheKey,
        localPath: cachedPath,
        bytes: cached?.bytes ?? 0,
      );
      return io.File(cachedPath);
    }

    cancellationToken?.throwIfCancellationRequested();
    await _imageRequestGovernor.waitForTurn();
    cancellationToken?.throwIfCancellationRequested();
    final readerService = await _readerServiceFuture;
    final result = await readerService.cacheImage(
      imageUrl: image.effectiveSourceUrl,
      cacheKey: cacheKey,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: detail.comicId,
      role: ImageCacheRole.comicPage,
      episodeId: image.episodeId,
      imageIndex: image.imageIndex,
    );
    final path = result.localPath;
    if (!result.success || path == null || path.trim().isEmpty) {
      throw ComicDownloadFailedException(
        ComicDownloadFailureCode.imageDownloadFailed,
        detail: image.effectiveSourceUrl,
      );
    }

    await _repository.updateEpisodeImageCacheStatus(
      episodeId: image.episodeId,
      imageUrl: image.imageUrl,
      cacheStatus: 'done',
      cacheLocalPath: path,
    );
    await _updateImageCacheMetadata(
      image: image,
      stableCacheKey: result.cacheKey ?? cacheKey,
      localPath: path,
      bytes: result.bytes,
    );
    return io.File(path);
  }

  Future<void> _copyCoverIfPossible({
    required ComicDetail detail,
    required io.Directory comicDir,
    ComicDownloadCancellationToken? cancellationToken,
  }) async {
    final target = io.File(p.join(comicDir.path, 'cover.jpg'));
    if (await target.exists()) {
      return;
    }
    final coverStore = _coverStore;
    final asset = LibraryCoverAssetFactory.preferred(
      ownerType: 'comic',
      ownerId: detail.comicId,
      sourceUrl: detail.coverImageUrl,
      sourceLegacyPath: detail.coverLocalPath,
      sourceRevision: detail.coverRevision,
      customSourceUrl: detail.customCoverImageUrl,
      customLegacyPath: detail.customCoverLocalPath,
      customRevision: detail.customCoverRevision,
    );
    if (coverStore != null && asset != null) {
      cancellationToken?.throwIfCancellationRequested();
      try {
        final source = await coverStore.ensureAvailable(asset);
        cancellationToken?.throwIfCancellationRequested();
        if (await source.exists()) {
          await source.copy(target.path);
          return;
        }
      } catch (_) {
        // A missing cover must not fail an otherwise valid offline chapter.
      }
    }
    // Keep a narrow compatibility fallback for injected legacy services used
    // by older callers/tests. Production always supplies the dedicated Store.
    final localCover = _firstExistingPath(<String?>[
      detail.customCoverLocalPath,
      detail.coverLocalPath,
    ]);
    if (localCover != null) {
      await io.File(localCover).copy(target.path);
    }
  }

  Future<bool> _isValidDownloadedEpisode(
    DownloadedComicEpisode downloaded,
  ) async {
    final file = io.File(downloaded.cbzPath);
    if (downloaded.imageFiles.isEmpty ||
        !await file.exists() ||
        await file.length() <= 0) {
      return false;
    }
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final archivedNames = archive.files
          .where((entry) => entry.isFile)
          .map((entry) => p.basename(entry.name))
          .toSet();
      return downloaded.imageFiles.every(archivedNames.contains);
    } catch (_) {
      return false;
    } finally {
      await input.close();
    }
  }

  Future<void> _cleanupInterruptedArtifacts({
    required io.Directory comicDir,
    required String episodeId,
    required io.File finalCbz,
    required io.File partialCbz,
  }) async {
    if (await partialCbz.exists()) {
      await partialCbz.delete();
    }
    if (await finalCbz.exists()) {
      await finalCbz.delete();
    }
    final tempRoot = io.Directory(p.join(comicDir.path, '.tmp'));
    if (!await tempRoot.exists()) {
      return;
    }
    final prefix = '${_storageService.safeFileName(episodeId)}-';
    await for (final entity in tempRoot.list(followLinks: false)) {
      if (entity is io.Directory &&
          p.basename(entity.path).startsWith(prefix)) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> _writeMeta({
    required ComicDetail detail,
    required List<ComicEpisodeItem> episodes,
    required _ComicDownloadedChapterDraft downloaded,
    required io.Directory comicDir,
  }) async {
    final existing = await _readMeta(comicDir);
    final oldChapters =
        (existing?['chapters'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    final oldByEpisodeId = <String, Map<String, Object?>>{
      for (final chapter in oldChapters)
        if (chapter['episodeId'] is String)
          chapter['episodeId'] as String: chapter,
    };
    oldByEpisodeId[downloaded.episode.episodeId] = downloaded.toJson();

    final chapters = <Map<String, Object?>>[
      for (var i = 0; i < episodes.length; i++)
        if (oldByEpisodeId.containsKey(episodes[i].episodeId))
          <String, Object?>{
            ...oldByEpisodeId[episodes[i].episodeId]!,
            'orderIndex': i,
          },
    ];

    await _storageService.writeJsonAtomically(
      io.File(p.join(comicDir.path, 'meta.json')),
      <String, Object?>{
        'schemaVersion': 1,
        'contentType': 'comic',
        'workId': detail.comicId,
        'sourceTid': detail.sourceTid,
        'sourceFid': detail.sourceFid,
        'sourceTypeId': detail.sourceTypeId,
        'sourceTagName': detail.sourceTagName,
        'title': detail.title,
        'author': detail.author,
        'translationGroup': detail.translationGroup,
        'intro': existing?['intro'],
        'coverFile': await io.File(p.join(comicDir.path, 'cover.jpg')).exists()
            ? 'cover.jpg'
            : null,
        'customCoverFile': null,
        'favorite': existing?['favorite'],
        'tags': <String, Object?>{
          'source': <String, Object?>{
            'typeid': detail.sourceTypeId,
            'name': detail.sourceTagName,
          },
          'custom': existing?['tags'] is Map
              ? (existing!['tags'] as Map)['custom']
              : <Object?>[],
        },
        'chapters': chapters,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _removeChapterFromMeta({
    required ComicDetail detail,
    required String episodeId,
  }) async {
    final comicDir = await _storageService.prepareComicDirectory(
      workId: detail.comicId,
      title: detail.title,
    );
    final existing = await _readMeta(comicDir);
    if (existing == null) {
      return;
    }
    final chapters =
        (existing['chapters'] as List?)
            ?.whereType<Map>()
            .where((item) => item['episodeId'] != episodeId)
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    await _storageService.writeJsonAtomically(
      io.File(p.join(comicDir.path, 'meta.json')),
      <String, Object?>{
        ...existing,
        'chapters': chapters,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<List<io.File>> _extractCbzForReading(
    DownloadedComicEpisode downloaded,
  ) async {
    final archiveFile = io.File(downloaded.cbzPath);
    final stat = await archiveFile.stat();
    final archiveIdentity =
        '${stat.size}-${stat.modified.microsecondsSinceEpoch}';
    final extractionKey = '${archiveFile.absolute.path}|$archiveIdentity';
    final active = _readerExtractionTasks[extractionKey];
    if (active != null) {
      return active;
    }

    final task = _extractArchiveGeneration(
      downloaded: downloaded,
      archiveFile: archiveFile,
      archiveIdentity: archiveIdentity,
    );
    _readerExtractionTasks[extractionKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_readerExtractionTasks[extractionKey], task)) {
        _readerExtractionTasks.remove(extractionKey);
      }
    }
  }

  Future<List<io.File>> _extractArchiveGeneration({
    required DownloadedComicEpisode downloaded,
    required io.File archiveFile,
    required String archiveIdentity,
  }) async {
    final episodeRoot = io.Directory(
      p.join(
        _readerExtractionRoot.path,
        _storageService.safeFileName(downloaded.workId),
        _storageService.safeFileName(downloaded.episodeId),
      ),
    );
    final targetDir = io.Directory(p.join(episodeRoot.path, archiveIdentity));
    final published = await _readPublishedExtraction(targetDir);
    if (published != null) {
      return published;
    }

    await episodeRoot.create(recursive: true);
    final stagingDir = await episodeRoot.createTemp('.extracting-');
    var publishedByThisCall = false;
    try {
      final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
      final entries = archive.files.where((entry) => entry.isFile).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final fileNames = <String>[];
      for (final entry in entries) {
        final bytes = entry.readBytes();
        if (bytes == null) {
          continue;
        }
        // Flatten entries so a malformed CBZ can never escape the extraction
        // generation. Duplicate basenames retain the established last-write
        // behavior and are de-duplicated in the published manifest.
        final fileName = p.basename(entry.name);
        if (fileName.isEmpty) {
          continue;
        }
        final target = io.File(p.join(stagingDir.path, fileName));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
        if (!fileNames.contains(fileName)) {
          fileNames.add(fileName);
        }
      }
      await io.File(
        p.join(stagingDir.path, '.complete.json'),
      ).writeAsString(jsonEncode(fileNames), encoding: utf8, flush: true);

      try {
        await stagingDir.rename(targetDir.path);
        publishedByThisCall = true;
      } on io.FileSystemException {
        final winner = await _readPublishedExtraction(targetDir);
        if (winner != null) {
          return winner;
        }
        rethrow;
      }
      return (await _readPublishedExtraction(targetDir)) ?? const <io.File>[];
    } finally {
      if (!publishedByThisCall && await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    }
  }

  Future<List<io.File>?> _readPublishedExtraction(
    io.Directory directory,
  ) async {
    final manifest = io.File(p.join(directory.path, '.complete.json'));
    if (!await manifest.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await manifest.readAsString(encoding: utf8));
      if (decoded is! List) {
        return null;
      }
      final files = decoded
          .whereType<String>()
          .map((name) => io.File(p.join(directory.path, p.basename(name))))
          .toList(growable: false);
      if (files.isEmpty) {
        return const <io.File>[];
      }
      for (final file in files) {
        if (!await file.exists()) {
          return null;
        }
      }
      return files;
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>?> _readMeta(io.Directory directory) async {
    final file = io.File(p.join(directory.path, 'meta.json'));
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _updateImageCacheMetadata({
    required ComicEpisodeImageItem image,
    required String stableCacheKey,
    required String localPath,
    required int bytes,
  }) async {
    if (_repository is! ComicEpisodeImageCacheMetadataWriter) {
      return;
    }
    await (_repository as ComicEpisodeImageCacheMetadataWriter)
        .updateEpisodeImageCacheMetadata(
          episodeId: image.episodeId,
          imageUrl: image.imageUrl,
          stableCacheKey: stableCacheKey,
          lastSourceUrl: image.effectiveSourceUrl,
          localPath: localPath,
          width: image.width,
          height: image.height,
          bytes: bytes,
          lastAccessedAt: DateTime.now(),
          protected: false,
        );
  }

  String? _firstExistingPath(List<String?> paths) {
    for (final path in paths) {
      final trimmed = path?.trim();
      if (trimmed != null &&
          trimmed.isNotEmpty &&
          io.File(trimmed).existsSync()) {
        return trimmed;
      }
    }
    return null;
  }

  String _imageExtension({
    required String localPath,
    required String? mimeType,
    required String sourceUrl,
  }) {
    switch (mimeType?.toLowerCase()) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
    }
    final localExt = p.extension(localPath).toLowerCase();
    if (const <String>{'.jpg', '.jpeg', '.png', '.webp'}.contains(localExt)) {
      return localExt == '.jpeg' ? '.jpg' : localExt;
    }
    final sourceExt = p
        .extension(Uri.tryParse(sourceUrl)?.path ?? sourceUrl)
        .toLowerCase();
    if (const <String>{'.jpg', '.jpeg', '.png', '.webp'}.contains(sourceExt)) {
      return sourceExt == '.jpeg' ? '.jpg' : sourceExt;
    }
    return '.jpg';
  }
}

class _ComicDownloadedChapterDraft {
  const _ComicDownloadedChapterDraft({
    required this.episode,
    required this.episodeIndex,
    required this.cbzFile,
    required this.imageFiles,
  });

  final ComicEpisodeItem episode;
  final int episodeIndex;
  final String cbzFile;
  final List<String> imageFiles;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'episodeId': episode.episodeId,
      'sourceTid': episode.sourceTid,
      'title': episode.episodeTitle,
      'orderIndex': episodeIndex,
      'cbzFile': cbzFile,
      'imageCount': imageFiles.length,
      'imageFiles': imageFiles,
    };
  }
}

final class MigrationGatedComicDownloadService
    implements ComicDownloadService, ComicDownloadAvailabilityChecker {
  const MigrationGatedComicDownloadService({
    required ComicDownloadService delegate,
    required ComicDownloadAvailabilityChecker availabilityChecker,
    required StorageRootAccessGate accessGate,
  }) : _delegate = delegate,
       _availabilityChecker = availabilityChecker,
       _accessGate = accessGate;

  final ComicDownloadService _delegate;
  final ComicDownloadAvailabilityChecker _availabilityChecker;
  final StorageRootAccessGate _accessGate;

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  }) {
    return _accessGate.runWithAccess(
      () => _delegate.downloadEpisode(
        comicId: comicId,
        episodeId: episodeId,
        observer: observer,
        cancellationToken: cancellationToken,
      ),
    );
  }

  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) {
    return _accessGate.runWithAccess(
      () => _delegate.deleteEpisodeDownload(
        comicId: comicId,
        episodeId: episodeId,
      ),
    );
  }

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) {
    return _accessGate.runWithAccess(
      () => _delegate.getDownloadedEpisodeImages(
        comicId: comicId,
        episodeId: episodeId,
      ),
    );
  }

  @override
  Future<bool> hasValidEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) {
    return _accessGate.runWithAccess(
      () => _availabilityChecker.hasValidEpisodeDownload(
        comicId: comicId,
        episodeId: episodeId,
      ),
    );
  }
}

final comicDownloadImageRequestGovernorProvider =
    Provider<ComicDownloadImageRequestGovernor>((ref) {
      return DefaultComicDownloadImageRequestGovernor();
    });

final comicDownloadServiceProvider = Provider<ComicDownloadService>((ref) {
  final delegate = DefaultComicDownloadService(
    repository: ref.watch(comicRepositoryProvider),
    readerServiceFuture: ref.watch(comicReaderServiceProvider.future),
    storageService: ref.watch(downloadStorageServiceProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
    coverStore: ref.watch(libraryCoverStoreProvider),
    imageRequestGovernor: ref.watch(comicDownloadImageRequestGovernorProvider),
  );
  return MigrationGatedComicDownloadService(
    delegate: delegate,
    availabilityChecker: delegate,
    accessGate: ref.watch(storageRootAccessGateProvider),
  );
});
