import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

typedef ThreadPostHtmlFirstImageFallback =
    void Function(ThreadPost post, ForumHtmlImageRequest request);
typedef ThreadPostHtmlFirstImageDiagnostics =
    void Function(
      ThreadPost post,
      ForumHtmlImageRequest request,
      ThreadHtmlImageReaderBridgeResult result,
    );

class ThreadPostHtmlFirstBody extends ConsumerWidget {
  const ThreadPostHtmlFirstBody({
    super.key,
    required this.post,
    required this.threadId,
    required this.imageReferer,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    this.onImageFallback,
    this.onImageDiagnostics,
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
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
  final Widget? fallback;
  final ForumHtmlRenderPreparer renderPreparer;
  final ThreadHtmlImageReaderBridge imageReaderBridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final html = post.message.trim();
    if (html.isEmpty) {
      return fallback ?? const SizedBox.shrink();
    }
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    try {
      final sourceId = post.pid.trim().isEmpty ? 'post' : post.pid.trim();
      final preparedDocument = renderPreparer.prepare(
        html: html,
        preferences: preferences,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: threadId,
      );
      return KeyedSubtree(
        key: Key('thread-post-html-first-body-${post.pid}'),
        child: ForumHtmlWidgetPostRenderer(
          html: html,
          preparedDocument: preparedDocument,
          sourceId: sourceId,
          threadId: threadId,
          imageHeaderBuilder: imageHeaderBuilder,
          imageCacheOwnerId: threadId,
          preferences: preferences,
          callbacks: ForumHtmlRenderCallbacks(
            onTapUrl: (url) {
              onOpenPostLink(url);
              return true;
            },
            onTapImage: (request) =>
                _handleTapImage(request, preparedDocument.sequence),
          ),
        ),
      );
    } catch (_) {
      return fallback ?? const ThreadPostHtmlBodyError();
    }
  }

  void _handleTapImage(
    ForumHtmlImageRequest request,
    ForumHtmlReadableImageSequence sequence,
  ) {
    final result = imageReaderBridge.buildOpenRequest(
      post: post,
      threadId: threadId,
      imageReferer: imageReferer,
      legacyPlan: plan,
      sequence: sequence,
      imageRequest: request,
    );
    onImageDiagnostics?.call(post, request, result);
    final openRequest = result.request;
    if (openRequest == null) {
      if (!request.isSticker) {
        onImageFallback?.call(post, request);
      }
      return;
    }
    final imageOpenHandler = onOpenPostImage;
    if (imageOpenHandler == null) {
      onImageFallback?.call(post, request);
      return;
    }
    imageOpenHandler(post, openRequest);
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
    this.onImageFallback,
    this.onImageDiagnostics,
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
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
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
      onImageFallback: onImageFallback,
      onImageDiagnostics: onImageDiagnostics,
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
