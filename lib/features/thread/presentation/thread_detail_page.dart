import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/shared/widgets/shelf/candidate_shelf_action_row.dart';
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
    final state = asyncState.value ?? ThreadDetailPageState.initial(tid: tid, subject: subject);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.subject.isNotEmpty ? state.subject : '帖子详情'),
        actions: [
          if (state.fid == '30')
            IconButton(
              key: const Key('thread-detail-search-button'),
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
      body: Column(
        children: [
          Expanded(
            child: (asyncState.isLoading && state.posts.isEmpty)
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
                      final showComicEntry = post.isFirst && state.comicCandidateInfo.isCandidate;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${post.number}楼 · ${post.author} · ${post.dateline}'),
                              if (showComicEntry) ...[
                                const SizedBox(height: 8),
                                CandidateShelfActionRow(
                                  label: '漫画候选（评分 ${state.comicCandidateInfo.score}）',
                                  inShelf: state.isInShelf,
                                  isLoading: state.isComicActionLoading,
                                  onPressed: controller.addToShelf,
                                ),
                              ],
                              if (post.isFirst && state.isNovelCandidate) ...[
                                const SizedBox(height: 8),
                                CandidateShelfActionRow(
                                  label: '小说候选（fid=${state.fid}）',
                                  inShelf: state.isNovelInShelf,
                                  isLoading: state.isNovelActionLoading,
                                  onPressed: controller.addNovelToShelf,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Html(
                                data: post.message,
                                key: Key('thread-post-${post.pid}'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _ReplyComposer(
            replyText: state.replyText,
            isSubmitting: state.isReplySubmitting,
            hint: state.replyHint,
            onChanged: controller.updateReplyText,
            onSubmit: controller.submitReply,
          ),
        ],
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.replyText,
    required this.isSubmitting,
    required this.hint,
    required this.onChanged,
    required this.onSubmit,
  });

  final String replyText;
  final bool isSubmitting;
  final String? hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null && hint!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  hint!,
                  key: const Key('thread-reply-hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('thread-reply-input'),
                  initialValue: replyText,
                  enabled: !isSubmitting,
                  onChanged: onChanged,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '输入回复内容',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('thread-reply-submit-button'),
                onPressed: isSubmitting ? null : onSubmit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
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
