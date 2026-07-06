import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/models/thread_detail_html_first_render_mode.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/thread_detail_render_entries.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/services/thread_html_image_preload_coordinator.dart';
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
part 'thread_detail_atoms.dart';
part 'thread_detail_card.dart';

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
    required this.onOpenAuthorProfile,
    required this.onOpenCommentAuthorProfile,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    this.onOpenPostImages,
    required this.onOpenPostActions,
    this.htmlFirstRenderMode = ThreadDetailHtmlFirstRenderMode.legacy,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    this.htmlImagePrecacheService,
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
  final ValueChanged<ThreadPost> onOpenAuthorProfile;
  final ValueChanged<ThreadPostCommentEntry> onOpenCommentAuthorProfile;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostActions;
  final ThreadDetailHtmlFirstRenderMode htmlFirstRenderMode;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ForumImagePrecacheService? htmlImagePrecacheService;
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
  ThreadHtmlImagePreloadCoordinator? _htmlImagePreloadCoordinator;
  String? _htmlImagePreloadSignature;

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
        !identical(oldWidget.imageDimensionStore, widget.imageDimensionStore) ||
        oldWidget.htmlFirstRenderMode != widget.htmlFirstRenderMode) {
      _entryPlanner = _createEntryPlanner();
    }
    if (!identical(
          oldWidget.htmlImagePrecacheService,
          widget.htmlImagePrecacheService,
        ) ||
        oldWidget.htmlFirstRenderMode != widget.htmlFirstRenderMode) {
      _resetHtmlImagePreload();
    }
    if (!identical(oldWidget.state.posts, widget.state.posts) ||
        oldWidget.state.currentPage != widget.state.currentPage) {
      _entryPlanner.prune(widget.state.posts);
      _resetHtmlImagePreload();
    }
  }

  @override
  void dispose() {
    widget.imageDimensionStore?.removeListener(_onImageDimensionsChanged);
    _htmlImagePreloadCoordinator?.dispose();
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
      renderMode: widget.htmlFirstRenderMode,
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
    _scheduleHtmlImageFirstWindowPreload(context);
    return ListView.builder(
      key: const Key('thread-detail-list'),
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      scrollCacheExtent: const ScrollCacheExtent.pixels(900),
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

  void _handlePostBuilt(int index) {
    widget.onPostBuilt?.call(index);
    if (!widget.htmlFirstRenderMode.isHtmlFirst) {
      return;
    }
    final coordinator = _htmlImageCoordinator();
    if (coordinator == null || widget.state.posts.isEmpty) {
      return;
    }
    unawaited(
      coordinator.preloadNearWindow(
        context: context,
        tid: widget.state.tid,
        posts: widget.state.posts,
        visiblePostIndex: index,
        planFor: _entryPlanner.planFor,
        expectedDisplaySize: _expectedImageDisplaySize(context),
      ),
    );
  }

  void _scheduleHtmlImageFirstWindowPreload(BuildContext context) {
    if (!widget.htmlFirstRenderMode.isHtmlFirst || widget.state.posts.isEmpty) {
      return;
    }
    final coordinator = _htmlImageCoordinator();
    if (coordinator == null) {
      return;
    }
    final signature =
        '${widget.state.tid}:${widget.state.currentPage}:${widget.state.posts.length}';
    if (_htmlImagePreloadSignature == signature) {
      return;
    }
    _htmlImagePreloadSignature = signature;
    unawaited(
      coordinator.preloadFirstWindow(
        context: context,
        tid: widget.state.tid,
        posts: widget.state.posts,
        planFor: _entryPlanner.planFor,
        expectedDisplaySize: _expectedImageDisplaySize(context),
      ),
    );
  }

  ThreadHtmlImagePreloadCoordinator? _htmlImageCoordinator() {
    final service = widget.htmlImagePrecacheService;
    if (service == null) {
      return null;
    }
    return _htmlImagePreloadCoordinator ??= ThreadHtmlImagePreloadCoordinator(
      precacheService: service,
    );
  }

  Size _expectedImageDisplaySize(BuildContext context) {
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final estimatedHorizontalPadding = 44.0;
    final width = mediaWidth - estimatedHorizontalPadding;
    return Size(width > 0 ? width : mediaWidth, double.nan);
  }

  void _resetHtmlImagePreload() {
    _htmlImagePreloadSignature = null;
    _htmlImagePreloadCoordinator?.reset();
  }

  Widget _buildEntry(
    BuildContext context,
    ThreadDetailRenderEntry entry,
    ThreadDetailNativePalette palette,
  ) {
    switch (entry.kind) {
      case ThreadDetailRenderEntryKind.postHeader:
        final plan = _entryPlanner.planFor(entry.post!);
        final header = _ThreadPostCardHeaderEntry(
          key: Key(entry.key),
          post: entry.post!,
          state: widget.state,
          plan: plan,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          palette: palette,
          onOpenAuthorProfile: widget.onOpenAuthorProfile,
          onOpenPostActions: widget.onOpenPostActions,
        );
        return _PostBuildObserver(
          index: entry.postIndex,
          onPostBuilt: _handlePostBuilt,
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
          imageReferer: widget.imageReferer,
          htmlFirstRenderMode: widget.htmlFirstRenderMode,
          palette: palette,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenPostImages: widget.onOpenPostImages,
          onHtmlFirstImageFallback: _copyHtmlFirstImageUrl,
          onOpenPostActions: widget.onOpenPostActions,
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
          onOpenPostActions: widget.onOpenPostActions,
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
        final plan = _entryPlanner.planFor(entry.post!);
        return _ThreadPostCardFooterEntry(
          key: Key(entry.key),
          post: entry.post!,
          state: widget.state,
          plan: plan,
          highlighted: entry.post!.pid == widget.highlightPostPid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          onOpenPostActions: widget.onOpenPostActions,
          onCopyActionUrl: widget.onCopyActionUrl,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenCommentAuthorProfile: widget.onOpenCommentAuthorProfile,
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

  void _copyHtmlFirstImageUrl(ThreadPost post, ForumHtmlImageRequest request) {
    widget.onCopyActionUrl('${post.number}# 图片', request.url);
  }
}
