import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

typedef NovelReaderPaginationCoordinatorBuilder =
    NovelReaderPaginationCoordinator Function({
      required BuildContext context,
      required ForumHtmlThemeContext theme,
      required ForumHtmlReaderPreferences preferences,
      required String sourceId,
      required String? threadId,
      required String? imageCacheOwnerId,
      required ImageRequestHeaderBuilder? imageHeaderBuilder,
    });

class NovelReaderHtmlPagedSurface extends StatefulWidget {
  const NovelReaderHtmlPagedSurface({
    super.key,
    required this.rawHtml,
    required this.episode,
    required this.preferences,
    required this.typography,
    required this.theme,
    required this.imageReferer,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
    this.onFallbackToVertical,
    this.onPageChanged,
    this.preferencesAdapter = const NovelHtmlReaderPreferencesAdapter(),
    this.preparer = const NovelHtmlChapterRenderPreparer(),
    this.preparationService,
    this.imageReaderBridge = const NovelHtmlImageReaderBridge(),
    this.coordinatorBuilder,
    this.bottomChromeReserveFraction = 0.18,
  });

  final String rawHtml;
  final NovelEpisodeItem episode;
  final NovelReaderPreferences preferences;
  final NovelReaderTypography typography;
  final ForumHtmlThemeContext theme;
  final String imageReferer;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final VoidCallback? onFallbackToVertical;
  final ValueChanged<int>? onPageChanged;
  final NovelHtmlReaderPreferencesAdapter preferencesAdapter;
  final NovelHtmlChapterPreparer preparer;
  final NovelReaderHtmlPreparationService? preparationService;
  final NovelHtmlImageReaderBridge imageReaderBridge;
  final NovelReaderPaginationCoordinatorBuilder? coordinatorBuilder;
  final double bottomChromeReserveFraction;

  @override
  State<NovelReaderHtmlPagedSurface> createState() =>
      _NovelReaderHtmlPagedSurfaceState();
}

class _NovelReaderHtmlPagedSurfaceState
    extends State<NovelReaderHtmlPagedSurface> {
  Future<NovelReaderPreparedChapter>? _prepareFuture;
  Object? _prepareSignature;
  NovelReaderPaginationCoordinator? _coordinator;
  Object? _coordinatorSignature;
  Future<NovelReaderPaginationPlan>? _planFuture;
  NovelReaderPaginationKey? _planKey;

  @override
  void initState() {
    super.initState();
    _ensurePreparationFuture();
  }

  @override
  void didUpdateWidget(covariant NovelReaderHtmlPagedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensurePreparationFuture();
  }

  @override
  Widget build(BuildContext context) {
    final htmlPreferences = widget.preferencesAdapter.map(widget.preferences);
    return DefaultTextStyle.merge(
      style: widget.typography.body,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pagePadding = widget.preferences.pagePadding
              .clamp(0.0, 96.0)
              .toDouble();
          final bottomChromeReserve =
              constraints.maxHeight *
              widget.bottomChromeReserveFraction.clamp(0.0, 0.35).toDouble();
          final availableWidth = constraints.maxWidth - pagePadding * 2;
          final availableHeight =
              constraints.maxHeight - pagePadding * 2 - bottomChromeReserve;
          final contentMaxWidth = widget.typography.contentMaxWidth < 160
              ? 160
              : widget.typography.contentMaxWidth;
          final pageWidth = math
              .min(availableWidth, contentMaxWidth)
              .toDouble();
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              pageWidth <= 0 ||
              availableHeight <= 0) {
            return const _NovelReaderPaginationStateView(
              key: Key('novel-reader-paged-invalid-viewport'),
              icon: Icons.crop_free,
              message: '当前窗口无法生成分页布局',
            );
          }

          return FutureBuilder<NovelReaderPreparedChapter>(
            future: _prepareFuture,
            builder: (context, snapshot) {
              final prepared = snapshot.data;
              if (prepared == null) {
                if (snapshot.hasError) {
                  return _NovelReaderPaginationFailureView(
                    error: snapshot.error!,
                    onRetry: _retryPreparation,
                    onFallbackToVertical: widget.onFallbackToVertical,
                  );
                }
                return const _NovelReaderPaginationStateView(
                  key: Key('novel-reader-paged-preparing'),
                  icon: Icons.menu_book_outlined,
                  message: '正在准备分页正文',
                  showProgress: true,
                );
              }

              final key = NovelReaderPaginationKey(
                episodeId: prepared.episodeId,
                contentHash: prepared.contentHash,
                viewportWidthPx: NovelReaderPaginationKey.logicalPixels(
                  pageWidth,
                ),
                viewportHeightPx: NovelReaderPaginationKey.logicalPixels(
                  availableHeight,
                ),
                typographySignature: _typographySignature(
                  widget.preferences,
                  widget.typography,
                  htmlPreferences,
                ),
                themeSignature: widget.theme.signature,
                imageDimensionRevision: prepared.imageDimensionRevision,
                rendererRevision: 1,
              );
              final planFuture = _ensurePlanFuture(
                context: context,
                prepared: prepared,
                key: key,
                htmlPreferences: htmlPreferences,
              );
              return FutureBuilder<NovelReaderPaginationPlan>(
                future: planFuture,
                builder: (context, planSnapshot) {
                  final plan = planSnapshot.data;
                  if (plan == null) {
                    if (planSnapshot.hasError) {
                      return _NovelReaderPaginationFailureView(
                        error: planSnapshot.error!,
                        onRetry: _retryPlan,
                        onFallbackToVertical: widget.onFallbackToVertical,
                      );
                    }
                    return const _NovelReaderPaginationStateView(
                      key: Key('novel-reader-paged-layout-loading'),
                      icon: Icons.view_agenda_outlined,
                      message: '正在计算分页布局',
                      showProgress: true,
                    );
                  }
                  if (plan.pages.isEmpty) {
                    return const _NovelReaderPaginationStateView(
                      key: Key('novel-reader-paged-empty'),
                      icon: Icons.article_outlined,
                      message: '本章没有可显示的正文',
                    );
                  }
                  return Padding(
                    key: const Key('novel-reader-paged-surface'),
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      pagePadding,
                      pagePadding,
                      pagePadding + bottomChromeReserve,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: pageWidth,
                        height: availableHeight,
                        child: _NovelReaderPagedPageView(
                          key: ValueKey<String>(plan.key.cacheIdentity),
                          plan: plan,
                          reverse:
                              widget.preferences.flowMode ==
                              NovelReaderFlowMode.pagedRtl,
                          showProgressIndicator:
                              widget.preferences.showProgressIndicator,
                          theme: widget.theme,
                          htmlPreferences: htmlPreferences,
                          typography: widget.typography,
                          renderDocument: prepared.renderDocument,
                          episode: widget.episode,
                          imageReferer: widget.imageReferer,
                          imageHeaderBuilder: widget.imageHeaderBuilder,
                          onLinkTap: widget.onLinkTap,
                          onOpenImage: widget.onOpenImage,
                          onImageFallback: widget.onImageFallback,
                          imageReaderBridge: widget.imageReaderBridge,
                          onPageChanged: widget.onPageChanged,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<NovelReaderPaginationPlan> _ensurePlanFuture({
    required BuildContext context,
    required NovelReaderPreparedChapter prepared,
    required NovelReaderPaginationKey key,
    required ForumHtmlReaderPreferences htmlPreferences,
  }) {
    if (_planKey == key && _planFuture != null) {
      return _planFuture!;
    }
    final coordinatorSignature = (
      theme: widget.theme.signature,
      preferences: htmlPreferences,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageOwner: widget.episode.sourceTid,
      headerBuilder: widget.imageHeaderBuilder,
      builder: widget.coordinatorBuilder,
    );
    if (_coordinator == null || _coordinatorSignature != coordinatorSignature) {
      _coordinatorSignature = coordinatorSignature;
      _coordinator =
          widget.coordinatorBuilder?.call(
            context: context,
            theme: widget.theme,
            preferences: htmlPreferences,
            sourceId: widget.episode.episodeId,
            threadId: widget.episode.sourceTid,
            imageCacheOwnerId: widget.episode.sourceTid,
            imageHeaderBuilder: widget.imageHeaderBuilder,
          ) ??
          _defaultCoordinator(
            context: context,
            htmlPreferences: htmlPreferences,
          );
    }
    _planKey = key;
    _planFuture = _coordinator!.paginate(chapter: prepared, key: key);
    return _planFuture!;
  }

  NovelReaderPaginationCoordinator _defaultCoordinator({
    required BuildContext context,
    required ForumHtmlReaderPreferences htmlPreferences,
  }) {
    return DefaultNovelReaderPaginationCoordinator(
      pageBreaker: NovelReaderHtmlPageBreaker(
        measureAdapter: NovelReaderHtmlPaginationMeasureAdapter(
          hostContext: context,
          theme: widget.theme,
          preferences: htmlPreferences,
          sourceId: widget.episode.episodeId,
          threadId: widget.episode.sourceTid,
          imageCacheOwnerId: widget.episode.sourceTid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
        ),
      ),
      cache: NovelReaderPaginationCache(),
    );
  }

  void _ensurePreparationFuture() {
    final htmlPreferences = widget.preferencesAdapter.map(widget.preferences);
    final signature = (
      rawHtml: widget.rawHtml,
      episodeId: widget.episode.episodeId,
      sourceTid: widget.episode.sourceTid,
      preferences: htmlPreferences,
      themeSignature: widget.theme.signature,
      preparationService: widget.preparationService,
      preparer: widget.preparer,
    );
    if (_prepareSignature == signature) {
      return;
    }
    _prepareSignature = signature;
    _prepareFuture =
        (widget.preparationService ??
                DefaultNovelReaderHtmlPreparationService(
                  preparer: widget.preparer,
                ))
            .prepare(
              rawHtml: widget.rawHtml,
              episode: widget.episode,
              preferences: htmlPreferences,
              theme: widget.theme,
              sourceId: widget.episode.episodeId,
              threadId: widget.episode.sourceTid,
              imageCacheOwnerId: widget.episode.sourceTid,
            );
    _coordinator = null;
    _coordinatorSignature = null;
    _planFuture = null;
    _planKey = null;
  }

  String _typographySignature(
    NovelReaderPreferences preferences,
    NovelReaderTypography typography,
    ForumHtmlReaderPreferences htmlPreferences,
  ) {
    return jsonEncode(<Object?>[
      preferences.fontSize,
      preferences.lineHeight,
      preferences.paragraphSpacing,
      preferences.pagePadding,
      preferences.fontFamily,
      preferences.contentMaxWidth,
      preferences.firstLineIndent,
      preferences.fontWeight,
      preferences.textAlign.name,
      htmlPreferences.typography.fontScale,
      htmlPreferences.typography.lineHeightScale,
      htmlPreferences.typography.paragraphSpacing,
      typography.textAlign.index,
    ]);
  }

  void _retryPreparation() {
    if (!mounted) {
      return;
    }
    setState(() {
      _prepareFuture = null;
      _prepareSignature = null;
      _planFuture = null;
      _planKey = null;
    });
  }

  void _retryPlan() {
    if (!mounted) {
      return;
    }
    setState(() {
      _planFuture = null;
      _planKey = null;
    });
  }
}

class _NovelReaderPagedPageView extends StatefulWidget {
  const _NovelReaderPagedPageView({
    super.key,
    required this.plan,
    required this.reverse,
    required this.showProgressIndicator,
    required this.theme,
    required this.htmlPreferences,
    required this.typography,
    required this.renderDocument,
    required this.episode,
    required this.imageReferer,
    required this.imageReaderBridge,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
    this.onPageChanged,
  });

  final NovelReaderPaginationPlan plan;
  final bool reverse;
  final bool showProgressIndicator;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences htmlPreferences;
  final NovelReaderTypography typography;
  final ForumHtmlPreparedRenderDocument renderDocument;
  final NovelEpisodeItem episode;
  final String imageReferer;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final NovelHtmlImageReaderBridge imageReaderBridge;
  final ValueChanged<int>? onPageChanged;

  @override
  State<_NovelReaderPagedPageView> createState() =>
      _NovelReaderPagedPageViewState();
}

class _NovelReaderPagedPageViewState extends State<_NovelReaderPagedPageView> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _reportedInitialPage = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, keepPage: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_reportedInitialPage && widget.plan.pageCount > 0) {
        _reportedInitialPage = true;
        widget.onPageChanged?.call(0);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.plan.pageCount;
    return Stack(
      key: const Key('novel-reader-paged-page-session'),
      fit: StackFit.expand,
      children: [
        PageView.builder(
          key: const Key('novel-reader-paged-page-view'),
          controller: _pageController,
          reverse: widget.reverse,
          itemCount: pageCount,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            final page = widget.plan.pages[index];
            return _NovelReaderPagedPage(
              page: page,
              plan: widget.plan,
              theme: widget.theme,
              htmlPreferences: widget.htmlPreferences,
              typography: widget.typography,
              renderDocument: widget.renderDocument,
              episode: widget.episode,
              imageReferer: widget.imageReferer,
              imageHeaderBuilder: widget.imageHeaderBuilder,
              onLinkTap: widget.onLinkTap,
              onOpenImage: widget.onOpenImage,
              onImageFallback: widget.onImageFallback,
              imageReaderBridge: widget.imageReaderBridge,
            );
          },
        ),
        if (widget.showProgressIndicator)
          Positioned(
            key: const Key('novel-reader-page-indicator'),
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.78),
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '${_currentPage + 1} / $pageCount',
                  key: const Key('novel-reader-page-indicator-text'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _onPageChanged(int index) {
    if (!mounted || index < 0 || index >= widget.plan.pageCount) {
      return;
    }
    setState(() {
      _currentPage = index;
    });
    widget.onPageChanged?.call(index);
  }
}

class _NovelReaderPagedPage extends StatelessWidget {
  const _NovelReaderPagedPage({
    required this.page,
    required this.plan,
    required this.theme,
    required this.htmlPreferences,
    required this.typography,
    required this.renderDocument,
    required this.episode,
    required this.imageReferer,
    required this.imageReaderBridge,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
  });

  final NovelReaderPageFragment page;
  final NovelReaderPaginationPlan plan;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences htmlPreferences;
  final NovelReaderTypography typography;
  final ForumHtmlPreparedRenderDocument renderDocument;
  final NovelEpisodeItem episode;
  final String imageReferer;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final NovelHtmlImageReaderBridge imageReaderBridge;

  @override
  Widget build(BuildContext context) {
    final preparedDocument = renderDocument.copyWith(preparedHtml: page.html);
    Widget child = ForumHtmlWidgetPostRenderer(
      key: ValueKey<int>(page.index),
      html: page.html,
      theme: theme,
      preparedDocument: preparedDocument,
      preferences: htmlPreferences,
      sourceId: episode.episodeId,
      threadId: episode.sourceTid,
      imageHeaderBuilder: imageHeaderBuilder,
      imageCacheOwnerId: episode.sourceTid,
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: (url) {
          onLinkTap?.call(NovelReaderLink(url: url, text: url));
          return true;
        },
        onTapImage: (request) => _handleImageTap(
          request: request,
          sequence: preparedDocument.sequence,
        ),
      ),
    );
    if (page.requiresInnerScroll) {
      child = SingleChildScrollView(
        key: ValueKey<int>(page.index),
        child: child,
      );
    }
    return Semantics(
      container: true,
      label: '第 ${page.index + 1} 页，共 ${plan.pageCount} 页',
      child: child,
    );
  }

  void _handleImageTap({
    required ForumHtmlImageRequest request,
    required ForumHtmlReadableImageSequence sequence,
  }) {
    final openRequest = imageReaderBridge.buildOpenRequest(
      threadId: episode.sourceTid,
      episodeId: episode.episodeId,
      postNumber: episode.orderIndex + 1,
      imageReferer: imageReferer,
      sequence: sequence,
      imageRequest: request,
    );
    if (openRequest != null) {
      onOpenImage?.call(openRequest);
      return;
    }
    if (!request.isSticker) {
      onImageFallback?.call(request);
    }
  }
}

class _NovelReaderPaginationStateView extends StatelessWidget {
  const _NovelReaderPaginationStateView({
    super.key,
    required this.icon,
    required this.message,
    this.showProgress = false,
  });

  final IconData icon;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        key: const Key('novel-reader-pagination-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 12),
          Text(message),
          if (showProgress) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _NovelReaderPaginationFailureView extends StatelessWidget {
  const _NovelReaderPaginationFailureView({
    required this.error,
    required this.onRetry,
    required this.onFallbackToVertical,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onFallbackToVertical;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        key: const Key('novel-reader-pagination-failure'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_outlined, size: 34),
          const SizedBox(height: 12),
          const Text('分页布局失败'),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('novel-reader-pagination-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              if (onFallbackToVertical != null)
                FilledButton.icon(
                  key: const Key('novel-reader-pagination-fallback'),
                  onPressed: onFallbackToVertical,
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: const Text('回到滚动'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
