import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

class NovelReaderLoadContext {
  const NovelReaderLoadContext({
    required this.novelId,
    required this.requestedEpisodeId,
    this.preservedProgress,
  });

  final String novelId;
  final String requestedEpisodeId;
  final NovelReadingProgress? preservedProgress;
}

class NovelReaderCriticalBootstrap {
  const NovelReaderCriticalBootstrap({
    required this.episodes,
    required this.currentEpisode,
    required this.currentContent,
    required this.document,
    required this.persistedPreferences,
    required this.effectivePreferences,
    required this.readingProgress,
    required this.progressSnapshot,
    required this.currentOffset,
  });

  final List<NovelEpisodeItem> episodes;
  final NovelEpisodeItem currentEpisode;
  final NovelChapterContent currentContent;
  final NovelReaderDocument document;
  final NovelReaderPreferences persistedPreferences;
  final NovelReaderPreferences effectivePreferences;
  final NovelReadingProgress? readingProgress;
  final NovelReaderProgressSnapshot progressSnapshot;
  final double currentOffset;
}

class NovelReaderSupplementalBootstrap {
  const NovelReaderSupplementalBootstrap({
    this.novel,
    this.bookmarks = const <NovelReaderBookmark>[],
    this.currentEpisodeBookmarks = const <NovelReaderBookmark>[],
    this.downloadedEpisodeIds = const <String>{},
  });

  final NovelItem? novel;
  final List<NovelReaderBookmark> bookmarks;
  final List<NovelReaderBookmark> currentEpisodeBookmarks;
  final Set<String> downloadedEpisodeIds;
}

abstract interface class NovelReaderBootstrapService {
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  );

  Future<NovelReaderSupplementalBootstrap> loadSupplemental(
    NovelReaderLoadContext context,
    NovelReaderCriticalBootstrap critical,
  );
}

class DefaultNovelReaderBootstrapService implements NovelReaderBootstrapService {
  DefaultNovelReaderBootstrapService({
    required NovelRepository repository,
    required NovelDownloadService downloadService,
    required NovelReaderDocumentParser documentParser,
    required NovelReaderCacheService cacheService,
    NovelReaderProgressPolicy progressPolicy = const NovelReaderProgressPolicy(),
  }) : _repository = repository,
       _downloadService = downloadService,
       _documentParser = documentParser,
       _cacheService = cacheService,
       _progressPolicy = progressPolicy;

  final NovelRepository _repository;
  final NovelDownloadService _downloadService;
  final NovelReaderDocumentParser _documentParser;
  final NovelReaderCacheService _cacheService;
  final NovelReaderProgressPolicy _progressPolicy;

  @override
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  ) async {
    final episodes = await _repository.getEpisodes(
      novelId: context.novelId,
      descending: false,
    );
    if (episodes.isEmpty) {
      throw StateError('小说章节目录为空');
    }
    final currentEpisode = episodes.firstWhere(
      (episode) => episode.episodeId == context.requestedEpisodeId,
      orElse: () => episodes.first,
    );

    final content = await _downloadService.getDownloadedChapterContent(
          novelId: context.novelId,
          episodeId: currentEpisode.episodeId,
        ) ??
        await _repository.getChapterContent(episodeId: currentEpisode.episodeId);
    if (content == null) {
      throw StateError('章节内容不存在');
    }

    final document = _documentParser.parse(
      episodeId: content.episodeId,
      rawHtml: content.rawHtml,
      fallbackParagraphs: content.paragraphs,
    );
    final persistedPreferences = await _repository.getReaderPreferences();
    final readingProgress = await _repository.getReadingProgress(
      novelId: context.novelId,
    );
    final restoredProgress = _progressForEpisode(
      episodeId: currentEpisode.episodeId,
      currentProgress: readingProgress,
      preservedProgress: context.preservedProgress,
    );
    final progressSnapshot = _progressPolicy.fromReadingProgress(
      novelId: context.novelId,
      episodeId: currentEpisode.episodeId,
      flowMode: persistedPreferences.flowMode,
      progress: restoredProgress,
    );

    return NovelReaderCriticalBootstrap(
      episodes: episodes,
      currentEpisode: currentEpisode,
      currentContent: content,
      document: document,
      persistedPreferences: persistedPreferences,
      effectivePreferences: persistedPreferences,
      readingProgress: readingProgress,
      progressSnapshot: progressSnapshot,
      currentOffset: progressSnapshot.scrollOffset,
    );
  }

  @override
  Future<NovelReaderSupplementalBootstrap> loadSupplemental(
    NovelReaderLoadContext context,
    NovelReaderCriticalBootstrap critical,
  ) async {
    NovelItem? novel;
    try {
      novel = await _repository.getDetail(novelId: context.novelId);
    } catch (_) {
      novel = null;
    }
    final bookmarks = await _repository.listReaderBookmarks(
      novelId: context.novelId,
    );
    final downloadedEpisodeIds = await _cacheService.getDownloadedEpisodeIds(
      novelId: context.novelId,
      episodeIds: critical.episodes.map((episode) => episode.episodeId),
    );
    return NovelReaderSupplementalBootstrap(
      novel: novel,
      bookmarks: bookmarks,
      currentEpisodeBookmarks: _bookmarksForEpisode(
        bookmarks,
        critical.currentEpisode.episodeId,
      ),
      downloadedEpisodeIds: downloadedEpisodeIds,
    );
  }

  NovelReadingProgress? _progressForEpisode({
    required String episodeId,
    required NovelReadingProgress? currentProgress,
    required NovelReadingProgress? preservedProgress,
  }) {
    if (currentProgress?.episodeId == episodeId) {
      return currentProgress;
    }
    if (preservedProgress?.episodeId == episodeId) {
      return preservedProgress;
    }
    return null;
  }

  List<NovelReaderBookmark> _bookmarksForEpisode(
    List<NovelReaderBookmark> bookmarks,
    String episodeId,
  ) {
    return bookmarks
        .where((bookmark) => bookmark.episodeId == episodeId)
        .toList(growable: false);
  }
}
