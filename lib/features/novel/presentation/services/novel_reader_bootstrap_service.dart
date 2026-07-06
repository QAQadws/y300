import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/services/novel_download_service.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_shared_preferences_bridge.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

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

abstract interface class NovelReaderBootstrapService {
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  );
}

class DefaultNovelReaderBootstrapService
    implements NovelReaderBootstrapService {
  DefaultNovelReaderBootstrapService({
    required NovelRepository repository,
    required NovelDownloadService downloadService,
    required NovelReaderDocumentBuildService documentBuildService,
    NovelReaderProgressPolicy progressPolicy =
        const NovelReaderProgressPolicy(),
  }) : _repository = repository,
       _downloadService = downloadService,
       _documentBuildService = documentBuildService,
       _progressPolicy = progressPolicy;

  final NovelRepository _repository;
  final NovelDownloadService _downloadService;
  final NovelReaderDocumentBuildService _documentBuildService;
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

    final content =
        await _downloadService.getDownloadedChapterContent(
          novelId: context.novelId,
          episodeId: currentEpisode.episodeId,
        ) ??
        await _repository.getChapterContent(
          episodeId: currentEpisode.episodeId,
        );
    if (content == null) {
      throw StateError('章节内容不存在');
    }

    // Load preferences before building so traditional/simplified conversion is
    // applied to the document at build time (and re-applied on episode change).
    final persistedPreferences = await _repository.getReaderPreferences();
    final effectivePreferences = persistedPreferences.copyWith(
      flowMode: NovelReaderFlowMode.vertical,
    );
    final converter = resolveTextConverter(
      effectivePreferences.sharedConversionMode,
    );

    final document = await _documentBuildService.build(
      NovelReaderDocumentBuildRequest(
        episodeId: content.episodeId,
        rawHtml: content.rawHtml,
        fallbackParagraphs: content.paragraphs,
      ),
      converter: converter,
    );
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
      flowMode: effectivePreferences.flowMode,
      progress: restoredProgress,
    );

    return NovelReaderCriticalBootstrap(
      episodes: episodes,
      currentEpisode: currentEpisode,
      currentContent: content,
      document: document,
      persistedPreferences: persistedPreferences,
      effectivePreferences: effectivePreferences,
      readingProgress: readingProgress,
      progressSnapshot: progressSnapshot,
      currentOffset: progressSnapshot.scrollOffset,
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
}
