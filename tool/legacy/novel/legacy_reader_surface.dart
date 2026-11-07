import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_comparison_surface.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_conversion_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_session_cache.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';

NovelReaderComparisonSurface createLegacyNovelReaderSurface() =>
    _LegacyReaderSurface();

final class _LegacyReaderSurface implements NovelReaderComparisonSurface {
  NovelReaderPaginationSessionCache? _cache;
  NovelReaderConversionPosition? _conversion;
  bool _closed = false;
  int _generation = 0;
  NovelReaderPaginationSessionCache get _activeCache {
    if (_closed) throw StateError('Legacy reader surface is closed');
    return _cache ??= NovelReaderPaginationSessionCache();
  }

  @override
  Widget buildPaged(WidgetRef ref, NovelReaderComparisonPagedRequest request) {
    final cache = _activeCache;
    final generation = _generation;
    if (_conversion?.chapter.episodeId != request.episode.episodeId ||
        _conversion?.rawHtml != request.rawHtml) {
      _conversion = null;
    }
    return NovelReaderHtmlPagedSurface(
      preparationService: ref.watch(novelReaderHtmlPreparationServiceProvider),
      paginationCache: cache.paginationCache,
      paginationMeasureCache: cache.measureCache,
      paginationBoundaryCache: cache.boundaryCache,
      preparedChapterCache: cache.preparedChapterCache,
      conversionPosition: _conversion,
      onConversionPositionChanged: (position) {
        if (!_closed && generation == _generation && request.isCurrent()) {
          _conversion = position;
        }
      },
      readingAuthorityIdentity: request.readingAuthorityIdentity,
      rawHtml: request.rawHtml,
      episode: request.episode,
      preferences: request.preferences,
      typography: request.typography,
      theme: request.theme,
      imageReferer: request.imageReferer,
      progressSnapshot: request.progressSnapshot,
      startsAtBeginning: request.startsAtBeginning,
      chromeInsets: request.chromeInsets,
      semanticDocument: request.semanticDocument,
      pageSeekRequest: request.pageSeekRequest,
      navigationController: request.navigationController,
      chapterEntryRequest: request.chapterEntryRequest,
      onChapterEntryApplied: request.onChapterEntryApplied,
      previousChapterTitle: request.previousChapterTitle,
      nextChapterTitle: request.nextChapterTitle,
      onTurnToAdjacentChapter: request.onTurnToAdjacentChapter,
      onContentReady: request.onContentReady,
      onContentTerminal: request.onContentTerminal,
      onLinkTap: request.onLinkTap,
      onOpenImage: request.onOpenImage,
      onImageFallback: request.onImageFallback,
      onContentInteraction: request.onContentInteraction,
      onChooseScrollMode: request.onChooseScrollMode,
      onPositionChanged: request.onPositionChanged,
      onImagesReadyChanged: request.onImagesReadyChanged,
      onScrollActivityChanged: request.onScrollActivityChanged,
      onNavigationUnavailable: request.onNavigationUnavailable,
    );
  }

  @override
  Widget buildFlow(WidgetRef ref, NovelReaderComparisonFlowRequest request) {
    clearPositionHint();
    final cache = _activeCache;
    return NovelReaderHtmlDocumentView(
      preparationService: ref.watch(novelReaderHtmlPreparationServiceProvider),
      preparedChapterCache: cache.preparedChapterCache,
      rawHtml: request.rawHtml,
      episode: request.episode,
      preferences: request.preferences,
      typography: request.typography,
      theme: request.theme,
      imageReferer: request.imageReferer,
      asSliver: request.asSliver,
      onLinkTap: request.onLinkTap,
      onOpenImage: request.onOpenImage,
      onImageFallback: request.onImageFallback,
      onContentInteraction: request.onContentInteraction,
      onContentReady: request.onContentReady,
      onContentTerminal: request.onContentTerminal,
      onImagesReadyChanged: request.onImagesReadyChanged,
      onRetry: request.onRetry,
    );
  }

  @override
  void clearPositionHint() {
    _generation++;
    _conversion = null;
  }

  @override
  void reset() {
    clearPositionHint();
    _cache?.dispose();
    _cache = null;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    reset();
  }
}
