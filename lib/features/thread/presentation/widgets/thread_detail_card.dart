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

