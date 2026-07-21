import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class NovelReaderHtmlDocumentView extends ConsumerStatefulWidget {
  const NovelReaderHtmlDocumentView({
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
    this.onContentReady,
    this.preferencesAdapter = const NovelHtmlReaderPreferencesAdapter(),
    this.preparer = const NovelHtmlChapterRenderPreparer(),
    this.preparationService,
    this.preparedChapterCache,
    this.imageReaderBridge = const NovelHtmlImageReaderBridge(),
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
  final VoidCallback? onContentReady;
  final NovelHtmlReaderPreferencesAdapter preferencesAdapter;
  final NovelHtmlChapterPreparer preparer;
  final NovelReaderHtmlPreparationService? preparationService;
  final NovelReaderPreparedChapterCache? preparedChapterCache;
  final NovelHtmlImageReaderBridge imageReaderBridge;

  @override
  ConsumerState<NovelReaderHtmlDocumentView> createState() =>
      _NovelReaderHtmlDocumentViewState();
}

class _NovelReaderHtmlDocumentViewState
    extends ConsumerState<NovelReaderHtmlDocumentView> {
  Future<NovelReaderPreparedChapter>? _future;
  Object? _signature;
  Object? _reportedReadySignature;
  NovelReaderPreparedChapterCache? _ownedPreparedCache;

  @override
  void initState() {
    super.initState();
    _ensureFuture();
  }

  @override
  void didUpdateWidget(covariant NovelReaderHtmlDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureFuture();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferencesAdapter.map(widget.preferences);
    return KeyedSubtree(
      key: const Key('novel-reader-html-document-view'),
      child: DefaultTextStyle.merge(
        style: widget.typography.body,
        child: FutureBuilder<NovelReaderPreparedChapter>(
          future: _future,
          builder: (context, snapshot) {
            final prepared = snapshot.data;
            if (prepared == null ||
                prepared.renderDocument.themeSignature !=
                    widget.theme.signature) {
              return const SizedBox(
                key: Key('novel-reader-html-loading'),
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            _scheduleContentReady();
            return ForumHtmlWidgetPostRenderer(
              key: const Key('novel-reader-html-renderer'),
              html: prepared.html,
              theme: widget.theme,
              preparedDocument: prepared.renderDocument,
              preferences: preferences,
              sourceId: widget.episode.episodeId,
              threadId: widget.episode.sourceTid,
              imageHeaderBuilder: widget.imageHeaderBuilder,
              imageCacheOwnerId: widget.episode.sourceTid,
              callbacks: ForumHtmlRenderCallbacks(
                onTapUrl: (url) {
                  widget.onLinkTap?.call(NovelReaderLink(url: url, text: url));
                  return true;
                },
                onTapImage: (request) => _handleImageTap(
                  request: request,
                  sequence: prepared.renderDocument.sequence,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _ensureFuture() {
    final preferences = widget.preferencesAdapter.map(widget.preferences);
    final signature = (
      rawHtml: widget.rawHtml,
      episodeId: widget.episode.episodeId,
      sourceTid: widget.episode.sourceTid,
      preferences: preferences,
      themeSignature: widget.theme.signature,
      preparationService: widget.preparationService,
      preparer: widget.preparer,
    );
    if (_signature == signature) {
      return;
    }
    _signature = signature;
    final preparationService = NovelReaderCachingHtmlPreparationService(
      delegate:
          widget.preparationService ??
          DefaultNovelReaderHtmlPreparationService(preparer: widget.preparer),
      cache:
          widget.preparedChapterCache ??
          (_ownedPreparedCache ??= NovelReaderPreparedChapterCache()),
    );
    _future = preparationService.prepare(
      rawHtml: widget.rawHtml,
      episode: widget.episode,
      preferences: preferences,
      theme: widget.theme,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageCacheOwnerId: widget.episode.sourceTid,
    );
  }

  void _scheduleContentReady() {
    final signature = _signature;
    if (signature == null || _reportedReadySignature == signature) {
      return;
    }
    _reportedReadySignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _signature == signature) {
        widget.onContentReady?.call();
      }
    });
  }

  void _handleImageTap({
    required ForumHtmlImageRequest request,
    required ForumHtmlReadableImageSequence sequence,
  }) {
    final openRequest = widget.imageReaderBridge.buildOpenRequest(
      threadId: widget.episode.sourceTid,
      episodeId: widget.episode.episodeId,
      postNumber: widget.episode.orderIndex + 1,
      imageReferer: widget.imageReferer,
      sequence: sequence,
      imageRequest: request,
    );
    if (openRequest != null) {
      widget.onOpenImage?.call(openRequest);
      return;
    }
    if (!request.isSticker) {
      widget.onImageFallback?.call(request);
    }
  }
}
