import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/shared/widgets/app_skeleton.dart';

class ForumDisplayPage extends ConsumerWidget {
  const ForumDisplayPage({super.key, required this.fid, this.title = ''});

  final String fid;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ForumDisplayArgs(fid: fid, title: title);
    final asyncState = ref.watch(forumDisplayControllerProvider(args));
    final controller = ref.read(forumDisplayControllerProvider(args).notifier);
    final state = asyncState.value ?? ForumDisplayPageState.initial(fid: fid, title: title);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.title.isNotEmpty ? state.title : '帖子列表'),
        actions: [
          if (fid == '30')
            IconButton(
              key: const Key('forum-display-search-button'),
              tooltip: '搜索本版',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForumSearchPage(
                      context: DiscuzSearchContext.curForum(srhfid: '30'),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.search),
            ),
        ],
      ),
      body: (asyncState.isLoading && state.threads.isEmpty)
          ? const ForumHomeSkeleton(key: Key('forum-display-skeleton'))
          : state.errorMessage != null && state.threads.isEmpty
          ? _ForumDisplayErrorView(
              message: state.errorMessage!,
              onRetry: controller.refresh,
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView.builder(
                key: const Key('forum-display-list'),
                padding: const EdgeInsets.all(16),
                itemCount: state.threads.length + 1,
                itemBuilder: (context, index) {
                  if (index == state.threads.length) {
                    return _LoadMoreSection(
                      hasMore: state.hasMore,
                      isLoadingMore: state.isLoadingMore,
                      onLoadMore: controller.loadMore,
                    );
                  }

                  final thread = state.threads[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      key: Key('forum-thread-${thread.tid}'),
                      title: Text(thread.subject),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (thread.sourceTagName?.trim().isNotEmpty == true) ...[
                            _ForumThreadTag(label: thread.sourceTagName!.trim()),
                            const SizedBox(height: 4),
                          ],
                          Text('${thread.author} · 回复 ${thread.replies} · 浏览 ${thread.views}'),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ThreadDetailPage(tid: thread.tid, subject: thread.subject),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _ForumThreadTag extends StatelessWidget {
  const _ForumThreadTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24, maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _LoadMoreSection extends StatelessWidget {
  const _LoadMoreSection({
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('没有更多帖子了')),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton(
        key: const Key('forum-display-load-more-button'),
        onPressed: onLoadMore,
        child: const Text('加载更多'),
      ),
    );
  }
}

class _ForumDisplayErrorView extends StatelessWidget {
  const _ForumDisplayErrorView({required this.message, required this.onRetry});

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
              key: const Key('forum-display-retry-button'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
