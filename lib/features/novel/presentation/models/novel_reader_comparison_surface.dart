import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_anchor_navigation_request.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';

/// Explicit development injection; production routes use the native surfaces.
/// A factory creates one owner per reader route, without owning UI or progress.
typedef NovelReaderComparisonSurfaceFactory =
    NovelReaderComparisonSurface Function();

abstract interface class NovelReaderComparisonSurface {
  // Ref is borrowed for this build only; implementations must not retain it.
  Widget buildPaged(WidgetRef ref, NovelReaderComparisonPagedRequest request);
  Widget buildFlow(WidgetRef ref, NovelReaderComparisonFlowRequest request);
  void clearPositionHint();
  void reset();
  void dispose();
}

final class NovelReaderComparisonPagedRequest {
  const NovelReaderComparisonPagedRequest({
    required this.readingAuthorityIdentity,
    required this.rawHtml,
    required this.episode,
    required this.preferences,
    required this.typography,
    required this.theme,
    required this.imageReferer,
    required this.progressSnapshot,
    required this.startsAtBeginning,
    required this.chromeInsets,
    required this.semanticDocument,
    required this.pageSeekRequest,
    required this.navigationController,
    required this.chapterEntryRequest,
    required this.onChapterEntryApplied,
    required this.previousChapterTitle,
    required this.nextChapterTitle,
    required this.onTurnToAdjacentChapter,
    required this.onContentReady,
    required this.onContentTerminal,
    required this.onLinkTap,
    required this.onOpenImage,
    required this.onImageFallback,
    required this.onContentInteraction,
    required this.onChooseScrollMode,
    required this.onPositionChanged,
    required this.onImagesReadyChanged,
    required this.onScrollActivityChanged,
    required this.onNavigationUnavailable,
    required this.isCurrent,
  });
  final Object? readingAuthorityIdentity;
  final String rawHtml;
  final NovelEpisodeItem episode;
  final NovelReaderPreferences preferences;
  final NovelReaderTypography typography;
  final ForumHtmlThemeContext theme;
  final String imageReferer;
  final NovelReaderProgressSnapshot progressSnapshot;
  final bool startsAtBeginning;
  final ReaderChromeInsets chromeInsets;
  final NovelReaderDocument? semanticDocument;
  final NovelReaderPageSeekRequest? pageSeekRequest;
  final NovelReaderPagedNavigationController? navigationController;
  final NovelReaderChapterEntryRequest? chapterEntryRequest;
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryApplied;
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnHandler? onTurnToAdjacentChapter;
  final VoidCallback? onContentReady;
  final VoidCallback? onContentTerminal;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final VoidCallback? onContentInteraction;
  final VoidCallback? onChooseScrollMode;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final ValueChanged<bool>? onImagesReadyChanged;
  final ValueChanged<bool>? onScrollActivityChanged;
  final ValueChanged<NovelReaderAnchorNavigationRequest>?
  onNavigationUnavailable;
  final bool Function() isCurrent;
}

final class NovelReaderComparisonFlowRequest {
  const NovelReaderComparisonFlowRequest({
    required this.rawHtml,
    required this.episode,
    required this.preferences,
    required this.typography,
    required this.theme,
    required this.imageReferer,
    required this.asSliver,
    required this.onLinkTap,
    required this.onOpenImage,
    required this.onImageFallback,
    required this.onContentInteraction,
    required this.onContentReady,
    required this.onContentTerminal,
    required this.onImagesReadyChanged,
    required this.onRetry,
  });
  final String rawHtml;
  final NovelEpisodeItem episode;
  final NovelReaderPreferences preferences;
  final NovelReaderTypography typography;
  final ForumHtmlThemeContext theme;
  final String imageReferer;
  final bool asSliver;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final VoidCallback? onContentInteraction;
  final VoidCallback? onContentReady;
  final VoidCallback? onContentTerminal;
  final ValueChanged<bool>? onImagesReadyChanged;
  final VoidCallback? onRetry;
}
