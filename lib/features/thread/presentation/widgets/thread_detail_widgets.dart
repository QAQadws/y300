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

// File split (Phase 5b): cohesive widget groups live in part files under the
// same library so private members and shared helpers remain accessible without
// changing visibility or call sites.
part 'thread_detail_pagination.dart';
part 'thread_detail_poll.dart';
part 'thread_detail_sheets.dart';
part 'thread_detail_footer.dart';

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
