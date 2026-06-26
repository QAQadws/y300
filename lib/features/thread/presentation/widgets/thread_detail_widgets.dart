import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ThreadDetailContent extends StatelessWidget {
  const ThreadDetailContent({
    super.key,
    required this.state,
    this.scrollController,
    this.highlightPostPid,
    this.targetPid,
    required this.imageHeaderBuilder,
    required this.sourceTagLabel,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onOpenPostReply,
    required this.onOpenPostRate,
    required this.onOpenPostComment,
    required this.onOpenAuthorProfile,
    required this.onCopyActionUrl,
    required this.onOpenPostLink,
    this.onOpenPostImages,
    required this.onTogglePollOption,
    required this.onSubmitPollVote,
  });

  final ThreadDetailPageState state;
  final ScrollController? scrollController;
  final String? highlightPostPid;
  final String? targetPid;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String sourceTagLabel;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
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

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final hasTargetPost = targetPid?.trim().isNotEmpty == true;
    return ListView.builder(
      key: const Key('thread-detail-list'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      cacheExtent: 900,
      itemCount: state.posts.length + (hasTargetPost ? 2 : 1),
      itemBuilder: (context, index) {
        if (index == state.posts.length) {
          return ThreadLoadMoreSection(
            hasMore: state.hasMore,
            isLoadingMore: state.isLoadingMore,
            currentPage: state.currentPage <= 0 ? 1 : state.currentPage,
            canLoadPrevious: state.currentPage > 1,
            onLoadPreviousPage: onLoadPreviousPage,
            onLoadNextPage: onLoadNextPage,
            palette: palette,
          );
        }
        if (hasTargetPost && index == state.posts.length + 1) {
          return SizedBox(
            key: const Key('thread-detail-target-scroll-spacer'),
            height: MediaQuery.sizeOf(context).height * 0.72,
          );
        }

        final post = state.posts[index];
        final postCard = ThreadPostCard(
          post: post,
          state: state,
          highlighted: post.pid == highlightPostPid,
          sourceTagLabel: sourceTagLabel,
          imageHeaderBuilder: imageHeaderBuilder,
          onOpenPostReply: onOpenPostReply,
          onOpenPostRate: onOpenPostRate,
          onOpenPostComment: onOpenPostComment,
          onOpenAuthorProfile: onOpenAuthorProfile,
          onCopyActionUrl: onCopyActionUrl,
          onOpenPostLink: onOpenPostLink,
          onOpenPostImages: onOpenPostImages,
          onTogglePollOption: onTogglePollOption,
          onSubmitPollVote: onSubmitPollVote,
          palette: palette,
        );
        return postCard;
      },
    );
  }
}

class ThreadPostCard extends StatelessWidget {
  const ThreadPostCard({
    super.key,
    required this.post,
    required this.state,
    this.highlighted = false,
    required this.sourceTagLabel,
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
  final String sourceTagLabel;
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

class ThreadPostCommentSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('thread-post-comment-section'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              Text(
                '点评',
                style: textTheme.labelLarge?.copyWith(
                  color: palette.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (var index = 0; index < comments.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: palette.outlineSoft,
                ),
              ),
            ThreadPostCommentRow(
              comment: comments[index],
              imageHeaderBuilder: imageHeaderBuilder,
              palette: palette,
            ),
          ],
        ],
      ),
    );
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
            : LibraryCachedImage(
                imageUrl: imageUrl,
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

class ThreadPostRatingSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('thread-post-rating-section'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_outline, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              Text(
                '评分',
                style: textTheme.labelLarge?.copyWith(
                  color: palette.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  summary.participantText.isEmpty
                      ? '参与人数'
                      : summary.participantText,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  summary.scoreText.isEmpty ? '积分' : summary.scoreText,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '理由',
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          for (final rating in summary.ratings) ...[
            const SizedBox(height: 6),
            ThreadPostRatingRow(rating: rating, palette: palette),
          ],
          if (summary.viewAllUrl?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: ThreadRatingLinkButton(
                label: '查看全部评分',
                palette: palette,
                onPressed: () => onCopyActionUrl('查看全部评分', summary.viewAllUrl!),
              ),
            ),
          ],
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

class ThreadPollCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        poll.canVote &&
        selectedOptionIds.isNotEmpty &&
        !isSubmitting &&
        (poll.actionUrl?.trim().isNotEmpty ?? false);
    final statusText = poll.statusText?.trim();
    return Container(
      key: const Key('thread-poll-card'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.summary,
            style: textTheme.labelLarge?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (poll.deadlineText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Text(
              poll.deadlineText!.trim(),
              style: textTheme.labelSmall?.copyWith(color: palette.muted),
            ),
          ],
          const SizedBox(height: 9),
          for (final option in poll.options) ...[
            ThreadPollOptionTile(
              option: option,
              palette: palette,
              isMultipleChoice: poll.isMultipleChoice,
              showSelector: poll.canVote,
              selected: selectedOptionIds.contains(option.id),
              enabled: poll.canVote && !isSubmitting,
              onTap: () => onToggleOption(option),
            ),
            const SizedBox(height: 8),
          ],
          if (statusText != null && statusText.isNotEmpty) ...[
            Text(
              statusText,
              key: const Key('thread-poll-status-text'),
              style: textTheme.labelSmall?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (hint?.trim().isNotEmpty == true) ...[
            Text(
              hint!.trim(),
              key: const Key('thread-poll-vote-hint'),
              style: textTheme.labelSmall?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (poll.canVote)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('thread-poll-submit-button'),
                onPressed: canSubmit ? onSubmit : null,
                child: isSubmitting
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
    required this.avatarUrl,
    required this.palette,
    this.onTap,
  });

  final String author;
  final String? avatarUrl;
  final ThreadDetailNativePalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim();
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: palette.avatarBackground,
      foregroundColor: palette.avatarForeground,
      backgroundImage: imageUrl == null || imageUrl.isEmpty
          ? null
          : NetworkImage(imageUrl),
      child: imageUrl == null || imageUrl.isEmpty
          ? Text(
              _authorInitial(author),
              style: const TextStyle(fontWeight: FontWeight.w800),
            )
          : null,
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
    required this.canLoadPrevious,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.palette,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final int currentPage;
  final bool canLoadPrevious;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
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
          TextButton(
            key: const Key('thread-detail-previous-page-button'),
            onPressed: canLoadPrevious ? onLoadPreviousPage : null,
            child: const Text('上一页'),
          ),
          const SizedBox(width: 6),
          Container(
            key: const Key('thread-detail-current-page-button'),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.chipBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '第 $currentPage 页',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: const Key('thread-detail-load-more-button'),
            onPressed: hasMore ? onLoadNextPage : null,
            child: Text(hasMore ? '下一页' : '没有更多'),
          ),
        ],
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

String _authorInitial(String author) {
  final text = author.trim();
  if (text.isEmpty) {
    return '?';
  }
  return text.characters.first.toUpperCase();
}
