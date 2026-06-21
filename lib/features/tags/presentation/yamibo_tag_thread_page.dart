import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class YamiboTagThreadPage extends ConsumerWidget {
  const YamiboTagThreadPage({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = YamiboTagThreadPageArgs(url: url, title: title);
    final asyncState = ref.watch(yamiboTagThreadPageControllerProvider(args));
    final controller = ref.read(
      yamiboTagThreadPageControllerProvider(args).notifier,
    );
    final state = asyncState.value ?? YamiboTagThreadPageState.initial(args);
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    final data = state.data;

    return Scaffold(
      key: const Key('yamibo-tag-thread-page'),
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(
          data?.tagName.trim().isNotEmpty == true
              ? data!.tagName
              : (state.title.trim().isNotEmpty ? state.title : '标签'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: asyncState.isLoading && data == null
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? _TagPageErrorView(
              message: state.errorMessage ?? '标签页加载失败',
              onRetry: controller.refresh,
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                key: const Key('yamibo-tag-thread-list'),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                children: [
                  _TagHeaderCard(data: data, palette: palette),
                  const SizedBox(height: 10),
                  if (state.errorMessage?.trim().isNotEmpty == true)
                    _InlineError(
                      message: state.errorMessage!,
                      palette: palette,
                    ),
                  if (data.threads.isEmpty)
                    _EmptyTagThreadList(palette: palette)
                  else
                    for (final thread in data.threads)
                      _TagThreadCard(
                        thread: thread,
                        palette: palette,
                        onTap: () => _openThread(context, thread),
                      ),
                  _TagPager(
                    data: data,
                    isLoading: state.isLoadingPage,
                    palette: palette,
                    onOpenUrl: controller.loadUrl,
                  ),
                ],
              ),
            ),
    );
  }

  void _openThread(BuildContext context, YamiboTagThreadItem thread) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: thread.tid, subject: thread.subject),
      ),
    );
  }
}

class _TagHeaderCard extends StatelessWidget {
  const _TagHeaderCard({required this.data, required this.palette});

  final YamiboTagThreadPageData data;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final page = data.pagination.currentPage;
    final total = data.pagination.totalPages;
    final pageLabel = page == null
        ? '${data.threads.length} 个相关帖子'
        : total == null
        ? '第 $page 页'
        : '第 $page / $total 页';
    return Container(
      key: const Key('yamibo-tag-header-card'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: _tagCardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sell_outlined, size: 18, color: palette.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  data.tagName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.title,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _TagMetricPill(label: pageLabel, palette: palette),
              if (data.tagId.trim().isNotEmpty)
                _TagMetricPill(label: 'id=${data.tagId}', palette: palette),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagThreadCard extends StatelessWidget {
  const _TagThreadCard({
    required this.thread,
    required this.palette,
    required this.onTap,
  });

  final YamiboTagThreadItem thread;
  final ForumDisplayThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final metrics = <String>[
      if (thread.replyCount != null) '回复 ${thread.replyCount}',
      if (thread.viewCount != null) '查看 ${thread.viewCount}',
    ].join(' · ');
    final authorLine = <String>[
      if (thread.authorName?.trim().isNotEmpty == true) thread.authorName!,
      if (thread.createdAt?.trim().isNotEmpty == true) thread.createdAt!,
    ].join(' · ');
    final lastPostLine = <String>[
      if (thread.lastPosterName?.trim().isNotEmpty == true)
        thread.lastPosterName!,
      if (thread.lastPostAt?.trim().isNotEmpty == true) thread.lastPostAt!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: _tagCardDecoration(palette),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('yamibo-tag-thread-${thread.tid}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        thread.subject,
                        style: textTheme.titleSmall?.copyWith(
                          color: palette.threadTitle,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (thread.hasImageAttachment) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: palette.softText,
                      ),
                    ],
                  ],
                ),
                if (authorLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    authorLine,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.author,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [
                    if (thread.forumName?.trim().isNotEmpty == true)
                      Flexible(
                        child: _TagMetricPill(
                          label: thread.forumName!,
                          palette: palette,
                        ),
                      ),
                    if (metrics.isNotEmpty) ...[
                      const SizedBox(width: 7),
                      _TagMetricPill(label: metrics, palette: palette),
                    ],
                  ],
                ),
                if (lastPostLine.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    '最后发表 $lastPostLine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.softText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPager extends StatelessWidget {
  const _TagPager({
    required this.data,
    required this.isLoading,
    required this.palette,
    required this.onOpenUrl,
  });

  final YamiboTagThreadPageData data;
  final bool isLoading;
  final ForumDisplayThemePalette palette;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final previous = data.pagination.previousPageUrl;
    final next = data.pagination.nextPageUrl ?? data.moreUrl;
    if (previous == null && next == null && !isLoading) {
      return const SizedBox(height: 8);
    }
    return Padding(
      key: const Key('yamibo-tag-pager'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            key: const Key('yamibo-tag-previous-page-button'),
            onPressed: previous == null || isLoading
                ? null
                : () => onOpenUrl(previous),
            child: const Text('上一页'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const Key('yamibo-tag-next-page-button'),
            onPressed: next == null || isLoading ? null : () => onOpenUrl(next),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(next == data.moreUrl ? '更多' : '下一页'),
          ),
        ],
      ),
    );
  }
}

class _TagMetricPill extends StatelessWidget {
  const _TagMetricPill({required this.label, required this.palette});

  final String label;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.metricBackground.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.muted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.palette});

  final String message;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: palette.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyTagThreadList extends StatelessWidget {
  const _EmptyTagThreadList({required this.palette});

  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('yamibo-tag-empty'),
      padding: const EdgeInsets.all(18),
      decoration: _tagCardDecoration(palette),
      child: Text(
        '暂无相关帖子',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TagPageErrorView extends StatelessWidget {
  const _TagPageErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('yamibo-tag-retry-button'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _tagCardDecoration(ForumDisplayThemePalette palette) {
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: palette.stateLayer.withValues(alpha: 0.34),
        blurRadius: 7,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
