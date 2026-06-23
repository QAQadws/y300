import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/thread_post_locator.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

class ThreadDetailPage extends ConsumerStatefulWidget {
  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.subject = '',
    this.initialPage,
    this.targetPid,
  });

  final String tid;
  final String subject;
  final int? initialPage;
  final String? targetPid;

  @override
  ConsumerState<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends ConsumerState<ThreadDetailPage> {
  late final ScrollController _scrollController;
  final Set<String> _scrolledTargetKeys = <String>{};
  final Set<String> _pendingTargetScrollKeys = <String>{};
  final Map<String, int> _targetScrollAttempts = <String, int>{};
  Timer? _highlightClearTimer;
  String? _highlightPostPid;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ThreadDetailArgs(
      tid: widget.tid,
      subject: widget.subject,
      initialPage: widget.initialPage,
      targetPid: widget.targetPid,
    );
    final asyncState = ref.watch(threadDetailControllerProvider(args));
    final controller = ref.read(threadDetailControllerProvider(args).notifier);
    final state =
        asyncState.value ??
        ThreadDetailPageState.initial(tid: widget.tid, subject: widget.subject);
    final imageHeaderBuilder = ref.watch(
      imageRequestHeaderBuilderForRefererProvider(_imageRefererFor(state)),
    );
    ref.listen<AsyncValue<ThreadDetailPageState>>(
      threadDetailControllerProvider(args),
      (previous, next) {
        _scheduleTargetPostScroll(next.value);
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
    _scheduleTargetPostScroll(state);

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
            onAllPosts: controller.openAllPosts,
            onReverseOrder: controller.openReverseOrder,
            onNormalOrder: controller.openNormalOrder,
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
                    scrollController: _scrollController,
                    highlightPostPid: _highlightPostPid,
                    targetPid: widget.targetPid,
                    imageHeaderBuilder: imageHeaderBuilder,
                    sourceTagLabel: _sourceTagLabel(state),
                    onLoadPreviousPage: controller.loadPreviousPage,
                    onLoadNextPage: controller.loadNextPage,
                    onOpenOnlyAuthor: controller.openOnlyAuthor,
                    onOpenAllPosts: controller.openAllPosts,
                    onOpenReverseOrder: controller.openReverseOrder,
                    onOpenNormalOrder: controller.openNormalOrder,
                    onAddComicToShelf: controller.addToShelf,
                    onAddNovelToShelf: controller.addNovelToShelf,
                    onOpenPostReply: (post) {
                      _openPostReplyComposer(args, state, post);
                    },
                    onOpenPostRate: (post) {
                      _openPostRateSheet(args, controller, post);
                    },
                    onOpenPostComment: (post) {
                      _openPostCommentSheet(args, controller, post);
                    },
                    onOpenAuthorProfile: _openAuthorProfile,
                    onCopyActionUrl: _copyActionUrl,
                    onOpenPostLink: _openForumLink,
                    onOpenPostImages: _openPostImages,
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

  String _imageRefererFor(ThreadDetailPageState state) {
    final desktopUrl = state.desktopUrl?.trim();
    if (desktopUrl != null && desktopUrl.isNotEmpty) {
      return desktopUrl;
    }
    final currentPage = state.currentPage <= 0 ? 1 : state.currentPage;
    return Uri.parse(AppConfig.siteBaseUrl)
        .replace(
          path: '/forum.php',
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': widget.tid,
            'page': currentPage.toString(),
          },
        )
        .toString();
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

  Future<void> _openPostCommentSheet(
    ThreadDetailArgs args,
    ThreadDetailController controller,
    ThreadPost post,
  ) async {
    final formResult = await controller.loadCommentForm(post);
    if (!mounted) {
      return;
    }
    if (formResult case ApiFailure<ThreadPostCommentForm>(:final error)) {
      _showSnackBar(error.message);
      return;
    }
    final form = (formResult as ApiSuccess<ThreadPostCommentForm>).data;
    final result = await showModalBottomSheet<ThreadPostCommentDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ThreadPostCommentSheet(form: form),
    );
    if (!mounted || result == null) {
      return;
    }
    final submitResult = await ref
        .read(threadDetailControllerProvider(args).notifier)
        .submitPostComment(result);
    if (!mounted) {
      return;
    }
    submitResult.when(
      success: (data) =>
          _showSnackBar(data.message.trim().isEmpty ? '点评成功' : data.message),
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

  void _openPostImages(ThreadPost post, ThreadPostImageOpenRequest request) {
    _copyUrl('${post.number}# 图片链接', request.image.url);
  }

  void _openAuthorProfile(ThreadPost post) {
    final uid = post.authorId.trim();
    if (uid.isEmpty) {
      _showSnackBar('用户 UID 缺失');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => UserProfilePage(uid: uid)));
  }

  void _scheduleTargetPostScroll(ThreadDetailPageState? state) {
    final targetPid = widget.targetPid?.trim();
    if (targetPid == null || targetPid.isEmpty || state == null) {
      return;
    }
    final targetIndex = state.posts.indexWhere((post) => post.pid == targetPid);
    if (targetIndex < 0) {
      return;
    }
    final key = '${state.currentPage}:$targetPid';
    if (_scrolledTargetKeys.contains(key) ||
        _pendingTargetScrollKeys.contains(key)) {
      return;
    }
    _queueTargetPostScroll(state, key, targetPid, targetIndex);
  }

  void _queueTargetPostScroll(
    ThreadDetailPageState state,
    String key,
    String targetPid,
    int targetIndex,
  ) {
    _pendingTargetScrollKeys.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingTargetScrollKeys.remove(key);
      if (!mounted) {
        return;
      }
      _tryScrollToTargetPost(state, key, targetPid, targetIndex);
    });
  }

  void _tryScrollToTargetPost(
    ThreadDetailPageState state,
    String key,
    String targetPid,
    int targetIndex,
  ) {
    if (_scrolledTargetKeys.contains(key)) {
      return;
    }
    final targetContext = _postCardContext(targetPid);
    if (targetContext == null) {
      _roughScrollTowardTargetPost(state, key, targetIndex);
      return;
    }
    final targetRenderObject = targetContext.findRenderObject();
    final viewport = RenderAbstractViewport.maybeOf(targetRenderObject);
    if (targetRenderObject == null ||
        viewport == null ||
        !_scrollController.hasClients) {
      _roughScrollTowardTargetPost(state, key, targetIndex);
      return;
    }
    _scrolledTargetKeys.add(key);
    _targetScrollAttempts.remove(key);
    final position = _scrollController.position;
    final revealed = viewport.getOffsetToReveal(targetRenderObject, 0);
    final targetOffset = revealed.offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    setState(() => _highlightPostPid = targetPid);
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _highlightPostPid == targetPid) {
        setState(() => _highlightPostPid = null);
      }
    });
  }

  void _roughScrollTowardTargetPost(
    ThreadDetailPageState state,
    String key,
    int targetIndex,
  ) {
    if (!_scrollController.hasClients) {
      return;
    }
    final attempt = _targetScrollAttempts[key] ?? 0;
    if (attempt >= 8) {
      _scrolledTargetKeys.add(key);
      return;
    }
    final position = _scrollController.position;
    final targetOffset = _roughTargetOffset(
      state: state,
      targetIndex: targetIndex,
      position: position,
    );
    _targetScrollAttempts[key] = attempt + 1;
    _scrollController.jumpTo(targetOffset);
    _queueTargetPostScroll(
      state,
      key,
      state.posts[targetIndex].pid,
      targetIndex,
    );
  }

  double _roughTargetOffset({
    required ThreadDetailPageState state,
    required int targetIndex,
    required ScrollPosition position,
  }) {
    final range = _builtPostIndexRange(state);
    if (range != null) {
      final viewport = position.viewportDimension;
      if (targetIndex < range.min) {
        final distance = (range.min - targetIndex).clamp(1, 4).toDouble();
        return (position.pixels - viewport * distance)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
      }
      if (targetIndex > range.max) {
        final distance = (targetIndex - range.max).clamp(1, 4).toDouble();
        return (position.pixels + viewport * distance)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
      }
    }

    final fraction = ((targetIndex + 1) / (state.posts.length + 1)).clamp(
      0.0,
      1.0,
    );
    return (position.maxScrollExtent * fraction)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  ({int min, int max})? _builtPostIndexRange(ThreadDetailPageState state) {
    int? min;
    int? max;
    for (var index = 0; index < state.posts.length; index++) {
      if (_postCardContext(state.posts[index].pid) == null) {
        continue;
      }
      min = min == null ? index : (index < min ? index : min);
      max = max == null ? index : (index > max ? index : max);
    }
    if (min == null || max == null) {
      return null;
    }
    return (min: min, max: max);
  }

  BuildContext? _postCardContext(String pid) {
    final element = _findContextByKey(Key('thread-post-card-$pid'));
    return element;
  }

  BuildContext? _findContextByKey(Key key) {
    BuildContext? found;
    void visitor(Element element) {
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visitor);
    }

    context.visitChildElements(visitor);
    return found;
  }

  void _openForumLink(String url) {
    final destination = const YamiboForumLinkResolver().resolve(url);
    if (destination == null) {
      _copyUrl('链接', url);
      return;
    }
    switch (destination.kind) {
      case YamiboForumLinkKind.thread:
        final tid = destination.tid;
        if (tid == null || tid.isEmpty) {
          _copyUrl('帖子链接', destination.uri.toString());
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ThreadDetailPage(tid: tid)),
        );
        return;
      case YamiboForumLinkKind.threadPost:
        _openThreadPost(destination);
        return;
      case YamiboForumLinkKind.tagThreadPage:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                YamiboTagThreadPage(url: destination.uri.toString()),
          ),
        );
        return;
      case YamiboForumLinkKind.managedWebView:
        _openManagedWebView(destination.uri);
        return;
      case YamiboForumLinkKind.external:
        _copyUrl('外部链接', destination.uri.toString());
        return;
    }
  }

  Future<void> _openThreadPost(YamiboForumLinkDestination destination) async {
    final tid = destination.tid?.trim();
    final pid = destination.pid?.trim();
    if (tid == null || tid.isEmpty || pid == null || pid.isEmpty) {
      _copyUrl('楼层链接', destination.uri.toString());
      return;
    }
    final directPage = destination.page;
    if (directPage != null && directPage > 0) {
      _pushThreadPost(tid: tid, page: directPage, pid: pid);
      return;
    }
    final result = await ref
        .read(threadPostLocatorProvider)
        .locate(tid: tid, pid: pid, sourceUri: destination.uri);
    if (!mounted) {
      return;
    }
    if (result case ApiSuccess<ThreadPostLocation>(:final data)) {
      _pushThreadPost(tid: data.tid, page: data.page, pid: data.pid);
      return;
    }
    _showSnackBar('楼层定位失败，已打开帖子');
    _pushThreadPost(tid: tid, page: 1, pid: pid);
  }

  void _pushThreadPost({
    required String tid,
    required int page,
    required String pid,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: tid, initialPage: page, targetPid: pid),
      ),
    );
  }

  void _openManagedWebView(Uri uri) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          overrides: [
            forumWebViewInitialUriProvider.overrideWithValue(uri),
            forumWebViewPopOnRootBackProvider.overrideWithValue(true),
            forumWebViewDriverProvider.overrideWith((ref) {
              final factory = ref.watch(forumWebViewDriverFactoryProvider);
              return factory();
            }),
            forumWebViewControllerProvider.overrideWith(
              ForumWebViewController.new,
            ),
          ],
          child: const ForumWebViewPage(),
        ),
      ),
    );
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
    required this.onAllPosts,
    required this.onReverseOrder,
    required this.onNormalOrder,
    required this.onCopyUrl,
  });

  final ThreadDetailPageState state;
  final VoidCallback onOnlyAuthor;
  final VoidCallback onAllPosts;
  final VoidCallback onReverseOrder;
  final VoidCallback onNormalOrder;
  final void Function(String label, String url) onCopyUrl;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('thread-detail-more-menu'),
      tooltip: '更多',
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: state.isOnlyAuthorView ? 'all-posts' : 'only-author',
          child: Text(state.isOnlyAuthorView ? '显示全部楼层' : '只看该作者'),
        ),
        PopupMenuItem<String>(
          value: state.isReverseOrderView ? 'normal-order' : 'reverse-order',
          child: Text(state.isReverseOrderView ? '正序浏览' : '倒序浏览'),
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
          case 'all-posts':
            onAllPosts();
            return;
          case 'reverse-order':
            onReverseOrder();
            return;
          case 'normal-order':
            onNormalOrder();
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

Widget threadDetailPreviewShell(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(
        child: ColoredBox(
          color: ThreadDetailNativePalette.resolve(AppTheme.light()).background,
          child: child,
        ),
      ),
    ),
  );
}

@Preview(
  name: 'Thread detail post card',
  group: 'Thread/Detail',
  size: Size(393, 520),
  wrapper: threadDetailPreviewShell,
)
Widget threadDetailPostCardPreview() {
  final state = ThreadDetailPageState.initial(tid: '572529', subject: '帖子楼卡片预览')
      .copyWith(
        fid: '33',
        typeid: '86',
        sourceTagName: '讨论',
        currentPage: 1,
        lastPage: 8,
        views: 4096,
        replies: 128,
        posts: <ThreadPost>[_threadDetailPreviewPost],
      );
  final palette = ThreadDetailNativePalette.resolve(AppTheme.light());
  return SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: ThreadPostCard(
      post: _threadDetailPreviewPost,
      state: state,
      sourceTagLabel: '讨论',
      imageHeaderBuilder: null,
      onAddComicToShelf: () {},
      onAddNovelToShelf: () {},
      onOpenPostReply: (_) {},
      onOpenPostRate: (_) {},
      onOpenPostComment: (_) {},
      onOpenAuthorProfile: (_) {},
      onCopyActionUrl: (_, _) {},
      onOpenPostLink: (_) {},
      onOpenPostImages: null,
      onTogglePollOption: (_, _) {},
      onSubmitPollVote: (_) {},
      palette: palette,
    ),
  );
}

final ThreadPost _threadDetailPreviewPost = ThreadPost(
  pid: 'preview-post',
  author: '蜥蜴少女与神明',
  authorId: '278948',
  number: 12,
  isFirst: false,
  dateline: '2026-06-23 12:48',
  avatarUrl:
      'https://bbs.yamibo.com/uc_server/data/avatar/000/27/89/48_avatar_small.jpg',
  replyUrl:
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572529&repquote=preview-post',
  rateUrl:
      'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=preview-post',
  commentUrl:
      'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=572529&pid=preview-post',
  message:
      '<div class="quote"><blockquote><b>hsyhlj</b>: 后面楼主参加活动的应该就是梅小雪那篇武侠了吧。</blockquote></div>'
      '<p>那篇很好啊我很喜欢 <img src="static/image/smiley/comcom/2.gif" class="vm"> '
      '角色之间的互动很轻盈，读起来像是在夏天的海边慢慢展开的一封信。</p>',
  tagLinks: const <ThreadPostTagLink>[
    ThreadPostTagLink(
      label: '百合',
      tagId: '20674',
      url: 'https://bbs.yamibo.com/misc.php?mod=tag&id=20674&type=thread',
    ),
    ThreadPostTagLink(
      label: '读后感',
      tagId: '21920',
      url: 'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread',
    ),
  ],
  comments: const <ThreadPostCommentEntry>[
    ThreadPostCommentEntry(
      author: '花実',
      authorId: '231169',
      avatarUrl:
          'https://bbs.yamibo.com/uc_server/data/avatar/000/23/11/69_avatar_small.jpg',
      message: '这一段点评会展示在正文下面，头像、名称、内容和时间都保留下来。',
      dateline: '2026-06-23 13:12',
    ),
    ThreadPostCommentEntry(
      author: 'tagami',
      authorId: '14577',
      avatarUrl:
          'https://bbs.yamibo.com/uc_server/data/avatar/000/01/45/77_avatar_small.jpg',
      message: '短点评也应该保持轻量，不抢正文和评分的视觉层级。',
      dateline: '2026-06-23 13:18',
    ),
  ],
  ratingSummary: const ThreadPostRatingSummary(
    participantText: '已有 2 人评分',
    scoreText: '积分 +8',
    ratings: <ThreadPostRating>[
      ThreadPostRating(userName: 'hsyhlj', score: '+5', reason: '我很赞同'),
      ThreadPostRating(userName: 'thessky', score: '+3', reason: '好萌好萌好萌'),
    ],
  ),
);
