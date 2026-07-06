import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_first_image_diagnostics_service.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ThreadPostHtmlFirstComparisonPage extends StatefulWidget {
  const ThreadPostHtmlFirstComparisonPage({
    super.key,
    required this.post,
    required this.threadId,
    required this.imageReferer,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
  });

  final ThreadPost post;
  final String threadId;
  final String imageReferer;
  final ThreadPostBodyRenderPlan plan;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)
  onOpenPostImage;

  @override
  State<ThreadPostHtmlFirstComparisonPage> createState() =>
      _ThreadPostHtmlFirstComparisonPageState();
}

class _ThreadPostHtmlFirstComparisonPageState
    extends State<ThreadPostHtmlFirstComparisonPage> {
  String _lastImageTapStatus = '尚未点击 HTML-first 图片';
  ThreadHtmlImageReaderBridgeResult? _lastBridgeResult;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const Key('thread-post-html-first-comparison-page'),
        backgroundColor: palette.background,
        appBar: AppBar(
          title: Text('${widget.post.number}# HTML-first 对照'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '旧渲染'),
              Tab(text: 'HTML-first'),
              Tab(text: '调试信息'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ComparisonPane(
              palette: palette,
              child: _legacyBody(createSelectionArea: true),
            ),
            _ComparisonPane(
              palette: palette,
              child: ThreadPostHtmlFirstBody(
                post: widget.post,
                threadId: widget.threadId,
                imageReferer: widget.imageReferer,
                plan: widget.plan,
                imageHeaderBuilder: widget.imageHeaderBuilder,
                onOpenPostLink: widget.onOpenPostLink,
                onOpenPostImage: widget.onOpenPostImage,
                onImageDiagnostics: (post, request, result) {
                  setState(() {
                    _lastBridgeResult = result;
                    if (result.canOpen) {
                      final index = request.readableIndex;
                      final via = index == null
                          ? 'aid/url fallback'
                          : 'readableIndex=$index';
                      _lastImageTapStatus =
                          '匹配图片：index=${result.request!.initialIndex}，$via';
                    } else if (request.isSticker) {
                      _lastImageTapStatus = '表情不进入阅读器';
                    } else {
                      _lastImageTapStatus = '未匹配图片：${request.url}';
                    }
                  });
                },
                onImageFallback: (post, request) {
                  setState(() {
                    _lastImageTapStatus = '未匹配图片：${request.url}';
                  });
                },
              ),
            ),
            _DebugPane(
              key: const Key('thread-post-html-first-debug-summary'),
              post: widget.post,
              threadId: widget.threadId,
              plan: widget.plan,
              fallbackWouldRender: widget.post.message.trim().isEmpty,
              lastImageTapStatus: _lastImageTapStatus,
              lastBridgeResult: _lastBridgeResult,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legacyBody({required bool createSelectionArea}) {
    return ThreadPostBodyView(
      document: widget.plan.document,
      blocks: widget.plan.displayDocument.blocks,
      images: widget.plan.images,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      imageCacheOwnerId: widget.threadId,
      imageOpenContext: ThreadImageOpenContext(
        tid: widget.threadId,
        pid: widget.post.pid,
        postNumber: widget.post.number,
        referer: widget.imageReferer,
        cacheKeyForImage: (image) {
          return ForumImageCacheRequests.threadInline(
            tid: widget.threadId,
            url: image.url,
            imageIndex: image.index,
          ).cacheKey;
        },
      ),
      resourceLayoutHints: widget.plan.resourceLayoutHints,
      selectionEnabled: true,
      createSelectionArea: createSelectionArea,
      onOpenLink: widget.onOpenPostLink,
      onOpenImage: (request) => widget.onOpenPostImage(widget.post, request),
    );
  }
}

class _ComparisonPane extends StatelessWidget {
  const _ComparisonPane({required this.palette, required this.child});

  final ThreadDetailNativePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(12),
            boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
          ),
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.bodyText,
              height: 1.5,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _DebugPane extends StatelessWidget {
  const _DebugPane({
    super.key,
    required this.post,
    required this.threadId,
    required this.plan,
    required this.fallbackWouldRender,
    required this.lastImageTapStatus,
    required this.lastBridgeResult,
  });

  final ThreadPost post;
  final String threadId;
  final ThreadPostBodyRenderPlan plan;
  final bool fallbackWouldRender;
  final String lastImageTapStatus;
  final ThreadHtmlImageReaderBridgeResult? lastBridgeResult;

  @override
  Widget build(BuildContext context) {
    final html = post.message;
    final prepared = const DefaultForumHtmlRenderPreparer().prepare(
      html: html,
      preferences: ForumHtmlReaderPreferences.defaults(),
      sourceId: post.pid.trim().isEmpty ? 'post' : post.pid.trim(),
      threadId: threadId,
      imageCacheOwnerId: threadId,
    );
    final diagnostics = const ThreadHtmlFirstImageDiagnosticsService()
        .buildReport(
          post: post,
          legacyPlan: plan,
          preparedDocument: prepared,
          lastTapStatus: lastImageTapStatus,
          lastBridgeResult: lastBridgeResult,
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _DebugLine(label: 'pid', value: post.pid),
        _DebugLine(label: '楼层', value: '${post.number}#'),
        _DebugLine(label: 'HTML 长度', value: '${html.length}'),
        _DebugLine(
          key: const Key('thread-post-html-first-readable-sequence-summary'),
          label: 'HTML-first 可读图片',
          value:
              '${prepared.readableImageCount}，跳过表情 ${prepared.skippedStickerCount}，跳过非网络 ${prepared.skippedNonNetworkCount}',
        ),
        _DebugLine(
          key: const Key('thread-post-html-first-image-diagnostics-summary'),
          label: '图片诊断',
          value: diagnostics.summaryText,
        ),
        _DebugLine(label: '旧 plan 图片数', value: '${plan.images.length}'),
        _DebugLine(
          key: const Key('thread-post-html-first-image-sequence-diff'),
          label: '序列对照',
          value: diagnostics.sequenceDiffText,
        ),
        _DebugLine(
          label: '旧 plan block 数',
          value: '${plan.document.blocks.length}',
        ),
        _DebugLine(
          label: 'HTML-first fallback',
          value: fallbackWouldRender ? '是' : '否',
        ),
        _DebugLine(
          key: const Key('thread-post-html-first-image-reader-fallback'),
          label: '图片点击匹配',
          value: lastImageTapStatus,
        ),
        _DebugLine(
          key: const Key('thread-post-html-first-image-failure-breakdown'),
          label: '失败/降级',
          value: diagnostics.failureBreakdownText,
        ),
      ],
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
