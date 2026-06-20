import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

class ThreadDetailPage extends ConsumerStatefulWidget {
  const ThreadDetailPage({super.key, required this.tid, this.subject = ''});

  final String tid;
  final String subject;

  @override
  ConsumerState<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends ConsumerState<ThreadDetailPage> {
  @override
  Widget build(BuildContext context) {
    final args = ThreadDetailArgs(tid: widget.tid, subject: widget.subject);
    final asyncState = ref.watch(threadDetailControllerProvider(args));
    final controller = ref.read(threadDetailControllerProvider(args).notifier);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final state =
        asyncState.value ??
        ThreadDetailPageState.initial(tid: widget.tid, subject: widget.subject);
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
          _ThreadDetailMoreMenu(
            state: state,
            onOnlyAuthor: controller.openOnlyAuthor,
            onReverseOrder: controller.openReverseOrder,
            onCopyUrl: _copyUrl,
          ),
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
                    onLoadPreviousPage: controller.loadPreviousPage,
                    onLoadNextPage: controller.loadNextPage,
                    onOpenOnlyAuthor: controller.openOnlyAuthor,
                    onOpenReverseOrder: controller.openReverseOrder,
                    onAddComicToShelf: controller.addToShelf,
                    onAddNovelToShelf: controller.addNovelToShelf,
                    onOpenPostReply: (post) {
                      _openPostReplyComposer(args, state, post);
                    },
                    onOpenPostRate: (post) {
                      _openPostRateSheet(args, controller, post);
                    },
                    onCopyActionUrl: _copyActionUrl,
                    onTogglePollOption: controller.togglePollOption,
                    onSubmitPollVote: controller.submitPollVote,
                  ),
          ),
          _ReplyComposer(
            hint: state.replyHint,
            onReply: asyncState.value == null
                ? null
                : () {
                    _openThreadReplyComposer(args, state);
                  },
            onFavorite:
                asyncState.value == null ||
                    state.isThreadFavoriteActionLoading ||
                    state.isThreadFavorited
                ? null
                : controller.favoriteThread,
            favoriteSelected: state.isThreadFavorited,
            favoriteLoading: state.isThreadFavoriteActionLoading,
            onShare: state.shareUrl?.trim().isEmpty ?? true
                ? null
                : () => _copyUrl('分享链接', state.shareUrl!),
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

  Future<void> _openThreadReplyComposer(
    ThreadDetailArgs args,
    ThreadDetailPageState state,
  ) async {
    final fid = state.fid.trim();
    final tid = state.tid.trim();
    if (fid.isEmpty || tid.isEmpty) {
      return;
    }
    final result = await Navigator.of(context).push<ReplyComposerResult>(
      MaterialPageRoute<ReplyComposerResult>(
        builder: (_) => ReplyComposerPage(
          args: ReplyComposerArgs(
            target: ReplyTarget.thread(
              fid: fid,
              tid: tid,
              sourceUri: Uri.tryParse(state.desktopUrl ?? ''),
            ),
            title: state.subject,
          ),
        ),
      ),
    );
    await _handleReplyComposerResult(args, result);
  }

  Future<void> _openPostReplyComposer(
    ThreadDetailArgs args,
    ThreadDetailPageState state,
    ThreadPost post,
  ) async {
    final replyUrl = post.replyUrl?.trim();
    final fid = state.fid.trim();
    final tid = state.tid.trim();
    if (replyUrl == null || replyUrl.isEmpty || fid.isEmpty || tid.isEmpty) {
      await _copyUrl('楼层回复链接', post.replyUrl ?? '');
      return;
    }
    final replyFormUri = Uri.tryParse(replyUrl);
    if (replyFormUri == null) {
      await _copyUrl('楼层回复链接', replyUrl);
      return;
    }
    final result = await Navigator.of(context).push<ReplyComposerResult>(
      MaterialPageRoute<ReplyComposerResult>(
        builder: (_) => ReplyComposerPage(
          args: ReplyComposerArgs(
            target: ReplyTarget.post(
              fid: fid,
              tid: tid,
              pid: post.pid,
              sourceUri: replyFormUri,
            ),
            replyFormUri: replyFormUri,
          ),
        ),
      ),
    );
    await _handleReplyComposerResult(args, result);
  }

  Future<void> _openPostRateSheet(
    ThreadDetailArgs args,
    ThreadDetailController controller,
    ThreadPost post,
  ) async {
    final formResult = await controller.loadRateForm(post);
    if (!mounted) {
      return;
    }
    if (formResult case ApiFailure<ThreadPostRateForm>(:final error)) {
      _showSnackBar(error.message);
      return;
    }
    final form = (formResult as ApiSuccess<ThreadPostRateForm>).data;
    final result = await showModalBottomSheet<ThreadPostRateDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ThreadPostRateSheet(form: form),
    );
    if (!mounted || result == null) {
      return;
    }
    final submitResult = await ref
        .read(threadDetailControllerProvider(args).notifier)
        .submitPostRate(result);
    if (!mounted) {
      return;
    }
    submitResult.when(
      success: (data) =>
          _showSnackBar(data.message.trim().isEmpty ? '评分成功' : data.message),
      failure: (error) => _showSnackBar(error.message),
    );
  }

  Future<void> _handleReplyComposerResult(
    ThreadDetailArgs args,
    ReplyComposerResult? result,
  ) async {
    if (!mounted || result == null || !result.sent) {
      return;
    }
    _showSnackBar(result.message.trim().isEmpty ? '回复成功' : result.message);
    await ref.read(threadDetailControllerProvider(args).notifier).refresh();
  }

  Future<void> _copyActionUrl(String label, String url) {
    return _copyUrl('$label链接', url);
  }

  Future<void> _copyUrl(String label, String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    _showSnackBar('$label已复制');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
  const _ThreadDetailMoreMenu({
    required this.state,
    required this.onOnlyAuthor,
    required this.onReverseOrder,
    required this.onCopyUrl,
  });

  final ThreadDetailPageState state;
  final VoidCallback onOnlyAuthor;
  final VoidCallback onReverseOrder;
  final void Function(String label, String url) onCopyUrl;

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
      onSelected: (value) {
        switch (value) {
          case 'only-author':
            onOnlyAuthor();
            return;
          case 'reverse-order':
            onReverseOrder();
            return;
          case 'home':
            onCopyUrl('首页链接', state.homeUrl!);
            return;
          case 'desktop':
            onCopyUrl('电脑版链接', state.desktopUrl!);
            return;
        }
      },
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.hint,
    required this.onReply,
    required this.onFavorite,
    required this.favoriteSelected,
    required this.favoriteLoading,
    required this.onShare,
  });

  final String? hint;
  final VoidCallback? onReply;
  final VoidCallback? onFavorite;
  final bool favoriteSelected;
  final bool favoriteLoading;
  final VoidCallback? onShare;

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
                child: OutlinedButton.icon(
                  key: const Key('thread-reply-input'),
                  onPressed: onReply,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('发表回复'),
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
              if (onShare != null)
                IconButton(
                  key: const Key('thread-detail-share-button'),
                  tooltip: '分享',
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_outlined),
                ),
              const SizedBox(width: 4),
              FilledButton(
                key: const Key('thread-reply-submit-button'),
                onPressed: onReply,
                child: const Text('回复'),
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
