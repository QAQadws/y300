import 'package:flutter/material.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_metric_pill.dart';

class BlogDetailHeader extends StatelessWidget {
  const BlogDetailHeader({
    super.key,
    required this.author,
    this.viewCount,
    this.commentCount,
  });

  final Widget author;
  final int? viewCount;
  final int? commentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ThreadDetailNativePalette.resolve(theme);
    final l10n = AppLocalizations.of(context);
    final metrics = [
      if (viewCount != null)
        (
          key: const Key('blog-detail-views'),
          icon: Icons.visibility_outlined,
          count: viewCount!,
          description: l10n.profileBlogViews(viewCount!),
        ),
      if (commentCount != null)
        (
          key: const Key('blog-detail-comment-count'),
          icon: Icons.forum_outlined,
          count: commentCount!,
          description: l10n.profileBlogCommentCount(commentCount!),
        ),
    ];
    if (metrics.isEmpty) return author;

    final textScaler = MediaQuery.textScalerOf(context);
    var metricsWidth = (metrics.length - 1) * 6.0;
    for (final metric in metrics) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${metric.count}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      metricsWidth += 16 + 14 + 4 + painter.width;
      painter.dispose();
    }
    final statistics = Wrap(
      spacing: 6,
      runSpacing: 5,
      alignment: WrapAlignment.end,
      children: [
        for (final metric in metrics)
          ForumMetricPill(
            key: metric.key,
            icon: metric.icon,
            label: '${metric.count}',
            semanticsLabel: metric.description,
            backgroundColor: palette.chipBackground,
            iconColor: palette.softText,
            textColor: palette.muted,
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the author and date readable when large text or counts leave
        // too little room for the normal, right-aligned statistics.
        if (constraints.maxWidth - metricsWidth - 8 < textScaler.scale(144)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              author,
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: statistics,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: author),
            const SizedBox(width: 8),
            statistics,
          ],
        );
      },
    );
  }
}
