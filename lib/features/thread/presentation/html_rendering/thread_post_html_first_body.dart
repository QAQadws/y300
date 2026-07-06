import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_continuous_image_adapter.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

typedef ThreadPostHtmlFirstImageFallback =
    void Function(ThreadPost post, ForumHtmlImageRequest request);

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
    this.fallback,
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
  final Widget? fallback;

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
      return KeyedSubtree(
        key: Key('thread-post-html-first-body-${post.pid}'),
        child: ForumHtmlWidgetPostRenderer(
          html: html,
          sourceId: 'thread-$threadId-post-${post.pid}',
          threadId: threadId,
          imageHeaderBuilder: imageHeaderBuilder,
          imageCacheOwnerId: threadId,
          preferences: preferences,
          callbacks: ForumHtmlRenderCallbacks(
            onTapUrl: (url) {
              onOpenPostLink(url);
              return true;
            },
            onTapImage: _handleTapImage,
          ),
        ),
      );
    } catch (_) {
      return fallback ?? const SizedBox.shrink();
    }
  }

  void _handleTapImage(ForumHtmlImageRequest request) {
    if (request.isSticker) {
      return;
    }
    final images = plan.images;
    if (images.isEmpty) {
      onImageFallback?.call(post, request);
      return;
    }
    final resolved = _matchImage(request, images);
    if (resolved == null) {
      onImageFallback?.call(post, request);
      return;
    }
    final initialIndex = images.indexOf(resolved);
    final imageOpenHandler = onOpenPostImage;
    if (imageOpenHandler == null) {
      onImageFallback?.call(post, request);
      return;
    }
    imageOpenHandler(
      post,
      ThreadPostImageOpenRequest(
        document: plan.document,
        images: images,
        image: resolved,
        initialIndex: initialIndex < 0 ? resolved.index : initialIndex,
        readerRequest: _readerRequest(
          images: images,
          initialIndex: initialIndex < 0 ? resolved.index : initialIndex,
        ),
      ),
    );
  }

  ThreadPostImageBlock? _matchImage(
    ForumHtmlImageRequest request,
    List<ThreadPostImageBlock> images,
  ) {
    final attachmentId = request.attachmentId?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      for (final image in images) {
        if (image.aid?.trim() == attachmentId) {
          return image;
        }
      }
    }
    final requestUrl = _normalizeUrlForMatch(request.url);
    for (final image in images) {
      if (_normalizeUrlForMatch(image.url) == requestUrl ||
          _normalizeUrlForMatch(image.rawUrl) == requestUrl) {
        return image;
      }
    }
    return null;
  }

  ThreadImageOpenRequest _readerRequest({
    required List<ThreadPostImageBlock> images,
    required int initialIndex,
  }) {
    final entries = images
        .map((image) {
          return ThreadPostImageEntry(
            url: image.url,
            rawUrl: image.rawUrl,
            indexInPost: image.index,
            cacheKey: ForumImageCacheRequests.threadInline(
              tid: threadId,
              url: image.url,
              imageIndex: image.index,
            ).cacheKey,
            aid: image.aid,
            layoutHint: plan.resourceLayoutHints.blockImage(image),
          );
        })
        .toList(growable: false);
    final request = ThreadImageOpenRequest(
      tid: threadId,
      pid: post.pid,
      postNumber: post.number,
      referer: imageReferer,
      group: ThreadPostImageGroup(
        tid: threadId,
        pid: post.pid,
        postNumber: post.number,
        entries: entries,
      ),
      initialIndex: initialIndex,
    );
    return ThreadImageOpenRequest(
      tid: request.tid,
      pid: request.pid,
      postNumber: request.postNumber,
      referer: request.referer,
      group: request.group,
      initialIndex: request.initialIndex,
      continuousImages: const ThreadImageReaderContinuousImageAdapter()
          .mapRequest(request),
    );
  }

  String _normalizeUrlForMatch(String value) {
    final trimmed = value.trim();
    final resolved = ForumHtmlWidgetPostRenderer.forumBaseUri.resolve(trimmed);
    return resolved.removeFragment().toString();
  }
}
