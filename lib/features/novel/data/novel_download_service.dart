import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

abstract class NovelDownloadService {
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  });

  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  });

  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  });
}

class DefaultNovelDownloadService implements NovelDownloadService {
  DefaultNovelDownloadService({
    required NovelRepository repository,
    required DownloadStorageService storageService,
    ImageCacheService? imageCacheService,
  })  : _repository = repository,
        _storageService = storageService,
        _imageCacheService = imageCacheService;

  final NovelRepository _repository;
  final DownloadStorageService _storageService;
  final ImageCacheService? _imageCacheService;

  @override
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  }) async {
    final detail = await _requireDetail(novelId);
    final episodes = await _repository.getEpisodes(novelId: novelId, descending: false);
    final episodeIndex = episodes.indexWhere((item) => item.episodeId == episodeId);
    if (episodeIndex < 0) {
      throw StateError('小说章节不存在');
    }
    final episode = episodes[episodeIndex];
    final content = await _repository.getChapterContent(episodeId: episodeId);
    if (content == null) {
      throw StateError('小说章节正文不存在');
    }

    final novelDir = await _storageService.prepareNovelDirectory(
      novelId: detail.novelId,
      title: detail.title,
    );
    await _copyCoverIfPossible(detail: detail, novelDir: novelDir);

    final imageEntries = await _copyInlineImages();

    final chapterFileName = _storageService.numberedFileName(
      index: episodeIndex,
      title: episode.episodeTitle,
      extension: '.json',
    );
    final relativeChapterPath = p.posix.join('chapters', chapterFileName);
    final chapterFile = io.File(p.join(novelDir.path, 'chapters', chapterFileName));
    await _storageService.writeJsonAtomically(
      chapterFile,
      <String, Object?>{
        'episodeId': episode.episodeId,
        'sourceTid': episode.sourceTid,
        'sourcePid': episode.sourcePid,
        'sourcePage': episode.sourcePage,
        'title': episode.episodeTitle,
        'orderIndex': episode.orderIndex,
        'rawHtml': content.rawHtml,
        'plainText': content.plainText,
        'paragraphs': content.paragraphs,
        'images': imageEntries.map((item) => item.toJson()).toList(growable: false),
      },
    );

    await _writeMeta(
      detail: detail,
      episodes: episodes,
      downloaded: _NovelDownloadedChapterDraft(
        episode: episode,
        file: relativeChapterPath,
      ),
      novelDir: novelDir,
    );

    return DownloadedNovelChapter(
      novelId: novelId,
      episodeId: episodeId,
      chapterPath: chapterFile.path,
    );
  }

  @override
  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  }) async {
    final detail = await _repository.getDetail(novelId: novelId);
    if (detail == null) {
      return;
    }
    final downloaded = await _storageService.findDownloadedNovelChapter(
      novelId: novelId,
      title: detail.title,
      episodeId: episodeId,
    );
    if (downloaded != null) {
      final file = io.File(downloaded.chapterPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _removeChapterFromMeta(detail: detail, episodeId: episodeId);
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    final detail = await _repository.getDetail(novelId: novelId);
    if (detail == null) {
      return null;
    }
    final downloaded = await _storageService.findDownloadedNovelChapter(
      novelId: novelId,
      title: detail.title,
      episodeId: episodeId,
    );
    if (downloaded == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(await io.File(downloaded.chapterPath).readAsString(encoding: utf8));
      if (decoded is! Map) {
        return null;
      }
      final paragraphs = (decoded['paragraphs'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[];
      return NovelChapterContent(
        episodeId: episodeId,
        rawHtml: decoded['rawHtml']?.toString() ?? '',
        plainText: decoded['plainText']?.toString() ?? '',
        paragraphs: paragraphs,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NovelItem> _requireDetail(String novelId) async {
    final detail = await _repository.getDetail(novelId: novelId);
    if (detail == null) {
      throw StateError('小说不存在或已删除');
    }
    return detail;
  }

  Future<List<DownloadedNovelChapterImage>> _copyInlineImages() async {
    // 当前 SQLite 正文表未持久化章节插图 URL 列。下载结构先保留 images
    // 字段与目录，后续在正文缓存扩展 imageUrls 时可无缝填充本方法。
    return const <DownloadedNovelChapterImage>[];
  }

  Future<void> _copyCoverIfPossible({
    required NovelItem detail,
    required io.Directory novelDir,
  }) async {
    final target = io.File(p.join(novelDir.path, 'cover.jpg'));
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
    final cacheService = _imageCacheService;
    if (coverUrl == null || coverUrl.isEmpty || cacheService == null) {
      return;
    }
    final result = await cacheService.ensureCached(
      ImageCacheRequest(
        cacheKey: ImageCacheKeys.novelCover(detail.novelId),
        sourceUrl: coverUrl,
        ownerType: ImageCacheOwnerType.novel,
        ownerId: detail.novelId,
        role: ImageCacheRole.cover,
        protected: true,
      ),
    );
    final path = result.localPath;
    if (result.success && path != null && await io.File(path).exists()) {
      await io.File(path).copy(target.path);
    }
  }

  Future<void> _writeMeta({
    required NovelItem detail,
    required List<NovelEpisodeItem> episodes,
    required _NovelDownloadedChapterDraft downloaded,
    required io.Directory novelDir,
  }) async {
    final existing = await _readMeta(novelDir);
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
      for (final episode in episodes)
        if (oldByEpisodeId.containsKey(episode.episodeId)) oldByEpisodeId[episode.episodeId]!,
    ];

    await _storageService.writeJsonAtomically(
      io.File(p.join(novelDir.path, 'meta.json')),
      <String, Object?>{
        'schemaVersion': 1,
        'contentType': 'novel',
        'workId': detail.novelId,
        'sourceTid': detail.sourceTid,
        'sourceFid': detail.sourceFid,
        'sourceTypeId': detail.sourceTypeId,
        'sourceTagName': detail.sourceTagName,
        'title': detail.title,
        'author': detail.author,
        'intro': existing?['intro'],
        'coverFile': await io.File(p.join(novelDir.path, 'cover.jpg')).exists() ? 'cover.jpg' : null,
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
    required NovelItem detail,
    required String episodeId,
  }) async {
    final novelDir = await _storageService.prepareNovelDirectory(
      novelId: detail.novelId,
      title: detail.title,
    );
    final existing = await _readMeta(novelDir);
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
      io.File(p.join(novelDir.path, 'meta.json')),
      <String, Object?>{
        ...existing,
        'chapters': chapters,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
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

  String? _firstExistingPath(List<String?> paths) {
    for (final path in paths) {
      final trimmed = path?.trim();
      if (trimmed != null && trimmed.isNotEmpty && io.File(trimmed).existsSync()) {
        return trimmed;
      }
    }
    return null;
  }
}

class _NovelDownloadedChapterDraft {
  const _NovelDownloadedChapterDraft({
    required this.episode,
    required this.file,
  });

  final NovelEpisodeItem episode;
  final String file;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'episodeId': episode.episodeId,
      'sourcePid': episode.sourcePid,
      'title': episode.episodeTitle,
      'orderIndex': episode.orderIndex,
      'file': file,
    };
  }
}
