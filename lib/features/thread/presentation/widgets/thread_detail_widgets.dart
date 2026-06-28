import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/presentation/thread_detail_render_entries.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_store.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ThreadDetailContent extends StatefulWidget {
  const ThreadDetailContent({
    super.key,
    required this.state,
    this.scrollController,
    this.highlightPostPid,
    this.targetPid,
    required this.imageHeaderBuilder,
    required this.imageReferer,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onLoadPageNumber,
    required this.onOpenPostReply,
    required this.onOpenPostRate,
    required this.onOpenPostComment,
    required this.onOpenAuthorProfile,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    this.onOpenPostImages,
    required this.onOpenPostCopyActions,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    this.onPostBuilt,
    this.imageDimensionStore,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
  });

  final ThreadDetailPageState state;
  final ScrollController? scrollController;
  final String? highlightPostPid;
  final String? targetPid;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String imageReferer;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onLoadPageNumber;
  final ValueChanged<ThreadPost> onOpenPostReply;
  final ValueChanged<ThreadPost> onOpenPostRate;
  final ValueChanged<ThreadPost> onOpenPostComment;
  final ValueChanged<ThreadPost> onOpenAuthorProfile;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostCopyActions;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ValueChanged<int>? onPostBuilt;

  /// 持久化图片尺寸快照（来自缓存预热）。提供时 render plan 会用可信尺寸锁定
  /// 首帧高度，避免滚动中异步改高。为空则退化为既有行为。
  final ThreadPostImageDimensionStore? imageDimensionStore;
  final void Function(ThreadPoll poll, ThreadPollOption option)
  onTogglePollOption;
  final ValueChanged<ThreadPoll> onSubmitPollVote;

  @override
  State<ThreadDetailContent> createState() => _ThreadDetailContentState();
}

class _ThreadDetailContentState extends State<ThreadDetailContent> {
  late ThreadDetailRenderEntryPlanner _entryPlanner;

  @override
  void initState() {
    super.initState();
    _entryPlanner = _createEntryPlanner();
    widget.imageDimensionStore?.addListener(_onImageDimensionsChanged);
  }

  @override
  void didUpdateWidget(covariant ThreadDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.imageDimensionStore, widget.imageDimensionStore)) {
      oldWidget.imageDimensionStore?.removeListener(_onImageDimensionsChanged);
      widget.imageDimensionStore?.addListener(_onImageDimensionsChanged);
    }
    if (!identical(oldWidget.diagnosticRecorder, widget.diagnosticRecorder) ||
        !identical(
          oldWidget.imageDimensionStore,
          widget.imageDimensionStore,
        )) {
      _entryPlanner = _createEntryPlanner();
    }
    if (!identical(oldWidget.state.posts, widget.state.posts) ||
        oldWidget.state.currentPage != widget.state.currentPage) {
      _entryPlanner.prune(widget.state.posts);
    }
  }

  @override
  void dispose() {
    widget.imageDimensionStore?.removeListener(_onImageDimensionsChanged);
    super.dispose();
  }

  /// 构造接入持久化尺寸的 render plan 装配器。
  ///
  /// resolver 开启 [ThreadPostResourceLayoutHintResolver.lockTrustedDimensions]：
  /// 只要 hint 来自 HTML 或缓存即锁定首帧高度；无尺寸图片仍走受 above-viewport
  /// 保护的 decode 回填。store 的 signature 已并入 resolver 签名，缓存预热到达后
  /// render plan 缓存自然失效并以可信尺寸重建。
  ThreadDetailRenderEntryPlanner _createEntryPlanner() {
    return ThreadDetailRenderEntryPlanner(
      diagnosticRecorder: widget.diagnosticRecorder,
      bodyRenderPlanner: ThreadPostBodyRenderPlanner(
        resourceLayoutHintResolver: ThreadPostResourceLayoutHintResolver(
          lockTrustedDimensions: true,
          dimensionLookup: widget.imageDimensionStore,
        ),
      ),
    );
  }

  void _onImageDimensionsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final entries = _entryPlanner.buildEntries(
      posts: widget.state.posts,
      targetPid: widget.targetPid,
    );
    return ListView.builder(
      key: const Key('thread-detail-list'),
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      cacheExtent: 900,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        _recordEntryBuild(entry);
        return _buildEntry(context, entry, palette);
      },
    );
  }

  void _recordEntryBuild(ThreadDetailRenderEntry entry) {
    // Hot path: runs for every item build. Bail out before computing scroll
    // position or building the message string when diagnostics are disabled
    // (always the case in release, where the recorder is a const no-op).
    if (!widget.diagnosticRecorder.enabled) {
      return;
    }
    final position = widget.scrollController?.hasClients == true
        ? widget.scrollController!.position.pixels
        : null;
    widget.diagnosticRecorder.record(
      type: ThreadDetailDiagnosticEventType.entryBuild,
      entryKey: entry.key,
      pid: entry.post?.pid,
      scrollOffset: position,
      message: 'build ${entry.kind.name}',
    );
  }

  Widget _buildEntry(
    BuildContext context,
    ThreadDetailRenderEntry entry,
    ThreadDetailNativePalette palette,
  ) {
    switch (entry.kind) {
      case ThreadDetailRenderEntryKind.postHeader:
        final header = _ThreadPostCardHeaderEntry(
          key: Key(entry.key),
          post: entry.post!,
          state: widget.state,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          palette: palette,
          onOpenAuthorProfile: widget.onOpenAuthorProfile,
        );
        return _PostBuildObserver(
          index: entry.postIndex,
          onPostBuilt: widget.onPostBuilt,
          child: header,
        );
      case ThreadDetailRenderEntryKind.postBody:
        final plan = entry.requirePlan();
        return _ThreadPostCardBodyEntry(
          key: Key(entry.key),
          post: entry.post!,
          threadId: widget.state.tid,
          plan: plan,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          imageOpenContext: _imageOpenContext(entry.post!),
          palette: palette,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenPostImages: widget.onOpenPostImages,
          onOpenPostCopyActions: widget.onOpenPostCopyActions,
          diagnosticRecorder: widget.diagnosticRecorder,
        );
      case ThreadDetailRenderEntryKind.postBodySegment:
        final segmentEntry = _ThreadPostCardBodySegmentEntry(
          key: Key(entry.key),
          post: entry.post!,
          threadId: widget.state.tid,
          plan: entry.plan!,
          segment: entry.segment!,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          imageOpenContext: _imageOpenContext(entry.post!),
          palette: palette,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenPostImages: widget.onOpenPostImages,
          onOpenPostCopyActions: widget.onOpenPostCopyActions,
          diagnosticRecorder: widget.diagnosticRecorder,
        );
        if (entry.segment!.index == 0) {
          return KeyedSubtree(
            key: Key('thread-post-body-${entry.post!.pid}'),
            child: segmentEntry,
          );
        }
        return segmentEntry;
      case ThreadDetailRenderEntryKind.postFooter:
        return _ThreadPostCardFooterEntry(
          key: Key(entry.key),
          post: entry.post!,
          state: widget.state,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          onOpenPostReply: widget.onOpenPostReply,
          onOpenPostRate: widget.onOpenPostRate,
          onOpenPostComment: widget.onOpenPostComment,
          onCopyActionUrl: widget.onCopyActionUrl,
          onOpenPostLink: widget.onOpenPostLink,
          onTogglePollOption: widget.onTogglePollOption,
          onSubmitPollVote: widget.onSubmitPollVote,
          palette: palette,
        );
      case ThreadDetailRenderEntryKind.pagination:
        return ThreadLoadMoreSection(
          key: const Key('thread-detail-pagination'),
          hasMore: widget.state.hasMore,
          isLoadingMore: widget.state.isLoadingMore,
          currentPage: widget.state.currentPage <= 0
              ? 1
              : widget.state.currentPage,
          lastPage: widget.state.lastPage,
          canLoadPrevious: widget.state.currentPage > 1,
          onLoadPreviousPage: widget.onLoadPreviousPage,
          onLoadNextPage: widget.onLoadNextPage,
          onLoadPageNumber: widget.onLoadPageNumber,
          palette: palette,
        );
      case ThreadDetailRenderEntryKind.targetSpacer:
        return SizedBox(
          key: const Key('thread-detail-target-scroll-spacer'),
          height: MediaQuery.sizeOf(context).height * 0.72,
        );
    }
  }

  ThreadImageOpenContext _imageOpenContext(ThreadPost post) {
    return ThreadImageOpenContext(
      tid: widget.state.tid,
      pid: post.pid,
      postNumber: post.number,
      referer: widget.imageReferer,
      cacheKeyForImage: (image) {
        return ForumImageCacheRequests.threadInline(
          tid: widget.state.tid,
          url: image.url,
          imageIndex: image.index,
        ).cacheKey;
      },
    );
  }
}

class _ThreadPostCardHeaderEntry extends StatelessWidget {
  const _ThreadPostCardHeaderEntry({
    super.key,
    required this.post,
    required this.state,
    required this.highlighted,
    required this.palette,
    required this.onOpenAuthorProfile,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final bool highlighted;
  final ThreadDetailNativePalette palette;
  final ValueChanged<ThreadPost> onOpenAuthorProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('thread-post-card-${post.pid}'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      decoration: _cardSegmentDecoration(
        palette: palette,
        highlighted: highlighted,
        position: _ThreadPostCardSegmentPosition.header,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isFirst) ...[
            _FirstPostThreadSummary(state: state, palette: palette),
            const SizedBox(height: 11),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThreadAuthorAvatar(
                key: Key('thread-author-avatar-${post.pid}'),
                author: post.author,
                authorId: post.authorId,
                avatarUrl: post.avatarUrl,
                palette: palette,
                onTap: post.authorId.trim().isEmpty
                    ? null
                    : () => onOpenAuthorProfile(post),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _PostHeader(
                  post: post,
                  palette: palette,
                  viewsLabel: post.isFirst ? state.views.toString() : null,
                  repliesLabel: post.isFirst ? state.replies.toString() : null,
                  onOpenAuthorProfile: post.authorId.trim().isEmpty
                      ? null
                      : () => onOpenAuthorProfile(post),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThreadPostCardBodyEntry extends StatelessWidget {
  const _ThreadPostCardBodyEntry({
    super.key,
    required this.post,
    required this.threadId,
    required this.plan,
    required this.highlighted,
    required this.imageHeaderBuilder,
    required this.imageOpenContext,
    required this.palette,
    required this.onOpenPostLink,
    required this.onOpenPostImages,
    required this.onOpenPostCopyActions,
    required this.diagnosticRecorder,
  });

  final ThreadPost post;
  final String threadId;
  final ThreadPostBodyRenderPlan plan;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadImageOpenContext imageOpenContext;
  final ThreadDetailNativePalette palette;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostCopyActions;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onOpenPostCopyActions(post, plan),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        decoration: _cardSegmentDecoration(
          palette: palette,
          highlighted: highlighted,
          position: _ThreadPostCardSegmentPosition.middle,
        ),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.bodyText,
            height: 1.5,
          ),
          child: ThreadPostBodyView(
            key: Key('thread-post-${post.pid}'),
            document: plan.document,
            blocks: plan.displayDocument.blocks,
            images: plan.images,
            imageHeaderBuilder: imageHeaderBuilder,
            imageCacheOwnerId: threadId,
            imageOpenContext: imageOpenContext,
            resourceLayoutHints: plan.resourceLayoutHints,
            resourceLayoutPolicy:
                ThreadPostResourceLayoutPolicy.adaptiveBlockImagesForReading,
            selectionEnabled: false,
            diagnosticRecorder: diagnosticRecorder,
            onOpenLink: onOpenPostLink,
            onOpenImage: (request) => onOpenPostImages?.call(post, request),
          ),
        ),
      ),
    );
  }
}

class _ThreadPostCardBodySegmentEntry extends StatelessWidget {
  const _ThreadPostCardBodySegmentEntry({
    super.key,
    required this.post,
    required this.threadId,
    required this.plan,
    required this.segment,
    required this.highlighted,
    required this.imageHeaderBuilder,
    required this.imageOpenContext,
    required this.palette,
    required this.onOpenPostLink,
    required this.onOpenPostImages,
    required this.onOpenPostCopyActions,
    required this.diagnosticRecorder,
  });

  final ThreadPost post;
  final String threadId;
  final ThreadPostBodyRenderPlan plan;
  final ThreadPostBodySegment segment;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadImageOpenContext imageOpenContext;
  final ThreadDetailNativePalette palette;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostCopyActions;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onOpenPostCopyActions(post, plan),
      child: Container(
        padding: EdgeInsets.fromLTRB(10, _segmentTopPadding(segment), 10, 0),
        decoration: _cardSegmentDecoration(
          palette: palette,
          highlighted: highlighted,
          position: _ThreadPostCardSegmentPosition.middle,
        ),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.bodyText,
            height: 1.5,
          ),
          child: ThreadPostBodySegmentView(
            document: plan.document,
            segment: segment,
            images: plan.images,
            imageHeaderBuilder: imageHeaderBuilder,
            imageCacheOwnerId: threadId,
            imageOpenContext: imageOpenContext,
            resourceLayoutHints: plan.resourceLayoutHints,
            resourceLayoutPolicy:
                ThreadPostResourceLayoutPolicy.adaptiveBlockImagesForReading,
            selectionEnabled: false,
            diagnosticRecorder: diagnosticRecorder,
            onOpenLink: onOpenPostLink,
            onOpenImage: (request) => onOpenPostImages?.call(post, request),
          ),
        ),
      ),
    );
  }

  double _segmentTopPadding(ThreadPostBodySegment segment) {
    if (segment.index == 0) {
      return 8;
    }
    final blocks = segment.blocks;
    if (blocks.isNotEmpty && blocks.first.continuesPrevious) {
      return 0;
    }
    return ThreadPostBodyStyle.defaults.blockSpacing;
  }
}

class _ThreadPostCardFooterEntry extends StatelessWidget {
  const _ThreadPostCardFooterEntry({
    super.key,
    required this.post,
    required this.state,
    required this.highlighted,
    required this.imageHeaderBuilder,
    required this.onOpenPostReply,
    required this.onOpenPostRate,
    required this.onOpenPostComment,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
    required this.palette,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<ThreadPost> onOpenPostReply;
  final ValueChanged<ThreadPost> onOpenPostRate;
  final ValueChanged<ThreadPost> onOpenPostComment;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPoll poll, ThreadPollOption option)
  onTogglePollOption;
  final ValueChanged<ThreadPoll> onSubmitPollVote;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: _cardSegmentDecoration(
        palette: palette,
        highlighted: highlighted,
        position: _ThreadPostCardSegmentPosition.footer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.tagLinks.isNotEmpty) ...[
            ThreadPostTagLinksSection(
              tags: post.tagLinks,
              palette: palette,
              onOpenTag: onOpenPostLink,
            ),
            const SizedBox(height: 10),
          ],
          if (post.poll != null) ...[
            ThreadPollCard(
              poll: post.poll!,
              selectedOptionIds: state.selectedPollOptionIds,
              isSubmitting: state.isPollVoteSubmitting,
              hint: state.pollVoteHint,
              onToggleOption: (option) =>
                  onTogglePollOption(post.poll!, option),
              onSubmit: () => onSubmitPollVote(post.poll!),
              palette: palette,
            ),
            const SizedBox(height: 10),
          ],
          if (post.comments.isNotEmpty) ...[
            ThreadPostCommentSection(
              comments: post.comments,
              imageHeaderBuilder: imageHeaderBuilder,
              palette: palette,
            ),
            const SizedBox(height: 10),
          ],
          if (post.ratingSummary != null) ...[
            ThreadPostRatingSection(
              summary: post.ratingSummary!,
              palette: palette,
              onCopyActionUrl: onCopyActionUrl,
            ),
            const SizedBox(height: 10),
          ],
          ThreadPostActionRow(
            post: post,
            palette: palette,
            onOpenPostReply: onOpenPostReply,
            onOpenPostRate: onOpenPostRate,
            onOpenPostComment: onOpenPostComment,
            onCopyActionUrl: onCopyActionUrl,
          ),
        ],
      ),
    );
  }
}

class _PostBuildObserver extends StatefulWidget {
  const _PostBuildObserver({
    required this.index,
    required this.onPostBuilt,
    required this.child,
  });

  final int index;
  final ValueChanged<int>? onPostBuilt;
  final Widget child;

  @override
  State<_PostBuildObserver> createState() => _PostBuildObserverState();
}

class _PostBuildObserverState extends State<_PostBuildObserver> {
  @override
  void initState() {
    super.initState();
    _scheduleNotify();
  }

  @override
  void didUpdateWidget(covariant _PostBuildObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.onPostBuilt != widget.onPostBuilt) {
      _scheduleNotify();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _scheduleNotify() {
    final callback = widget.onPostBuilt;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        callback(widget.index);
      }
    });
  }
}

/// Single-card preview/compat renderer.
///
/// The production native thread detail page uses [ThreadDetailContent], which
/// renders post header/body/footer entries separately to keep long posts lazy.
class ThreadPostCard extends StatelessWidget {
  const ThreadPostCard({
    super.key,
    required this.post,
    required this.state,
    this.highlighted = false,
    required this.imageHeaderBuilder,
    required this.onOpenPostReply,
    required this.onOpenPostRate,
    required this.onOpenPostComment,
    required this.onOpenAuthorProfile,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    required this.onOpenPostImages,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
    required this.palette,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<ThreadPost> onOpenPostReply;
  final ValueChanged<ThreadPost> onOpenPostRate;
  final ValueChanged<ThreadPost> onOpenPostComment;
  final ValueChanged<ThreadPost> onOpenAuthorProfile;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPoll poll, ThreadPollOption option)
  onTogglePollOption;
  final ValueChanged<ThreadPoll> onSubmitPollVote;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('thread-post-card-${post.pid}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: highlighted
          ? _highlightedCardDecoration(palette)
          : _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isFirst) ...[
            _FirstPostThreadSummary(state: state, palette: palette),
            const SizedBox(height: 11),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThreadAuthorAvatar(
                key: Key('thread-author-avatar-${post.pid}'),
                author: post.author,
                authorId: post.authorId,
                avatarUrl: post.avatarUrl,
                palette: palette,
                onTap: post.authorId.trim().isEmpty
                    ? null
                    : () => onOpenAuthorProfile(post),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _PostHeader(
                  post: post,
                  palette: palette,
                  viewsLabel: post.isFirst ? state.views.toString() : null,
                  repliesLabel: post.isFirst ? state.replies.toString() : null,
                  onOpenAuthorProfile: post.authorId.trim().isEmpty
                      ? null
                      : () => onOpenAuthorProfile(post),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.bodyText,
              height: 1.5,
            ),
            child: ThreadPostHtml(
              data: post.message,
              key: Key('thread-post-${post.pid}'),
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: state.tid,
              onOpenLink: onOpenPostLink,
              onOpenImage: (request) => onOpenPostImages?.call(post, request),
            ),
          ),
          if (post.tagLinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            ThreadPostTagLinksSection(
              tags: post.tagLinks,
              palette: palette,
              onOpenTag: onOpenPostLink,
            ),
          ],
          if (post.poll != null) ...[
            const SizedBox(height: 10),
            ThreadPollCard(
              poll: post.poll!,
              selectedOptionIds: state.selectedPollOptionIds,
              isSubmitting: state.isPollVoteSubmitting,
              hint: state.pollVoteHint,
              onToggleOption: (option) =>
                  onTogglePollOption(post.poll!, option),
              onSubmit: () => onSubmitPollVote(post.poll!),
              palette: palette,
            ),
          ],
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ThreadPostCommentSection(
              comments: post.comments,
              imageHeaderBuilder: imageHeaderBuilder,
              palette: palette,
            ),
          ],
          if (post.ratingSummary != null) ...[
            const SizedBox(height: 10),
            ThreadPostRatingSection(
              summary: post.ratingSummary!,
              palette: palette,
              onCopyActionUrl: onCopyActionUrl,
            ),
          ],
          const SizedBox(height: 10),
          ThreadPostActionRow(
            post: post,
            palette: palette,
            onOpenPostReply: onOpenPostReply,
            onOpenPostRate: onOpenPostRate,
            onOpenPostComment: onOpenPostComment,
            onCopyActionUrl: onCopyActionUrl,
          ),
        ],
      ),
    );
  }
}

class _FirstPostThreadSummary extends StatelessWidget {
  const _FirstPostThreadSummary({required this.state, required this.palette});

  final ThreadDetailPageState state;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('thread-detail-first-post-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.subject.isNotEmpty ? state.subject : '帖子详情',
          style: textTheme.titleMedium?.copyWith(
            color: palette.title,
            fontWeight: FontWeight.w800,
            height: 1.24,
          ),
        ),
      ],
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.palette,
    this.viewsLabel,
    this.repliesLabel,
    this.onOpenAuthorProfile,
  });

  final ThreadPost post;
  final ThreadDetailNativePalette palette;
  final String? viewsLabel;
  final String? repliesLabel;
  final VoidCallback? onOpenAuthorProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final views = viewsLabel?.trim();
    final replies = repliesLabel?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onOpenAuthorProfile,
                  child: Text(
                    post.author.isNotEmpty ? post.author : '匿名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: palette.author,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (post.dateline.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  post.dateline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.softText,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          alignment: WrapAlignment.end,
          children: [
            if (views != null && views.isNotEmpty)
              ThreadMetricPill(
                icon: Icons.visibility_outlined,
                label: views,
                palette: palette,
              ),
            if (replies != null && replies.isNotEmpty)
              ThreadMetricPill(
                icon: Icons.forum_outlined,
                label: replies,
                palette: palette,
              ),
            ThreadPill(label: '${post.number}#', palette: palette),
          ],
        ),
      ],
    );
  }
}

class ThreadPostCommentSection extends StatefulWidget {
  const ThreadPostCommentSection({
    super.key,
    required this.comments,
    required this.imageHeaderBuilder,
    required this.palette,
  });

  final List<ThreadPostCommentEntry> comments;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadDetailNativePalette palette;

  @override
  State<ThreadPostCommentSection> createState() =>
      _ThreadPostCommentSectionState();
}

class _ThreadPostCommentSectionState extends State<ThreadPostCommentSection> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('thread-post-comment-section'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: widget.palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleSectionHeader(
            key: const Key('thread-post-comment-header'),
            label: '点评',
            icon: Icons.chat_bubble_outline,
            palette: widget.palette,
            showSummaries: !_expanded,
            collapsedSummaries: [
              _SectionSummaryPill(
                label: widget.comments.length.toString(),
                palette: widget.palette,
              ),
            ],
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 9),
                for (
                  var index = 0;
                  index < widget.comments.length;
                  index++
                ) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: widget.palette.outlineSoft,
                      ),
                    ),
                  ThreadPostCommentRow(
                    comment: widget.comments[index],
                    imageHeaderBuilder: widget.imageHeaderBuilder,
                    palette: widget.palette,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CollapsibleSectionHeader extends StatelessWidget {
  const _CollapsibleSectionHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.palette,
    required this.showSummaries,
    required this.collapsedSummaries,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final ThreadDetailNativePalette palette;
  final bool showSummaries;
  final List<Widget> collapsedSummaries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: palette.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (showSummaries) Wrap(spacing: 5, children: collapsedSummaries),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionSummaryPill extends StatelessWidget {
  const _SectionSummaryPill({required this.label, required this.palette});

  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.muted,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _ThreadPostRatingCollapseSummary {
  const _ThreadPostRatingCollapseSummary({
    required this.countLabel,
    required this.scoreLabel,
  });

  final String countLabel;
  final String? scoreLabel;

  factory _ThreadPostRatingCollapseSummary.from(
    ThreadPostRatingSummary summary,
  ) {
    final count = _firstInt(summary.participantText) ?? summary.ratings.length;
    final score =
        _firstSignedInt(summary.scoreText) ?? _sumRatingScores(summary.ratings);
    return _ThreadPostRatingCollapseSummary(
      countLabel: count.toString(),
      scoreLabel: score == null ? null : _formatSignedScore(score),
    );
  }

  static int? _firstInt(String text) {
    return int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0) ?? '');
  }

  static int? _firstSignedInt(String text) {
    final match = RegExp(r'[+-]?\s*\d+').firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!.replaceAll(' ', ''));
  }

  static int? _sumRatingScores(List<ThreadPostRating> ratings) {
    var hasScore = false;
    var total = 0;
    for (final rating in ratings) {
      final score = _firstSignedInt(rating.score);
      if (score == null) {
        continue;
      }
      hasScore = true;
      total += score;
    }
    return hasScore ? total : null;
  }

  static String _formatSignedScore(int score) {
    if (score > 0) {
      return '+$score';
    }
    return score.toString();
  }
}

class ThreadPostCommentRow extends StatelessWidget {
  const ThreadPostCommentRow({
    super.key,
    required this.comment,
    required this.imageHeaderBuilder,
    required this.palette,
  });

  final ThreadPostCommentEntry comment;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ThreadCommentAvatar(
          comment: comment,
          imageHeaderBuilder: imageHeaderBuilder,
          palette: palette,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      comment.author.isEmpty ? '用户' : comment.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: palette.author,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (comment.dateline.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        comment.dateline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.softText,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (comment.message.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  comment.message,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.bodyText,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadCommentAvatar extends StatelessWidget {
  const _ThreadCommentAvatar({
    required this.comment,
    required this.imageHeaderBuilder,
    required this.palette,
  });

  final ThreadPostCommentEntry comment;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    final imageUrl = comment.avatarUrl?.trim();
    final fallback = _ThreadCommentAvatarFallback(
      author: comment.author,
      palette: palette,
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl == null || imageUrl.isEmpty
            ? fallback
            : CachedLibraryImage(
                request: ForumImageCacheRequests.avatar(
                  ownerId: comment.authorId?.trim().isNotEmpty == true
                      ? comment.authorId!
                      : comment.author,
                  ownerType: ImageCacheOwnerType.thread,
                  url: imageUrl,
                ),
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: fallback,
                errorPlaceholder: fallback,
                headerBuilder: imageHeaderBuilder,
              ),
      ),
    );
  }
}

class _ThreadCommentAvatarFallback extends StatelessWidget {
  const _ThreadCommentAvatarFallback({
    required this.author,
    required this.palette,
  });

  final String author;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.avatarBackground,
      child: Center(
        child: Text(
          _authorInitial(author),
          style: TextStyle(
            color: palette.avatarForeground,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class ThreadPostRatingSection extends StatefulWidget {
  const ThreadPostRatingSection({
    super.key,
    required this.summary,
    required this.palette,
    required this.onCopyActionUrl,
  });

  final ThreadPostRatingSummary summary;
  final ThreadDetailNativePalette palette;
  final void Function(String label, String url) onCopyActionUrl;

  @override
  State<ThreadPostRatingSection> createState() =>
      _ThreadPostRatingSectionState();
}

class _ThreadPostRatingSectionState extends State<ThreadPostRatingSection> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final collapsedSummary = _ThreadPostRatingCollapseSummary.from(
      widget.summary,
    );
    return Container(
      key: const Key('thread-post-rating-section'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: widget.palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleSectionHeader(
            key: const Key('thread-post-rating-header'),
            label: '评分',
            icon: Icons.favorite_outline,
            palette: widget.palette,
            showSummaries: !_expanded,
            collapsedSummaries: [
              _SectionSummaryPill(
                label: collapsedSummary.countLabel,
                palette: widget.palette,
              ),
              if (collapsedSummary.scoreLabel != null)
                _SectionSummaryPill(
                  label: collapsedSummary.scoreLabel!,
                  palette: widget.palette,
                ),
            ],
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        widget.summary.participantText.isEmpty
                            ? '参与人数'
                            : widget.summary.participantText,
                        style: textTheme.labelSmall?.copyWith(
                          color: widget.palette.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        widget.summary.scoreText.isEmpty
                            ? '积分'
                            : widget.summary.scoreText,
                        style: textTheme.labelSmall?.copyWith(
                          color: widget.palette.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '理由',
                        style: textTheme.labelSmall?.copyWith(
                          color: widget.palette.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final rating in widget.summary.ratings) ...[
                  const SizedBox(height: 6),
                  ThreadPostRatingRow(rating: rating, palette: widget.palette),
                ],
                if (widget.summary.viewAllUrl?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ThreadRatingLinkButton(
                      label: '查看全部评分',
                      palette: widget.palette,
                      onPressed: () => widget.onCopyActionUrl(
                        '查看全部评分',
                        widget.summary.viewAllUrl!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class ThreadPostRatingRow extends StatelessWidget {
  const ThreadPostRatingRow({
    super.key,
    required this.rating,
    required this.palette,
  });

  final ThreadPostRating rating;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            rating.userName.isEmpty ? '用户' : rating.userName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: palette.bodyText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            rating.score,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: palette.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            rating.reason,
            style: textTheme.labelSmall?.copyWith(
              color: palette.softText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class ThreadRatingLinkButton extends StatelessWidget {
  const ThreadRatingLinkButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final ThreadDetailNativePalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class ThreadPostActionRow extends StatelessWidget {
  const ThreadPostActionRow({
    super.key,
    required this.post,
    required this.palette,
    required this.onOpenPostReply,
    required this.onOpenPostRate,
    required this.onOpenPostComment,
    required this.onCopyActionUrl,
  });

  final ThreadPost post;
  final ThreadDetailNativePalette palette;
  final ValueChanged<ThreadPost> onOpenPostReply;
  final ValueChanged<ThreadPost> onOpenPostRate;
  final ValueChanged<ThreadPost> onOpenPostComment;
  final void Function(String label, String url) onCopyActionUrl;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: Key('thread-post-actions-${post.pid}'),
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        if (post.rateUrl?.trim().isNotEmpty == true)
          ThreadActionChip(
            label: '评分',
            icon: Icons.favorite_border,
            palette: palette,
            onPressed: () => onOpenPostRate(post),
          ),
        if (post.commentUrl?.trim().isNotEmpty == true)
          ThreadActionChip(
            label: '点评',
            icon: Icons.chat_bubble_outline,
            palette: palette,
            onPressed: () => onOpenPostComment(post),
          ),
        ThreadActionChip(
          label: '回复',
          icon: Icons.reply_outlined,
          palette: palette,
          onPressed: () => onOpenPostReply(post),
        ),
      ],
    );
  }
}

class ThreadPostTagLinksSection extends StatelessWidget {
  const ThreadPostTagLinksSection({
    super.key,
    required this.tags,
    required this.palette,
    required this.onOpenTag,
  });

  final List<ThreadPostTagLink> tags;
  final ThreadDetailNativePalette palette;
  final ValueChanged<String> onOpenTag;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('thread-post-tag-links'),
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final tag in tags)
          Material(
            key: Key('thread-post-tag-link-${tag.tagId ?? tag.label}'),
            color: palette.chipBackground,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onOpenTag(tag.url),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sell_outlined, size: 13, color: palette.accent),
                    const SizedBox(width: 4),
                    Text(
                      tag.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ThreadActionChip extends StatelessWidget {
  const ThreadActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final ThreadDetailNativePalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.chipBackground,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: SizedBox(
          height: 27,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: palette.softText),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ThreadPostRateSheet extends StatefulWidget {
  const ThreadPostRateSheet({super.key, required this.form});

  final ThreadPostRateForm form;

  @override
  State<ThreadPostRateSheet> createState() => _ThreadPostRateSheetState();
}

class _ThreadPostRateSheetState extends State<ThreadPostRateSheet> {
  late int _score;
  late bool _notifyAuthor;
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _score = widget.form.defaultScore;
    _notifyAuthor = widget.form.notifyAuthorDefault;
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
        child: Column(
          key: const Key('thread-post-rate-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '评分',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-rate-close-button'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '积分',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-rate-decrease-button'),
                  onPressed: _score > widget.form.scoreMin
                      ? () => setState(() => _score -= 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    '+$_score',
                    key: const Key('thread-post-rate-score-label'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('thread-post-rate-increase-button'),
                  onPressed: _score < widget.form.scoreMax
                      ? () => setState(() => _score += 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text(_scoreHint, style: theme.textTheme.labelSmall),
            if (widget.form.reasonOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in widget.form.reasonOptions)
                    ActionChip(
                      key: Key('thread-post-rate-reason-$reason'),
                      label: Text(reason),
                      onPressed: () {
                        _reasonController.text = reason;
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('thread-post-rate-reason-input'),
              controller: _reasonController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '评分理由',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('thread-post-rate-notify-switch'),
              contentPadding: EdgeInsets.zero,
              value: _notifyAuthor,
              onChanged: (value) => setState(() => _notifyAuthor = value),
              title: const Text('通知作者'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('thread-post-rate-submit-button'),
                onPressed: _reasonController.text.trim().isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          ThreadPostRateDraft(
                            form: widget.form,
                            score: _score,
                            reason: _reasonController.text,
                            notifyAuthor: _notifyAuthor,
                          ),
                        );
                      },
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _scoreHint {
    final range = '范围 ${widget.form.scoreMin}~${widget.form.scoreMax}';
    final remaining = widget.form.todayRemaining;
    if (remaining <= 0) {
      return range;
    }
    return '$range，今日剩余 $remaining';
  }
}

class ThreadPostCommentSheet extends StatefulWidget {
  const ThreadPostCommentSheet({super.key, required this.form});

  final ThreadPostCommentForm form;

  @override
  State<ThreadPostCommentSheet> createState() => _ThreadPostCommentSheetState();
}

class _ThreadPostCommentSheetState extends State<ThreadPostCommentSheet> {
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxLength = widget.form.maxLength <= 0 ? 200 : widget.form.maxLength;
    final message = _messageController.text.trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
        child: Column(
          key: const Key('thread-post-comment-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '点评',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-comment-close-button'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('thread-post-comment-message-input'),
              controller: _messageController,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: maxLength,
              decoration: const InputDecoration(
                labelText: '点评内容',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('thread-post-comment-submit-button'),
                onPressed: message.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          ThreadPostCommentDraft(
                            form: widget.form,
                            message: _messageController.text,
                          ),
                        );
                      },
                child: const Text('发布'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThreadPollCard extends StatefulWidget {
  const ThreadPollCard({
    super.key,
    required this.poll,
    required this.selectedOptionIds,
    required this.isSubmitting,
    required this.hint,
    required this.onToggleOption,
    required this.onSubmit,
    required this.palette,
  });

  final ThreadPoll poll;
  final Set<String> selectedOptionIds;
  final bool isSubmitting;
  final String? hint;
  final ValueChanged<ThreadPollOption> onToggleOption;
  final VoidCallback onSubmit;
  final ThreadDetailNativePalette palette;

  @override
  State<ThreadPollCard> createState() => _ThreadPollCardState();
}

class _ThreadPollCardState extends State<ThreadPollCard> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        widget.poll.canVote &&
        widget.selectedOptionIds.isNotEmpty &&
        !widget.isSubmitting &&
        (widget.poll.actionUrl?.trim().isNotEmpty ?? false);
    final statusText = widget.poll.statusText?.trim();
    return Container(
      key: const Key('thread-poll-card'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: widget.palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('thread-poll-header'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.poll.summary,
                        style: textTheme.labelLarge?.copyWith(
                          color: widget.palette.title,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.poll.deadlineText?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 5),
                  Text(
                    widget.poll.deadlineText!.trim(),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                for (final option in widget.poll.options) ...[
                  ThreadPollOptionTile(
                    option: option,
                    palette: widget.palette,
                    isMultipleChoice: widget.poll.isMultipleChoice,
                    showSelector: widget.poll.canVote,
                    selected: widget.selectedOptionIds.contains(option.id),
                    enabled: widget.poll.canVote && !widget.isSubmitting,
                    onTap: () => widget.onToggleOption(option),
                  ),
                  const SizedBox(height: 8),
                ],
                if (statusText != null && statusText.isNotEmpty) ...[
                  Text(
                    statusText,
                    key: const Key('thread-poll-status-text'),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.hint?.trim().isNotEmpty == true) ...[
                  Text(
                    widget.hint!.trim(),
                    key: const Key('thread-poll-vote-hint'),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.poll.canVote)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('thread-poll-submit-button'),
                      onPressed: canSubmit ? widget.onSubmit : null,
                      child: widget.isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('提交'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class ThreadPollOptionTile extends StatelessWidget {
  const ThreadPollOptionTile({
    super.key,
    required this.option,
    required this.palette,
    required this.isMultipleChoice,
    required this.showSelector,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ThreadPollOption option;
  final ThreadDetailNativePalette palette;
  final bool isMultipleChoice;
  final bool showSelector;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = option.percent;
    final color = _parseColor(option.colorHex) ?? palette.accent;
    return Material(
      color: selected
          ? palette.accent.withValues(alpha: 0.07)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('thread-poll-option-${option.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showSelector) ...[
                    Icon(
                      selected
                          ? isMultipleChoice
                                ? Icons.check_box
                                : Icons.radio_button_checked
                          : isMultipleChoice
                          ? Icons.check_box_outline_blank
                          : Icons.radio_button_unchecked,
                      size: 17,
                      color: selected ? palette.accent : palette.softText,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.bodyText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (percent != null)
                    Text(
                      '${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 2)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (percent != null) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (percent / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: palette.pollTrack,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                if (option.voteCount != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${option.voteCount} 票',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: palette.softText),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String? value) {
    final source = value?.trim();
    if (source == null || source.isEmpty || !source.startsWith('#')) {
      return null;
    }
    final hex = source.substring(1);
    if (hex.length == 3) {
      final expanded = hex.split('').map((char) => '$char$char').join();
      return Color(int.parse('FF$expanded', radix: 16));
    }
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }
}

class ThreadAuthorAvatar extends StatelessWidget {
  const ThreadAuthorAvatar({
    super.key,
    required this.author,
    required this.authorId,
    required this.avatarUrl,
    required this.palette,
    this.onTap,
  });

  final String author;
  final String authorId;
  final String? avatarUrl;
  final ThreadDetailNativePalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim();
    final useDefaultAvatar = isForumDefaultOrUnsupportedAvatarUrl(imageUrl);
    final placeholder = ColoredBox(
      color: palette.avatarBackground,
      child: Center(
        child: Text(
          _authorInitial(author),
          style: TextStyle(
            color: palette.avatarForeground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    final avatar = ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: useDefaultAvatar
            ? ColoredBox(
                color: palette.avatarBackground,
                child: forumDefaultAvatarImage(width: 34, height: 34),
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                width: 34,
                height: 34,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
    if (onTap == null) {
      return avatar;
    }
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: avatar,
    );
  }
}

class ThreadMetricPill extends StatelessWidget {
  const ThreadMetricPill({
    super.key,
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.softText),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ThreadPill extends StatelessWidget {
  const ThreadPill({
    super.key,
    required this.label,
    required this.palette,
    this.emphasized = false,
  });

  final String label;
  final ThreadDetailNativePalette palette;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? palette.accent.withValues(alpha: 0.10)
            : palette.chipBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasized ? palette.accent : palette.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ThreadLoadMoreSection extends StatelessWidget {
  const ThreadLoadMoreSection({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.currentPage,
    required this.lastPage,
    required this.canLoadPrevious,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onLoadPageNumber,
    required this.palette,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final int currentPage;
  final int? lastPage;
  final bool canLoadPrevious;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onLoadPageNumber;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ThreadPageButton(
            key: const Key('thread-detail-previous-page-button'),
            onPressed: canLoadPrevious ? onLoadPreviousPage : null,
            label: '上一页',
            palette: palette,
          ),
          const SizedBox(width: 6),
          _ThreadPageButton(
            key: const Key('thread-detail-current-page-button'),
            onPressed: () => _showPagePicker(context),
            label: '第 $currentPage 页',
            palette: palette,
          ),
          const SizedBox(width: 6),
          _ThreadPageButton(
            key: const Key('thread-detail-load-more-button'),
            onPressed: hasMore ? onLoadNextPage : null,
            label: hasMore ? '下一页' : '没有更多',
            palette: palette,
          ),
        ],
      ),
    );
  }

  Future<void> _showPagePicker(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _ThreadDetailPagePickerDialog(
        currentPage: currentPage,
        lastPage: lastPage,
      ),
    );
    if (selected == null || selected == currentPage) {
      return;
    }
    onLoadPageNumber(selected);
  }
}

class _ThreadPageButton extends StatelessWidget {
  const _ThreadPageButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.palette,
  });

  final VoidCallback? onPressed;
  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: palette.chipBackground,
          disabledBackgroundColor: palette.chipBackground,
          foregroundColor: palette.muted,
          disabledForegroundColor: palette.softText,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ThreadDetailPagePickerDialog extends StatefulWidget {
  const _ThreadDetailPagePickerDialog({
    required this.currentPage,
    required this.lastPage,
  });

  final int currentPage;
  final int? lastPage;

  @override
  State<_ThreadDetailPagePickerDialog> createState() =>
      _ThreadDetailPagePickerDialogState();
}

class _ThreadDetailPagePickerDialogState
    extends State<_ThreadDetailPagePickerDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = widget.lastPage;
    return AlertDialog(
      key: const Key('thread-detail-page-picker-dialog'),
      title: const Text('选择页码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('thread-detail-page-input'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: lastPage == null ? '页码' : '页码（1-$lastPage）',
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-5-button'),
                increment: 5,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-10-button'),
                increment: 10,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-50-button'),
                increment: 50,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('thread-detail-page-confirm-button'),
          onPressed: () => _submit(context),
          child: const Text('跳转'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final page = int.tryParse(_controller.text.trim());
    final lastPage = widget.lastPage;
    if (page == null || page < 1) {
      setState(() => _errorText = '请输入有效页码');
      return;
    }
    if (lastPage != null && page > lastPage) {
      setState(() => _errorText = '不能超过第$lastPage页');
      return;
    }
    Navigator.of(context).pop(page);
  }
}

class _PageIncrementButton extends StatelessWidget {
  const _PageIncrementButton({
    required this.buttonKey,
    required this.increment,
    required this.currentPage,
    required this.lastPage,
  });

  final Key buttonKey;
  final int increment;
  final int currentPage;
  final int? lastPage;

  @override
  Widget build(BuildContext context) {
    final targetPage = currentPage + increment;
    final maxPage = lastPage;
    final enabled = maxPage == null || targetPage <= maxPage;
    return OutlinedButton(
      key: buttonKey,
      onPressed: enabled ? () => Navigator.of(context).pop(targetPage) : null,
      child: Text('+$increment'),
    );
  }
}

BoxDecoration _cardDecoration(ThreadDetailNativePalette palette) {
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(12),
    boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
  );
}

BoxDecoration _highlightedCardDecoration(ThreadDetailNativePalette palette) {
  return BoxDecoration(
    color: palette.accent.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12),
    boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
  );
}

enum _ThreadPostCardSegmentPosition { header, middle, footer }

BoxDecoration _cardSegmentDecoration({
  required ThreadDetailNativePalette palette,
  required bool highlighted,
  required _ThreadPostCardSegmentPosition position,
}) {
  final radius = switch (position) {
    _ThreadPostCardSegmentPosition.header => const BorderRadius.vertical(
      top: Radius.circular(12),
    ),
    _ThreadPostCardSegmentPosition.middle => BorderRadius.zero,
    _ThreadPostCardSegmentPosition.footer => const BorderRadius.vertical(
      bottom: Radius.circular(12),
    ),
  };
  return BoxDecoration(
    color: highlighted ? palette.accent.withValues(alpha: 0.10) : palette.card,
    borderRadius: radius,
    boxShadow: position == _ThreadPostCardSegmentPosition.header
        ? ForumNativeSurfaceShadows.card(palette.stateLayer)
        : null,
  );
}

String _authorInitial(String author) {
  final text = author.trim();
  if (text.isEmpty) {
    return '?';
  }
  return text.characters.first.toUpperCase();
}
