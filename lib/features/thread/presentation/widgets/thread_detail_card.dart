part of 'thread_detail_widgets.dart';

// Post card widgets for thread detail: per-entry card segments (header/body/
// segment/footer), the post-build observer, ThreadPostCard, first-post summary,
// and post header. Moved verbatim from thread_detail_widgets.dart (Phase 5b
// file split); keys and logic unchanged.

class _ThreadPostCardHeaderEntry extends StatelessWidget {
  const _ThreadPostCardHeaderEntry({
    super.key,
    required this.post,
    required this.state,
    required this.plan,
    required this.highlighted,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onOpenAuthorProfile,
    required this.onOpenPostActions,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final ThreadPostBodyRenderPlan plan;
  final bool highlighted;
  final ThreadDetailNativePalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<ThreadPost> onOpenAuthorProfile;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostActions;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onOpenPostActions(post, plan),
      child: Container(
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
                  imageHeaderBuilder: imageHeaderBuilder,
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
                    repliesLabel: post.isFirst
                        ? state.replies.toString()
                        : null,
                    onOpenAuthorProfile: post.authorId.trim().isEmpty
                        ? null
                        : () => onOpenAuthorProfile(post),
                  ),
                ),
              ],
            ),
          ],
        ),
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
    required this.imageReferer,
    required this.palette,
    required this.onOpenPostLink,
    required this.onOpenPostImages,
    required this.onHtmlFirstImageFallback,
    required this.onHtmlFirstImageLayoutShift,
    required this.onHtmlFirstImageFallbackAspectRatio,
    required this.onHtmlFirstBlockImageResolved,
    required this.onOpenPostActions,
  });

  final ThreadPost post;
  final String threadId;
  final ThreadPostBodyRenderPlan plan;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String imageReferer;
  final ThreadDetailNativePalette palette;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final ThreadPostHtmlFirstImageFallback onHtmlFirstImageFallback;
  final void Function(ForumHtmlImageLayoutShift shift)
  onHtmlFirstImageLayoutShift;
  final double? Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
  )
  onHtmlFirstImageFallbackAspectRatio;
  final void Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )
  onHtmlFirstBlockImageResolved;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostActions;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onOpenPostActions(post, plan),
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
          child: ThreadPostHtmlBody(
            post: post,
            threadId: threadId,
            imageReferer: imageReferer,
            plan: plan,
            imageHeaderBuilder: imageHeaderBuilder,
            onOpenPostLink: onOpenPostLink,
            onOpenPostImage: onOpenPostImages == null
                ? null
                : (post, request) => onOpenPostImages!.call(post, request),
            theme: const ForumHtmlRenderThemeFactory().fromThreadPalette(
              palette: palette,
              brightness: Theme.of(context).brightness,
            ),
            onImageFallback: onHtmlFirstImageFallback,
            onImageLayoutShift: onHtmlFirstImageLayoutShift,
            imageFallbackAspectRatioFor: (spec, request) =>
                onHtmlFirstImageFallbackAspectRatio(post, spec, request),
            onBlockImageResolved: (spec, request, size) =>
                onHtmlFirstBlockImageResolved(post, spec, request, size),
          ),
        ),
      ),
    );
  }
}

class _ThreadPostCardFooterEntry extends StatelessWidget {
  const _ThreadPostCardFooterEntry({
    super.key,
    required this.post,
    required this.state,
    required this.plan,
    required this.highlighted,
    required this.imageHeaderBuilder,
    required this.onOpenPostActions,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    required this.onOpenCommentAuthorProfile,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
    required this.palette,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final ThreadPostBodyRenderPlan plan;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostActions;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<String> onOpenPostLink;
  final ValueChanged<ThreadPostCommentEntry> onOpenCommentAuthorProfile;
  final void Function(ThreadPoll poll, ThreadPollOption option)
  onTogglePollOption;
  final ValueChanged<ThreadPoll> onSubmitPollVote;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final hasFooterContent =
        post.poll != null ||
        post.comments.isNotEmpty ||
        post.ratingSummary != null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onOpenPostActions(post, plan),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.fromLTRB(10, hasFooterContent ? 10 : 0, 10, 10),
        decoration: _cardSegmentDecoration(
          palette: palette,
          highlighted: highlighted,
          position: _ThreadPostCardSegmentPosition.footer,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            ],
            if (post.comments.isNotEmpty) ...[
              if (post.poll != null) const SizedBox(height: 10),
              ThreadPostCommentSection(
                comments: post.comments,
                imageHeaderBuilder: imageHeaderBuilder,
                palette: palette,
                onOpenAuthorProfile: onOpenCommentAuthorProfile,
              ),
            ],
            if (post.ratingSummary != null) ...[
              if (post.poll != null || post.comments.isNotEmpty)
                const SizedBox(height: 10),
              ThreadPostRatingSection(
                summary: post.ratingSummary!,
                palette: palette,
                onCopyActionUrl: onCopyActionUrl,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThreadPostCardEntry extends StatefulWidget {
  const _ThreadPostCardEntry({
    super.key,
    required this.post,
    required this.postIndex,
    required this.state,
    required this.plan,
    required this.highlighted,
    required this.imageHeaderBuilder,
    required this.imageReferer,
    required this.palette,
    required this.onOpenAuthorProfile,
    required this.onOpenPostLink,
    required this.onOpenPostImages,
    required this.onHtmlFirstImageFallback,
    required this.onHtmlFirstImageLayoutShift,
    required this.onHtmlFirstImageFallbackAspectRatio,
    required this.onHtmlFirstBlockImageResolved,
    required this.onOpenPostActions,
    required this.onCopyActionUrl,
    required this.onOpenCommentAuthorProfile,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
    required this.onPostBuilt,
  });

  final ThreadPost post;
  final int postIndex;
  final ThreadDetailPageState state;
  final ThreadPostBodyRenderPlan plan;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String imageReferer;
  final ThreadDetailNativePalette palette;
  final ValueChanged<ThreadPost> onOpenAuthorProfile;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final ThreadPostHtmlFirstImageFallback onHtmlFirstImageFallback;
  final void Function(ForumHtmlImageLayoutShift shift)
  onHtmlFirstImageLayoutShift;
  final double? Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
  )
  onHtmlFirstImageFallbackAspectRatio;
  final void Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )
  onHtmlFirstBlockImageResolved;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)
  onOpenPostActions;
  final void Function(String label, String url) onCopyActionUrl;
  final ValueChanged<ThreadPostCommentEntry> onOpenCommentAuthorProfile;
  final void Function(ThreadPoll poll, ThreadPollOption option)
  onTogglePollOption;
  final ValueChanged<ThreadPoll> onSubmitPollVote;
  final ValueChanged<int>? onPostBuilt;

  @override
  State<_ThreadPostCardEntry> createState() => _ThreadPostCardEntryState();
}

class _ThreadPostCardEntryState extends State<_ThreadPostCardEntry>
    with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    _scheduleNotify();
  }

  @override
  void didUpdateWidget(covariant _ThreadPostCardEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.pid != widget.post.pid ||
        oldWidget.postIndex != widget.postIndex ||
        oldWidget.onPostBuilt != widget.onPostBuilt) {
      _scheduleNotify();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThreadPostCardHeaderEntry(
          key: Key('thread-post-header-${widget.post.pid}'),
          post: widget.post,
          state: widget.state,
          plan: widget.plan,
          highlighted: widget.highlighted,
          palette: widget.palette,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          onOpenAuthorProfile: widget.onOpenAuthorProfile,
          onOpenPostActions: widget.onOpenPostActions,
        ),
        _ThreadPostCardBodyEntry(
          key: Key('thread-post-body-${widget.post.pid}'),
          post: widget.post,
          threadId: widget.state.tid,
          plan: widget.plan,
          highlighted: widget.highlighted,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          imageReferer: widget.imageReferer,
          palette: widget.palette,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenPostImages: widget.onOpenPostImages,
          onHtmlFirstImageFallback: widget.onHtmlFirstImageFallback,
          onHtmlFirstImageLayoutShift: widget.onHtmlFirstImageLayoutShift,
          onHtmlFirstImageFallbackAspectRatio:
              widget.onHtmlFirstImageFallbackAspectRatio,
          onHtmlFirstBlockImageResolved: widget.onHtmlFirstBlockImageResolved,
          onOpenPostActions: widget.onOpenPostActions,
        ),
        _ThreadPostCardFooterEntry(
          key: Key('thread-post-footer-${widget.post.pid}'),
          post: widget.post,
          state: widget.state,
          plan: widget.plan,
          highlighted: widget.highlighted,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          onOpenPostActions: widget.onOpenPostActions,
          onCopyActionUrl: widget.onCopyActionUrl,
          onOpenPostLink: widget.onOpenPostLink,
          onOpenCommentAuthorProfile: widget.onOpenCommentAuthorProfile,
          onTogglePollOption: widget.onTogglePollOption,
          onSubmitPollVote: widget.onSubmitPollVote,
          palette: widget.palette,
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  void _scheduleNotify() {
    final callback = widget.onPostBuilt;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        callback(widget.postIndex);
      }
    });
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
/// The production native thread detail page uses [_ThreadPostCardEntry] so it
/// can reuse the shared render plan cache and HTML-first image callbacks.
class ThreadPostCard extends StatelessWidget {
  const ThreadPostCard({
    super.key,
    required this.post,
    this.state,
    this.highlighted = false,
    required this.imageHeaderBuilder,
    this.onOpenAuthorProfile,
    this.onCopyActionUrl,
    this.onOpenPostLink,
    this.onOpenPostImages,
    this.onTogglePollOption,
    this.onSubmitPollVote,
    required this.palette,
    this.onOpenCommentAuthorProfile,
    this.onOpenPostActions,
    this.interactionPolicy = const ThreadPostCardInteractionPolicy.full(),
    this.renderContext,
  });

  final ThreadPost post;
  final ThreadDetailPageState? state;
  final bool highlighted;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<ThreadPost>? onOpenAuthorProfile;
  final void Function(String label, String url)? onCopyActionUrl;
  final ValueChanged<String>? onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImages;
  final void Function(ThreadPoll poll, ThreadPollOption option)?
  onTogglePollOption;
  final ValueChanged<ThreadPoll>? onSubmitPollVote;
  final ThreadDetailNativePalette palette;
  final ValueChanged<ThreadPostCommentEntry>? onOpenCommentAuthorProfile;
  final void Function(ThreadPost post, ThreadPostBodyRenderPlan plan)?
  onOpenPostActions;
  final ThreadPostCardInteractionPolicy interactionPolicy;
  final ThreadPostRenderContext? renderContext;

  @override
  Widget build(BuildContext context) {
    final renderContext = this.renderContext;
    final detailState = state;
    final resolvedPalette = renderContext?.palette ?? palette;
    final renderOwner = renderContext?.renderOwnerFor(post) ?? detailState?.tid;
    final threadId = renderOwner == null || renderOwner.trim().isEmpty
        ? post.pid
        : renderOwner;
    final imageReferer =
        renderContext?.imageRefererFor(post) ?? detailState?.desktopUrl ?? '';
    final resolvedImageHeaderBuilder =
        renderContext?.imageHeaderBuilder ?? imageHeaderBuilder;
    final plan =
        renderContext?.planFor(post) ??
        const ThreadPostBodyRenderPlanner().plan(post.message);
    final authorProfileCallback = interactionPolicy.allowAuthorProfile
        ? onOpenAuthorProfile
        : null;
    final postActionCallback = interactionPolicy.allowPostActions
        ? onOpenPostActions
        : null;
    final commentAuthorProfileCallback =
        interactionPolicy.allowCommentAuthorProfile
        ? onOpenCommentAuthorProfile
        : null;
    final imageOpenCallback = interactionPolicy.allowImageOpen
        ? onOpenPostImages
        : null;
    final linkCallback = interactionPolicy.allowPostLinks
        ? (onOpenPostLink ?? _ignoreLink)
        : _ignoreLink;
    ThreadPostHtmlFirstImageFallback? imageFallback;
    if (interactionPolicy.allowImageFallbackCopy && onCopyActionUrl != null) {
      imageFallback = (post, request) {
        onCopyActionUrl?.call('${post.number}# 图片', request.url);
      };
    }
    final card = Container(
      key: Key('thread-post-card-${post.pid}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: highlighted
          ? _highlightedCardDecoration(resolvedPalette)
          : _cardDecoration(resolvedPalette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isFirst && detailState != null) ...[
            _FirstPostThreadSummary(
              state: detailState,
              palette: resolvedPalette,
            ),
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
                palette: resolvedPalette,
                imageHeaderBuilder: resolvedImageHeaderBuilder,
                onTap:
                    post.authorId.trim().isEmpty ||
                        authorProfileCallback == null
                    ? null
                    : () => authorProfileCallback(post),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _PostHeader(
                  post: post,
                  palette: resolvedPalette,
                  viewsLabel: post.isFirst && detailState != null
                      ? detailState.views.toString()
                      : null,
                  repliesLabel: post.isFirst && detailState != null
                      ? detailState.replies.toString()
                      : null,
                  onOpenAuthorProfile:
                      post.authorId.trim().isEmpty ||
                          authorProfileCallback == null
                      ? null
                      : () => authorProfileCallback(post),
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
            child: ThreadPostHtmlBody(
              key: Key('thread-post-${post.pid}'),
              post: post,
              threadId: threadId,
              imageReferer: imageReferer,
              plan: plan,
              imageHeaderBuilder: resolvedImageHeaderBuilder,
              onOpenPostLink: linkCallback,
              onOpenPostImage: imageOpenCallback,
              theme: const ForumHtmlRenderThemeFactory().fromThreadPalette(
                palette: resolvedPalette,
                brightness: Theme.of(context).brightness,
              ),
              onImageFallback: imageFallback,
              onImageDiagnostics: renderContext?.onImageDiagnostics,
              onImageLayoutShift: renderContext?.onImageLayoutShift,
              imageFallbackAspectRatioFor:
                  renderContext?.imageFallbackAspectRatioFor == null
                  ? null
                  : (spec, request) =>
                        renderContext!.imageFallbackAspectRatioFor!(
                          post,
                          spec,
                          request,
                        ),
              onBlockImageResolved: renderContext?.onBlockImageResolved == null
                  ? null
                  : (spec, request, size) =>
                        renderContext!.onBlockImageResolved!(
                          post,
                          spec,
                          request,
                          size,
                        ),
            ),
          ),
          if (post.poll != null && interactionPolicy.showPoll) ...[
            const SizedBox(height: 10),
            ThreadPollCard(
              poll: post.poll!,
              selectedOptionIds:
                  detailState?.selectedPollOptionIds ?? const <String>{},
              isSubmitting: detailState?.isPollVoteSubmitting ?? false,
              hint: detailState?.pollVoteHint,
              onToggleOption: (option) =>
                  onTogglePollOption?.call(post.poll!, option),
              onSubmit: () => onSubmitPollVote?.call(post.poll!),
              palette: resolvedPalette,
            ),
          ],
          if (post.comments.isNotEmpty && interactionPolicy.showComments) ...[
            const SizedBox(height: 10),
            ThreadPostCommentSection(
              comments: post.comments,
              imageHeaderBuilder: resolvedImageHeaderBuilder,
              palette: resolvedPalette,
              onOpenAuthorProfile: commentAuthorProfileCallback,
            ),
          ],
          if (post.ratingSummary != null && interactionPolicy.showRating) ...[
            const SizedBox(height: 10),
            ThreadPostRatingSection(
              summary: post.ratingSummary!,
              palette: resolvedPalette,
              onCopyActionUrl: onCopyActionUrl ?? (_, _) {},
            ),
          ],
        ],
      ),
    );
    final openActions = postActionCallback;
    if (openActions == null) {
      return card;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => openActions(post, plan),
      child: card,
    );
  }

  static void _ignoreLink(String _) {}
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
