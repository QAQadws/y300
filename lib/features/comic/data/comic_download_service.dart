import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

abstract class ComicDownloadService {
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
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

class DefaultComicDownloadService implements ComicDownloadService {
  DefaultComicDownloadService({
    required ComicRepository repository,
    required Future<ComicReaderService> readerServiceFuture,
    required DownloadStorageService storageService,
  })  : _repository = repository,
        _readerServiceFuture = readerServiceFuture,
        _storageService = storageService;

  final ComicRepository _repository;
  final Future<ComicReaderService> _readerServiceFuture;
  final DownloadStorageService _storageService;

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
  }) async {
    final detail = await _requireDetail(comicId);
    final episodes = await _repository.getComicEpisodes(comicId: comicId, descending: false);
    final episodeIndex = episodes.indexWhere((item) => item.episodeId == episodeId);
    if (episodeIndex < 0) {
      throw StateError('漫画章节不存在');
    }
    final episode = episodes[episodeIndex];
    final images = await _ensureEpisodeImages(episode: episode);
    if (images.isEmpty) {
      throw StateError('当前章节没有可下载图片');
    }

    final comicDir = await _storageService.prepareComicDirectory(
      workId: detail.comicId,
      title: detail.title,
    );
    await _copyCoverIfPossible(detail: detail, comicDir: comicDir);

    final tempDir = io.Directory(
      p.join(comicDir.path, '.tmp', '${_storageService.safeFileName(episodeId)}-${DateTime.now().microsecondsSinceEpoch}'),
    );
    await tempDir.create(recursive: true);

    final imageFiles = <String>[];
    try {
      for (final image in images) {
        final source = await _resolveImageFile(detail: detail, image: image);
        final extension = _imageExtension(
          localPath: source.path,
          mimeType: image.mimeType,
          sourceUrl: image.effectiveSourceUrl,
        );
        final fileName = '${(image.imageIndex + 1).toString().padLeft(3, '0')}$extension';
        await source.copy(p.join(tempDir.path, fileName));
        imageFiles.add(fileName);
      }

      final cbzFile = _storageService.numberedFileName(
        index: episodeIndex,
        title: episode.episodeTitle ?? episode.sourceTid,
        extension: '.cbz',
      );
      final cbzPath = p.join(comicDir.path, cbzFile);
      final encoder = ZipFileEncoder();
      await encoder.zipDirectory(
        tempDir,
        filename: cbzPath,
      );

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

      return DownloadedComicEpisode(
        workId: comicId,
        episodeId: episodeId,
        cbzPath: cbzPath,
        imageFiles: imageFiles,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
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
    return extracted.asMap().entries.map((entry) {
      final dbImage = entry.key < dbImages.length ? dbImages[entry.key] : null;
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
    }).toList(growable: false);
  }

  Future<ComicDetail> _requireDetail(String comicId) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      throw StateError('漫画不存在或已删除');
    }
    return detail;
  }

  Future<List<ComicEpisodeImageItem>> _ensureEpisodeImages({
    required ComicEpisodeItem episode,
  }) async {
    var images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    if (images.isNotEmpty) {
      return images;
    }
    final readerService = await _readerServiceFuture;
    final fetched = await readerService.fetchEpisodeImagesByTid(episode.sourceTid);
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
  }) async {
    final local = image.effectiveLocalPath;
    if (local != null) {
      final file = io.File(local);
      if (await file.exists()) {
        return file;
      }
    }

    final cacheKey = image.stableCacheKey ??
        ImageCacheKeys.comicPage(
          comicId: detail.comicId,
          episodeId: image.episodeId,
          imageIndex: image.imageIndex,
        );
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
      throw StateError('图片下载失败：${image.effectiveSourceUrl}');
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
  }) async {
    final target = io.File(p.join(comicDir.path, 'cover.jpg'));
    if (await target.exists()) {
      return;
    }
    final localCover = _firstExistingPath(
      <String?>[
        detail.customCoverLocalPath,
        detail.coverLocalPath,
      ],
    );
    if (localCover != null) {
      await io.File(localCover).copy(target.path);
      return;
    }
    final coverUrl = detail.coverImageUrl?.trim();
    if (coverUrl == null || coverUrl.isEmpty) {
      return;
    }
    final readerService = await _readerServiceFuture;
    final result = await readerService.cacheImage(
      imageUrl: coverUrl,
      cacheKey: ImageCacheKeys.comicCover(detail.comicId),
      ownerType: ImageCacheOwnerType.comic,
      ownerId: detail.comicId,
      role: ImageCacheRole.cover,
      protected: true,
    );
    final path = result.localPath;
    if (result.success && path != null && await io.File(path).exists()) {
      await io.File(path).copy(target.path);
    }
  }

  Future<void> _writeMeta({
    required ComicDetail detail,
    required List<ComicEpisodeItem> episodes,
    required _ComicDownloadedChapterDraft downloaded,
    required io.Directory comicDir,
  }) async {
    final existing = await _readMeta(comicDir);
    final oldChapters = (existing?['chapters'] as List?)
            ?.whereType<Map>()
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    final oldByEpisodeId = <String, Map<String, Object?>>{
      for (final chapter in oldChapters)
        if (chapter['episodeId'] is String) chapter['episodeId'] as String: chapter,
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
        'coverFile': await io.File(p.join(comicDir.path, 'cover.jpg')).exists() ? 'cover.jpg' : null,
        'customCoverFile': null,
        'favorite': existing?['favorite'],
        'tags': <String, Object?>{
          'source': <String, Object?>{
            'typeid': detail.sourceTypeId,
            'name': detail.sourceTagName,
          },
          'custom': existing?['tags'] is Map ? (existing!['tags'] as Map)['custom'] : <Object?>[],
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
    final chapters = (existing['chapters'] as List?)
            ?.whereType<Map>()
            .where((item) => item['episodeId'] != episodeId)
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
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

  Future<List<io.File>> _extractCbzForReading(DownloadedComicEpisode downloaded) async {
    final targetDir = io.Directory(
      p.join(
        io.Directory.systemTemp.path,
        'y300_download_reader',
        _storageService.safeFileName(downloaded.workId),
        _storageService.safeFileName(downloaded.episodeId),
      ),
    );
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(await io.File(downloaded.cbzPath).readAsBytes());
    final files = archive.files.where((entry) => entry.isFile).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final extracted = <io.File>[];
    for (final entry in files) {
      final bytes = entry.readBytes();
      if (bytes == null) {
        continue;
      }
      // CBZ entries are flattened deliberately to avoid zip-slip paths from
      // ever escaping the temporary reader directory.
      final target = io.File(p.join(targetDir.path, p.basename(entry.name)));
      await target.writeAsBytes(bytes);
      extracted.add(target);
    }
    return extracted;
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
    await (_repository as ComicEpisodeImageCacheMetadataWriter).updateEpisodeImageCacheMetadata(
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
      if (trimmed != null && trimmed.isNotEmpty && io.File(trimmed).existsSync()) {
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
    final sourceExt = p.extension(Uri.tryParse(sourceUrl)?.path ?? sourceUrl).toLowerCase();
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

final comicDownloadServiceProvider = Provider<ComicDownloadService>((ref) {
  return DefaultComicDownloadService(
    repository: ref.watch(comicRepositoryProvider),
    readerServiceFuture: ref.watch(comicReaderServiceProvider.future),
    storageService: ref.watch(downloadStorageServiceProvider),
  );
});
