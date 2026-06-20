import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
import 'package:y300/shared/widgets/shelf/candidate_shelf_action_row.dart';

class ThreadDetailContent extends StatelessWidget {
  const ThreadDetailContent({
    super.key,
    required this.state,
    required this.imageHeaderBuilder,
    required this.sourceTagLabel,
    required this.onLoadMore,
    required this.onAddComicToShelf,
    required this.onAddNovelToShelf,
  });

  final ThreadDetailPageState state;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String sourceTagLabel;
  final VoidCallback onLoadMore;
  final VoidCallback onAddComicToShelf;
  final VoidCallback onAddNovelToShelf;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return ListView.builder(
      key: const Key('thread-detail-list'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      itemCount: state.posts.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ThreadDetailHeaderCard(state: state, palette: palette);
        }
        if (index == state.posts.length + 1) {
          return ThreadLoadMoreSection(
            hasMore: state.hasMore,
            isLoadingMore: state.isLoadingMore,
            currentPage: state.currentPage <= 0 ? 1 : state.currentPage,
            onLoadMore: onLoadMore,
            palette: palette,
          );
        }

        final post = state.posts[index - 1];
        final postCard = ThreadPostCard(
          post: post,
          state: state,
          sourceTagLabel: sourceTagLabel,
          imageHeaderBuilder: imageHeaderBuilder,
          onAddComicToShelf: onAddComicToShelf,
          onAddNovelToShelf: onAddNovelToShelf,
          palette: palette,
        );
        if (post.isFirst && state.posts.length > 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              postCard,
              ThreadRepliesHeader(state: state, palette: palette),
            ],
          );
        }
        return postCard;
      },
    );
  }
}

class ThreadDetailHeaderCard extends StatelessWidget {
  const ThreadDetailHeaderCard({
    super.key,
    required this.state,
    required this.palette,
  });

  final ThreadDetailPageState state;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final typeName = state.typeName?.trim();
    final pageText = state.lastPage == null || state.lastPage! <= 1
        ? '第 ${state.currentPage <= 0 ? 1 : state.currentPage} 页'
        : '第 ${state.currentPage} / ${state.lastPage} 页';

    return Container(
      key: const Key('thread-detail-header-card'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typeName != null && typeName.isNotEmpty) ...[
            ThreadPill(label: typeName, palette: palette, emphasized: true),
            const SizedBox(height: 8),
          ],
          Text(
            state.subject.isNotEmpty ? state.subject : '帖子详情',
            style: textTheme.titleMedium?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ThreadMetricPill(
                icon: Icons.visibility_outlined,
                label: state.views.toString(),
                palette: palette,
              ),
              ThreadMetricPill(
                icon: Icons.forum_outlined,
                label: state.replies.toString(),
                palette: palette,
              ),
              ThreadPill(label: pageText, palette: palette),
            ],
          ),
        ],
      ),
    );
  }
}

class ThreadRepliesHeader extends StatelessWidget {
  const ThreadRepliesHeader({
    super.key,
    required this.state,
    required this.palette,
  });

  final ThreadDetailPageState state;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final currentPage = state.currentPage <= 0 ? 1 : state.currentPage;
    final pageLabel = state.lastPage == null || state.lastPage! <= 1
        ? '第 $currentPage 页'
        : '第 $currentPage / ${state.lastPage} 页';
    return Container(
      key: const Key('thread-replies-header'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.metricBackground.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            '全部回复',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            state.replies.toString(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.author,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (state.reverseOrderUrl?.trim().isNotEmpty == true) ...[
            ThreadReplyHeaderAction(label: '倒序浏览', palette: palette),
            const SizedBox(width: 6),
          ],
          if (state.onlyAuthorUrl?.trim().isNotEmpty == true) ...[
            ThreadReplyHeaderAction(label: '只看楼主', palette: palette),
            const SizedBox(width: 6),
          ],
          Text(
            pageLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.softText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ThreadReplyHeaderAction extends StatelessWidget {
  const ThreadReplyHeaderAction({
    super.key,
    required this.label,
    required this.palette,
  });

  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ThreadPostCard extends StatelessWidget {
  const ThreadPostCard({
    super.key,
    required this.post,
    required this.state,
    required this.sourceTagLabel,
    required this.imageHeaderBuilder,
    required this.onAddComicToShelf,
    required this.onAddNovelToShelf,
    required this.palette,
  });

  final ThreadPost post;
  final ThreadDetailPageState state;
  final String sourceTagLabel;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final VoidCallback onAddComicToShelf;
  final VoidCallback onAddNovelToShelf;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final showComicEntry =
        post.isFirst && state.contentKind == ThreadContentKind.comic;
    final showNovelEntry =
        post.isFirst && state.contentKind == ThreadContentKind.novel;

    return Container(
      key: Key('thread-post-card-${post.pid}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: _cardDecoration(palette),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThreadAuthorAvatar(
            author: post.author,
            avatarUrl: post.avatarUrl,
            palette: palette,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PostHeader(post: post, palette: palette),
                if (showComicEntry) ...[
                  const SizedBox(height: 8),
                  CandidateShelfActionRow(
                    label: '漫画 · $sourceTagLabel',
                    inShelf: state.isInShelf,
                    isLoading: state.isComicActionLoading,
                    onPressed: onAddComicToShelf,
                  ),
                ],
                if (showNovelEntry) ...[
                  const SizedBox(height: 8),
                  CandidateShelfActionRow(
                    label: '小说 · $sourceTagLabel',
                    inShelf: state.isNovelInShelf,
                    isLoading: state.isNovelActionLoading,
                    onPressed: onAddNovelToShelf,
                  ),
                ],
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
                  ),
                ),
                if (post.poll != null) ...[
                  const SizedBox(height: 10),
                  ThreadPollCard(poll: post.poll!, palette: palette),
                ],
                if (post.rateSummary?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  ThreadPill(
                    label: '评分 ${post.rateSummary!.trim()}',
                    palette: palette,
                  ),
                ],
                const SizedBox(height: 10),
                ThreadPostActionRow(post: post, palette: palette),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post, required this.palette});

  final ThreadPost post;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author.isNotEmpty ? post.author : '匿名',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  color: palette.author,
                  fontWeight: FontWeight.w800,
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
        ThreadPill(label: '${post.number}#', palette: palette),
      ],
    );
  }
}

class ThreadPostActionRow extends StatelessWidget {
  const ThreadPostActionRow({
    super.key,
    required this.post,
    required this.palette,
  });

  final ThreadPost post;
  final ThreadDetailNativePalette palette;

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
          ),
        if (post.commentUrl?.trim().isNotEmpty == true)
          ThreadActionChip(
            label: '点评',
            icon: Icons.chat_bubble_outline,
            palette: palette,
          ),
        ThreadActionChip(
          label: '回复',
          icon: Icons.reply_outlined,
          palette: palette,
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
  });

  final String label;
  final IconData icon;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.metricBackground.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(9),
      ),
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
    );
  }
}

class ThreadPollCard extends StatelessWidget {
  const ThreadPollCard({super.key, required this.poll, required this.palette});

  final ThreadPoll poll;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('thread-poll-card'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.metricBackground.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.summary,
            style: textTheme.labelLarge?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
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
            ThreadPollOptionTile(option: option, palette: palette),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('thread-poll-submit-button'),
              onPressed: null,
              child: const Text('提交'),
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
  });

  final ThreadPollOption option;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final percent = option.percent;
    final color = _parseColor(option.colorHex) ?? palette.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.radio_button_unchecked,
              size: 15,
              color: palette.softText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                option.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.bodyText,
                  fontWeight: FontWeight.w600,
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
  });

  final String author;
  final String? avatarUrl;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim();
    return CircleAvatar(
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
        color: palette.metricBackground,
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
            : palette.metricBackground.withValues(alpha: 0.72),
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
    required this.onLoadMore,
    required this.palette,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final int currentPage;
  final VoidCallback onLoadMore;
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
            onPressed: null,
            child: const Text('上一页'),
          ),
          const SizedBox(width: 6),
          Container(
            key: const Key('thread-detail-current-page-button'),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.metricBackground.withValues(alpha: 0.64),
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
            onPressed: hasMore ? onLoadMore : null,
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
    boxShadow: [
      BoxShadow(
        color: palette.stateLayer.withValues(alpha: 0.42),
        blurRadius: 7,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

String _authorInitial(String author) {
  final text = author.trim();
  if (text.isEmpty) {
    return '?';
  }
  return text.characters.first.toUpperCase();
}
