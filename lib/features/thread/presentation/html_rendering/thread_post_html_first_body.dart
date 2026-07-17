import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';

typedef ThreadPostHtmlFirstImageFallback =
    void Function(ThreadPost post, ForumHtmlImageRequest request);
typedef ThreadPostHtmlFirstImageDiagnostics =
    void Function(
      ThreadPost post,
      ForumHtmlImageRequest request,
      ThreadHtmlImageReaderBridgeResult result,
    );

class ThreadPostHtmlFirstBody extends ConsumerStatefulWidget {
  const ThreadPostHtmlFirstBody({
    super.key,
    required this.post,
    required this.threadId,
    required this.imageReferer,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    required this.theme,
    this.onImageFallback,
    this.onImageDiagnostics,
    this.onImageLayoutShift,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.fallback,
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
    this.imageReaderBridge = const ThreadHtmlImageReaderBridge(),
  });

  final ThreadPost post;
  final String threadId;
  final String imageReferer;
  final ThreadPostBodyRenderPlan plan;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImage;
  final ForumHtmlThemeContext theme;
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final Widget? fallback;
  final ForumHtmlRenderPreparer renderPreparer;
  final ThreadHtmlImageReaderBridge imageReaderBridge;

  @override
  ConsumerState<ThreadPostHtmlFirstBody> createState() =>
      _ThreadPostHtmlFirstBodyState();
}

class _ThreadPostHtmlFirstBodyState
    extends ConsumerState<ThreadPostHtmlFirstBody> {
  String? _conversionHtml;
  TextConversionMode? _conversionMode;
  Future<HtmlTextNodeConversionResult>? _conversionFuture;
  bool _loggedEmptyBody = false;
  String? _lastPreparedLogKey;
  String? _lastRenderFailureLogKey;

  @override
  Widget build(BuildContext context) {
    final html = widget.post.message.trim();
    if (html.isEmpty) {
      if (!_loggedEmptyBody) {
        _loggedEmptyBody = true;
        _logNative(
          'render_empty_body',
          'tid=${widget.threadId} pid=${widget.post.pid} '
              'postNo=${widget.post.number} authorId=${widget.post.authorId}',
        );
      }
      return widget.fallback ?? const SizedBox.shrink();
    }
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();

    if (preferences.conversionMode == TextConversionMode.none) {
      return _buildHtmlBody(html, preferences);
    }

    return FutureBuilder<HtmlTextNodeConversionResult>(
      future: _conversionFutureFor(html, preferences.conversionMode),
      builder: (context, snapshot) {
        final renderedHtml = snapshot.hasData ? snapshot.data!.html : html;
        return _buildHtmlBody(renderedHtml, preferences);
      },
    );
  }

  Future<HtmlTextNodeConversionResult> _conversionFutureFor(
    String html,
    TextConversionMode mode,
  ) {
    if (_conversionHtml != html ||
        _conversionMode != mode ||
        _conversionFuture == null) {
      _conversionHtml = html;
      _conversionMode = mode;
      final converter = ref.read(textConverterProvider(mode));
      _conversionFuture = ref
          .read(htmlTextNodeConversionServiceProvider)
          .convert(html: html, converter: converter);
    }
    return _conversionFuture!;
  }

  Widget _buildHtmlBody(String html, ForumHtmlReaderPreferences preferences) {
    try {
      final sourceId = widget.post.pid.trim().isEmpty
          ? 'post'
          : widget.post.pid.trim();
      final preparedDocument = widget.renderPreparer.prepare(
        html: html,
        preferences: preferences,
        theme: widget.theme,
        sourceId: sourceId,
        threadId: widget.threadId,
        imageCacheOwnerId: widget.threadId,
      );
      _logPreparedDocument(
        sourceId: sourceId,
        htmlLength: html.length,
        preparedDocument: preparedDocument,
      );
      return KeyedSubtree(
        key: Key('thread-post-html-first-body-${widget.post.pid}'),
        child: ForumHtmlWidgetPostRenderer(
          html: html,
          theme: widget.theme,
          preparedDocument: preparedDocument,
          sourceId: sourceId,
          threadId: widget.threadId,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          imageCacheOwnerId: widget.threadId,
          imageFallbackAspectRatioFor: widget.imageFallbackAspectRatioFor,
          onBlockImageResolved: widget.onBlockImageResolved,
          preferences: preferences,
          callbacks: ForumHtmlRenderCallbacks(
            onTapUrl: (url) {
              widget.onOpenPostLink(url);
              return true;
            },
            onTapImage: (request) =>
                _handleTapImage(request, preparedDocument.sequence),
            onImageLayoutShift: widget.onImageLayoutShift,
          ),
        ),
      );
    } catch (error, stackTrace) {
      _logRenderFailure(
        htmlLength: html.length,
        error: error,
        stackTrace: stackTrace,
      );
      return widget.fallback ?? const ThreadPostHtmlBodyError();
    }
  }

  void _logPreparedDocument({
    required String sourceId,
    required int htmlLength,
    required ForumHtmlPreparedRenderDocument preparedDocument,
  }) {
    if (!kDebugMode) {
      return;
    }
    final key = [
      sourceId,
      htmlLength,
      preparedDocument.preparedHtml.length,
      preparedDocument.sequence.entries.length,
      preparedDocument.totalImageCount,
    ].join(':');
    if (_lastPreparedLogKey == key) {
      return;
    }
    _lastPreparedLogKey = key;
    _logNative(
      'render_prepare_success',
      'tid=${widget.threadId} pid=${widget.post.pid} postNo=${widget.post.number} '
          'rawLength=$htmlLength preparedLength=${preparedDocument.preparedHtml.length} '
          'totalImages=${preparedDocument.totalImageCount} '
          'readableImages=${preparedDocument.sequence.entries.length} '
          'stickers=${preparedDocument.skippedStickerCount} '
          'nonNetwork=${preparedDocument.skippedNonNetworkCount} '
          'duplicates=${preparedDocument.duplicatedReadableUrlCount} '
          'attachments=${preparedDocument.attachmentTaggedCount}',
    );
  }

  void _logRenderFailure({
    required int htmlLength,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    final key = '${widget.post.pid}:$htmlLength:$error';
    if (_lastRenderFailureLogKey == key) {
      return;
    }
    _lastRenderFailureLogKey = key;
    _logNative(
      'render_failure',
      'tid=${widget.threadId} pid=${widget.post.pid} postNo=${widget.post.number} '
          'rawLength=$htmlLength error=${_oneLine(error.toString())} '
          'stack=${_stackHead(stackTrace)}',
    );
  }

  void _handleTapImage(
    ForumHtmlImageRequest request,
    ForumHtmlReadableImageSequence sequence,
  ) {
    final result = widget.imageReaderBridge.buildOpenRequest(
      post: widget.post,
      threadId: widget.threadId,
      imageReferer: widget.imageReferer,
      legacyPlan: widget.plan,
      sequence: sequence,
      imageRequest: request,
    );
    widget.onImageDiagnostics?.call(widget.post, request, result);
    final openRequest = result.request;
    if (openRequest == null) {
      if (!request.isSticker) {
        widget.onImageFallback?.call(widget.post, request);
      }
      return;
    }
    final imageOpenHandler = widget.onOpenPostImage;
    if (imageOpenHandler == null) {
      widget.onImageFallback?.call(widget.post, request);
      return;
    }
    imageOpenHandler(widget.post, openRequest);
  }

  void _logNative(String stage, String message) {
    debugPrint('[ThreadDetail][native][$stage] $message');
  }

  String _oneLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stackHead(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isEmpty) {
      return '-';
    }
    return _oneLine(text.split('\n').first);
  }
}

/// Production HTML-first thread body.
///
/// The legacy rich-document renderer is intentionally not used as a runtime
/// fallback here. Old rendering remains available from diagnostic comparison
/// surfaces, while the normal thread detail path either renders HTML-first or
/// shows a small recoverable error block.
class ThreadPostHtmlBody extends StatelessWidget {
  const ThreadPostHtmlBody({
    super.key,
    required this.post,
    required this.threadId,
    required this.imageReferer,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    required this.theme,
    this.onImageFallback,
    this.onImageDiagnostics,
    this.onImageLayoutShift,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
    this.imageReaderBridge = const ThreadHtmlImageReaderBridge(),
  });

  final ThreadPost post;
  final String threadId;
  final String imageReferer;
  final ThreadPostBodyRenderPlan plan;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImage;
  final ForumHtmlThemeContext theme;
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumHtmlRenderPreparer renderPreparer;
  final ThreadHtmlImageReaderBridge imageReaderBridge;

  @override
  Widget build(BuildContext context) {
    return ThreadPostHtmlFirstBody(
      post: post,
      threadId: threadId,
      imageReferer: imageReferer,
      plan: plan,
      imageHeaderBuilder: imageHeaderBuilder,
      onOpenPostLink: onOpenPostLink,
      onOpenPostImage: onOpenPostImage,
      theme: theme,
      onImageFallback: onImageFallback,
      onImageDiagnostics: onImageDiagnostics,
      onImageLayoutShift: onImageLayoutShift,
      imageFallbackAspectRatioFor: imageFallbackAspectRatioFor,
      onBlockImageResolved: onBlockImageResolved,
      renderPreparer: renderPreparer,
      imageReaderBridge: imageReaderBridge,
    );
  }
}

class ThreadPostHtmlBodyError extends StatelessWidget {
  const ThreadPostHtmlBodyError({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('thread-post-html-body-error'),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          '正文渲染失败，可长按楼层复制正文或打开原帖查看。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer),
        ),
      ),
    );
  }
}
