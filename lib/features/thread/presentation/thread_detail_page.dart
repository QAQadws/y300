import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

class ThreadDetailPage extends ConsumerWidget {
  const ThreadDetailPage({super.key, required this.tid, this.subject = ''});

  final String tid;
  final String subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ThreadDetailArgs(tid: tid, subject: subject);
    final asyncState = ref.watch(threadDetailControllerProvider(args));
    final controller = ref.read(threadDetailControllerProvider(args).notifier);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final state =
        asyncState.value ??
        ThreadDetailPageState.initial(tid: tid, subject: subject);
    ref.listen<AsyncValue<ThreadDetailPageState>>(
      threadDetailControllerProvider(args),
      (previous, next) {
        final previousHint = previous?.value?.threadFavoriteHint;
        final nextHint = next.value?.threadFavoriteHint;
        if (nextHint == null ||
            nextHint.trim().isEmpty ||
            nextHint == previousHint) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(nextHint)));
      },
    );
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: _ThreadDetailAppBarTitle(state: state),
        actions: [
          IconButton(
            key: const Key('thread-detail-favorite-button'),
            tooltip: state.isThreadFavorited ? '已收藏' : '收藏帖子',
            onPressed:
                asyncState.value == null ||
                    state.isThreadFavoriteActionLoading ||
                    state.isThreadFavorited
                ? null
                : controller.favoriteThread,
            icon: state.isThreadFavoriteActionLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    state.isThreadFavorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                  ),
          ),
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
          _ThreadDetailMoreMenu(state: state),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: (asyncState.isLoading && state.posts.isEmpty)
                ? const SizedBox.shrink()
                : state.errorMessage != null && state.posts.isEmpty
                ? _ThreadErrorView(
                    message: state.errorMessage!,
                    onRetry: controller.refresh,
                  )
                : ThreadDetailContent(
                    state: state,
                    imageHeaderBuilder: imageHeaderBuilder,
                    sourceTagLabel: _sourceTagLabel(state),
                    onLoadMore: controller.loadMore,
                    onAddComicToShelf: controller.addToShelf,
                    onAddNovelToShelf: controller.addNovelToShelf,
                  ),
          ),
          _ReplyComposer(
            replyText: state.replyText,
            isSubmitting: state.isReplySubmitting,
            hint: state.replyHint,
            onChanged: controller.updateReplyText,
            onSubmit: controller.submitReply,
            onFavorite:
                asyncState.value == null ||
                    state.isThreadFavoriteActionLoading ||
                    state.isThreadFavorited
                ? null
                : controller.favoriteThread,
            favoriteSelected: state.isThreadFavorited,
            favoriteLoading: state.isThreadFavoriteActionLoading,
            showShare: state.shareUrl?.trim().isNotEmpty == true,
          ),
        ],
      ),
    );
  }

  String _sourceTagLabel(ThreadDetailPageState state) {
    final tagName = state.sourceTagName?.trim();
    if (tagName != null && tagName.isNotEmpty) {
      return tagName;
    }
    final typeid = state.typeid.trim();
    return typeid.isEmpty ? '未标记' : 'typeid=$typeid';
  }
}

class _ThreadDetailAppBarTitle extends StatelessWidget {
  const _ThreadDetailAppBarTitle({required this.state});

  final ThreadDetailPageState state;

  @override
  Widget build(BuildContext context) {
    final forumName = state.forumName?.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.subject.isNotEmpty ? state.subject : '帖子详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (forumName != null && forumName.isNotEmpty)
          Text(
            forumName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DefaultTextStyle.of(
              context,
            ).style.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _ThreadDetailMoreMenu extends StatelessWidget {
  const _ThreadDetailMoreMenu({required this.state});

  final ThreadDetailPageState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('thread-detail-more-menu'),
      tooltip: '更多',
      itemBuilder: (context) => [
        if (state.onlyAuthorUrl?.trim().isNotEmpty == true)
          const PopupMenuItem<String>(
            value: 'only-author',
            child: Text('只看楼主'),
          ),
        if (state.reverseOrderUrl?.trim().isNotEmpty == true)
          const PopupMenuItem<String>(
            value: 'reverse-order',
            child: Text('倒序浏览'),
          ),
        if (state.homeUrl?.trim().isNotEmpty == true)
          const PopupMenuItem<String>(value: 'home', child: Text('返回首页')),
        if (state.desktopUrl?.trim().isNotEmpty == true)
          const PopupMenuItem<String>(value: 'desktop', child: Text('电脑版')),
      ],
      onSelected: (_) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('该入口后续接入')));
      },
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
    required this.onFavorite,
    required this.favoriteSelected,
    required this.favoriteLoading,
    required this.showShare,
  });

  final String replyText;
  final bool isSubmitting;
  final String? hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onFavorite;
  final bool favoriteSelected;
  final bool favoriteLoading;
  final bool showShare;

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
              IconButton(
                key: const Key('thread-detail-bottom-favorite-button'),
                tooltip: favoriteSelected ? '已收藏' : '收藏帖子',
                onPressed: onFavorite,
                icon: favoriteLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        favoriteSelected
                            ? Icons.star
                            : Icons.star_border_outlined,
                      ),
              ),
              if (showShare)
                IconButton(
                  key: const Key('thread-detail-share-button'),
                  tooltip: '分享',
                  onPressed: null,
                  icon: const Icon(Icons.ios_share_outlined),
                ),
              const SizedBox(width: 4),
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
