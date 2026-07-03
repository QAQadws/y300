part of 'thread_detail_widgets.dart';

// Post footer widgets: comment section, rating section, and tag links.

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
