import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/shared/widgets/app_skeleton.dart';

class ThreadDetailPage extends ConsumerWidget {
  const ThreadDetailPage({super.key, required this.tid, this.subject = ''});

  final String tid;
  final String subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ThreadDetailArgs(tid: tid, subject: subject);
    final asyncState = ref.watch(threadDetailControllerProvider(args));
    final controller = ref.read(threadDetailControllerProvider(args).notifier);

    final state = asyncState.value ??
        ThreadDetailPageState.initial(tid: tid, subject: subject);

    return Scaffold(
      appBar: AppBar(title: Text(state.subject.isNotEmpty ? state.subject : '帖子详情')),
      body: (asyncState.isLoading && state.posts.isEmpty)
          ? const ForumHomeSkeleton(key: Key('thread-detail-skeleton'))
          : state.errorMessage != null && state.posts.isEmpty
              ? _ThreadErrorView(
                  message: state.errorMessage!,
                  onRetry: controller.refresh,
                )
              : ListView.builder(
                  key: const Key('thread-detail-list'),
                  padding: const EdgeInsets.all(16),
                  itemCount: state.posts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == state.posts.length) {
                      return _ThreadLoadMoreSection(
                        hasMore: state.hasMore,
                        isLoadingMore: state.isLoadingMore,
                        onLoadMore: controller.loadMore,
                      );
                    }

                    final post = state.posts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${post.number}楼 · ${post.author} · ${post.dateline}'),
                            const SizedBox(height: 8),
                            Text(
                              _stripSimpleHtml(post.message),
                              key: Key('thread-post-${post.pid}'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _stripSimpleHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

class _ThreadLoadMoreSection extends StatelessWidget {
  const _ThreadLoadMoreSection({
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
        child: Center(child: Text('没有更多回复了')),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton(
        key: const Key('thread-detail-load-more-button'),
        onPressed: onLoadMore,
        child: const Text('加载更多回复'),
      ),
    );
  }
}

class _ThreadErrorView extends StatelessWidget {
  const _ThreadErrorView({required this.message, required this.onRetry});

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
              key: const Key('thread-detail-retry-button'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
