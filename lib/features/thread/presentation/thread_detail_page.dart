import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
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
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_post_media_preload_queue.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

// Temporary diagnostic switch: media preloading can parse/decode nearby heavy
// posts on the UI isolate while scrolling. Keep it disabled until the thread
// detail jank source is verified on device.
const bool _enableThreadPostMediaPreload = false;

class ThreadDetailPage extends ConsumerStatefulWidget {
  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.subject = '',
    this.initialPage,
    this.targetPid,
    this.initialForumName,
  });

  final String tid;
  final String subject;
  final int? initialPage;
  final String? targetPid;
  final String? initialForumName;

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
  bool _suppressTargetScrollForPageAction = false;
  ThreadPostMediaPreloadQueue? _mediaPreloadQueue;
  ImageRequestHeaderBuilder? _latestImageHeaderBuilder;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _mediaPreloadQueue?.dispose();
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
    _latestImageHeaderBuilder = imageHeaderBuilder;
    if (_enableThreadPostMediaPreload) {
      _mediaPreloadQueue ??= ThreadPostMediaPreloadQueue(
        imageCacheService: ref.read(imageCacheServiceProvider),
      );
    }
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
        centerTitle: false,
        title: GestureDetector(
          key: const Key('thread-detail-appbar-copy-link-area'),
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            unawaited(_copyThreadUrl(state));
          },
          child: SizedBox(
            width: double.infinity,
            height: kToolbarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ThreadDetailAppBarTitle(
                state: state,
                initialForumName: widget.initialForumName,
              ),
            ),
          ),
        ),
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
                        ? Icons.star
                        : Icons.star_border_outlined,
                  ),
          ),
          IconButton(
            key: const Key('thread-detail-appbar-reply-button'),
            tooltip: '回复帖子',
            onPressed: asyncState.value == null
                ? null
                : () {
                    _openThreadReplyComposer(args, state);
                  },
            icon: const Icon(Icons.reply),
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
                    onLoadPreviousPage: () {
                      unawaited(
                        _runPageActionAndScrollTop(controller.loadPreviousPage),
                      );
                    },
                    onLoadNextPage: () {
                      unawaited(
                        _runPageActionAndScrollTop(controller.loadNextPage),
                      );
                    },
                    onLoadPageNumber: (page) {
                      unawaited(
                        _runPageActionAndScrollTop(
                          () => controller.loadPage(page),
                        ),
                      );
                    },
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
                    onOpenPostCopyActions: _openPostCopyActions,
                    onPostBuilt: _enableThreadPostMediaPreload
                        ? (index) {
                            _mediaPreloadQueue?.preloadNearbyPosts(
                              tid: state.tid,
                              posts: state.posts,
                              centerIndex: index,
                            );
                          }
                        : null,
                    onTogglePollOption: controller.togglePollOption,
                    onSubmitPollVote: controller.submitPollVote,
                  ),
          ),
        ],
      ),
    );
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

  Future<void> _runPageActionAndScrollTop(
    FutureOr<void> Function() action,
  ) async {
    _suppressTargetScrollForPageAction = true;
    try {
      await action();
      if (!mounted) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final targetOffset = position.minScrollExtent;
      if ((position.pixels - targetOffset).abs() < 1) {
        return;
      }
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _suppressTargetScrollForPageAction = false;
    }
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
    await ref
        .read(threadDetailControllerProvider(args).notifier)
        .refreshAfterMutation();
  }

  Future<void> _copyActionUrl(String label, String url) {
    return _copyUrl('$label链接', url);
  }

  Future<void> _copyThreadUrl(ThreadDetailPageState state) {
    return _copyUrl('帖子链接', _threadUrlForCopy(state));
  }

  String _threadUrlForCopy(ThreadDetailPageState state) {
    final desktopUrl = state.desktopUrl?.trim();
    if (desktopUrl != null && desktopUrl.isNotEmpty) {
      return desktopUrl;
    }
    final tid = state.tid.trim().isNotEmpty
        ? state.tid.trim()
        : widget.tid.trim();
    if (tid.isEmpty) {
      return '';
    }
    final page = state.currentPage > 0
        ? state.currentPage
        : (widget.initialPage ?? 1);
    return Uri.parse(AppConfig.siteBaseUrl)
        .replace(
          path: '/forum.php',
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': tid,
            if (page > 1) 'page': page.toString(),
          },
        )
        .toString();
  }

  void _openPostImages(ThreadPost post, ThreadPostImageOpenRequest request) {
    _copyUrl('${post.number}# 图片链接', request.image.url);
  }

  Future<void> _openPostCopyActions(
    ThreadPost post,
    ThreadPostBodyRenderPlan plan,
  ) async {
    final action = await showModalBottomSheet<_ThreadPostCopyAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _ThreadPostCopyActionSheet(),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ThreadPostCopyAction.select:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _ThreadPostSelectableCopyPage(
              post: post,
              threadId: widget.tid,
              plan: plan,
              imageHeaderBuilder: _latestImageHeaderBuilder,
              onOpenLink: _openForumLink,
              onOpenImage: (request) => _openPostImages(post, request),
            ),
          ),
        );
        return;
      case _ThreadPostCopyAction.copyAll:
        await _copyPostPlainText(post, plan);
        return;
    }
  }

  Future<void> _copyPostPlainText(
    ThreadPost post,
    ThreadPostBodyRenderPlan plan,
  ) {
    final text = const ThreadPostBodyPlainTextExtractor().extract(
      plan.document,
    );
    return _copyUrl('${post.number}# 正文', text);
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
    if (_suppressTargetScrollForPageAction) {
      return;
    }
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
  const _ThreadDetailAppBarTitle({required this.state, this.initialForumName});

  final ThreadDetailPageState state;
  final String? initialForumName;

  @override
  Widget build(BuildContext context) {
    final parsedForumName = state.forumName?.trim();
    final fallbackForumName = initialForumName?.trim();
    final forumName = parsedForumName?.isNotEmpty == true
        ? parsedForumName
        : fallbackForumName;
    return Text(
      forumName == null || forumName.isEmpty ? '' : forumName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

enum _ThreadPostCopyAction { select, copyAll }

class _ThreadPostCopyActionSheet extends StatelessWidget {
  const _ThreadPostCopyActionSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('thread-post-copy-action-sheet'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('thread-post-select-copy-action'),
                dense: true,
                leading: const Icon(Icons.text_fields),
                title: const Text('选择复制'),
                onTap: () =>
                    Navigator.of(context).pop(_ThreadPostCopyAction.select),
              ),
              ListTile(
                key: const Key('thread-post-copy-all-action'),
                dense: true,
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('全部复制'),
                onTap: () =>
                    Navigator.of(context).pop(_ThreadPostCopyAction.copyAll),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadPostSelectableCopyPage extends StatelessWidget {
  const _ThreadPostSelectableCopyPage({
    required this.post,
    required this.threadId,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenLink,
    required this.onOpenImage,
  });

  final ThreadPost post;
  final String threadId;
  final ThreadPostBodyRenderPlan plan;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<String> onOpenLink;
  final ThreadPostImageOpenHandler onOpenImage;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return Scaffold(
      key: const Key('thread-post-selectable-copy-page'),
      backgroundColor: palette.background,
      appBar: AppBar(centerTitle: false, title: const Text('选择复制')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        children: [
          Container(
            key: Key('thread-post-selectable-copy-body-${post.pid}'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
            ),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.bodyText,
                height: 1.5,
              ),
              child: ThreadPostBodyView(
                document: plan.document,
                blocks: plan.document.blocks,
                images: plan.images,
                imageHeaderBuilder: imageHeaderBuilder,
                imageCacheOwnerId: threadId,
                resourceLayoutHints: plan.resourceLayoutHints,
                selectionEnabled: true,
                onOpenLink: onOpenLink,
                onOpenImage: onOpenImage,
              ),
            ),
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
      imageHeaderBuilder: null,
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
