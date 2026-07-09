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
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_prewarmer.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_store.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

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
  ImageRequestHeaderBuilder? _latestImageHeaderBuilder;

  /// 跨重建保留的图片真实尺寸快照，供 render plan 锁定首帧高度（防上滑回溯）。
  final ThreadPostImageDimensionStore _imageDimensionStore =
      ThreadPostImageDimensionStore();
  ThreadPostImageDimensionPrewarmer? _imageDimensionPrewarmer;
  String? _prewarmSignature;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _scrollController.dispose();
    _imageDimensionStore.dispose();
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
    ref.watch(threadDetailDiagnosticControllerProvider);
    final diagnosticRecorder = ref.watch(
      threadDetailDiagnosticRecorderProvider,
    );
    final htmlFirstPrecacheService = ref.watch(
      forumImagePrecacheServiceProvider,
    );
    _latestImageHeaderBuilder = imageHeaderBuilder;
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
    _schedulePrewarmImageDimensions(state);

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
          _ThreadDetailMoreMenu(
            state: state,
            onOnlyAuthor: controller.openOnlyAuthor,
            onAllPosts: controller.openAllPosts,
            onReverseOrder: controller.openReverseOrder,
            onNormalOrder: controller.openNormalOrder,
            onCopyUrl: _copyUrl,
            onDisplaySettings: _openDisplaySettings,
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
                    imageReferer: _imageRefererFor(state),
                    imageDimensionStore: _imageDimensionStore,
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
                    onOpenAuthorProfile: _openAuthorProfile,
                    onOpenCommentAuthorProfile: _openCommentAuthorProfile,
                    onCopyActionUrl: _copyActionUrl,
                    onOpenPostLink: _openForumLink,
                    onOpenPostImages: _openPostImages,
                    onOpenPostActions: (post, plan) {
                      _openPostActions(args, state, controller, post, plan);
                    },
                    diagnosticRecorder: diagnosticRecorder,
                    htmlImagePrecacheService: htmlFirstPrecacheService,
                    onTogglePollOption: controller.togglePollOption,
                    onSubmitPollVote: controller.submitPollVote,
                  ),
          ),
        ],
      ),
    );
  }

  /// 进入阅读态前，用持久化缓存里的真实尺寸预热 [_imageDimensionStore]。
  ///
  /// 按 (tid, 当前页, 楼层数) 去重触发，命中后 store 推进 signature，render plan
  /// 缓存随之失效并以可信尺寸重建——首帧即定高，避免滚动中异步改高造成上滑回溯。
  /// 缓存键规则与正文图片渲染保持一致（[ForumImageCacheRequests.threadInline]）。
  void _schedulePrewarmImageDimensions(ThreadDetailPageState state) {
    if (state.posts.isEmpty) {
      return;
    }
    final tid = state.tid.trim().isNotEmpty ? state.tid.trim() : widget.tid;
    final signature = '$tid:${state.currentPage}:${state.posts.length}';
    if (_prewarmSignature == signature) {
      return;
    }
    _prewarmSignature = signature;

    final prewarmer = _imageDimensionPrewarmer ??=
        ThreadPostImageDimensionPrewarmer(
          imageCacheService: ref.read(imageCacheServiceProvider),
          store: _imageDimensionStore,
        );
    const planner = ThreadPostBodyRenderPlanner();
    final documents = state.posts
        .map((post) => planner.plan(post.message).document)
        .toList(growable: false);
    unawaited(
      prewarmer.prewarmDocuments(
        documents,
        cacheKeyResolver: (image) => ForumImageCacheRequests.threadInline(
          tid: tid,
          url: image.url,
          imageIndex: image.index,
        ).cacheKey,
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
            'mobile': '2',
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
      _recordScrollDiagnostic(
        type: ThreadDetailDiagnosticEventType.scrollAnimate,
        scrollOffset: position.pixels,
        message: 'page action scroll top -> ${targetOffset.toStringAsFixed(1)}',
      );
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
              sourceUri: Uri.tryParse(_threadUrlForCopy(state)),
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

  void _openDisplaySettings() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => const ForumHtmlReaderSettingsSheet(
          key: Key('thread-detail-display-settings-sheet'),
          showConversionControls: true,
          showAuthorStyleControls: false,
          showResetButton: false,
        ),
      ),
    );
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
            'mobile': '2',
            if (page > 1) 'page': page.toString(),
          },
        )
        .toString();
  }

  void _openPostImages(ThreadPost post, ThreadPostImageOpenRequest request) {
    final readerRequest = request.readerRequest;
    if (readerRequest == null || readerRequest.continuousImages.isEmpty) {
      _copyUrl('${post.number}# 图片链接', request.image.url);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadImageReaderPage(
          request: readerRequest,
          imageHeaderBuilder: _latestImageHeaderBuilder,
        ),
      ),
    );
  }

  Future<void> _openPostActions(
    ThreadDetailArgs args,
    ThreadDetailPageState state,
    ThreadDetailController controller,
    ThreadPost post,
    ThreadPostBodyRenderPlan plan,
  ) async {
    final action = await showModalBottomSheet<_ThreadPostAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ThreadPostActionSheet(post: post),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ThreadPostAction.reply:
        await _openPostReplyComposer(args, state, post);
        return;
      case _ThreadPostAction.rate:
        await _openPostRateSheet(args, controller, post);
        return;
      case _ThreadPostAction.comment:
        await _openPostCommentSheet(args, controller, post);
        return;
      case _ThreadPostAction.selectCopy:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ThreadPostHtmlSelectionCopyPage(
              post: post,
              threadId: widget.tid,
              imageReferer: _imageRefererFor(state),
              plan: plan,
              imageHeaderBuilder: _latestImageHeaderBuilder,
              onOpenPostLink: _openForumLink,
              onOpenPostImage: _openPostImages,
              onImageFallback: _copyHtmlFirstImageUrl,
            ),
          ),
        );
        return;
      case _ThreadPostAction.copyAll:
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

  void _copyHtmlFirstImageUrl(ThreadPost post, ForumHtmlImageRequest request) {
    _copyUrl('${post.number}# 图片', request.url);
  }

  void _openAuthorProfile(ThreadPost post) {
    final uid = post.authorId.trim();
    if (uid.isEmpty) {
      _showSnackBar('用户 UID 缺失');
      return;
    }
    _openManagedWebView(_authorProfileUri(uid));
  }

  void _openCommentAuthorProfile(ThreadPostCommentEntry comment) {
    final uid = _commentAuthorUid(comment);
    if (uid == null || uid.isEmpty) {
      _showSnackBar('用户 UID 缺失');
      return;
    }
    _openManagedWebView(_authorProfileUri(uid));
  }

  String? _commentAuthorUid(ThreadPostCommentEntry comment) {
    final authorId = comment.authorId?.trim();
    if (authorId != null && authorId.isNotEmpty) {
      return authorId;
    }
    final authorUrl = comment.authorUrl?.trim();
    if (authorUrl == null || authorUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(authorUrl);
    final uid = uri?.queryParameters['uid']?.trim();
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }
    final match = RegExp(
      r'space-uid-(\d+)',
      caseSensitive: false,
    ).firstMatch(authorUrl);
    return match?.group(1);
  }

  Uri _authorProfileUri(String uid) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': uid,
        'mobile': '2',
      },
    );
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
    _recordScrollDiagnostic(
      type: ThreadDetailDiagnosticEventType.targetPostScroll,
      pid: targetPid,
      message: 'queue target post scroll index=$targetIndex',
    );
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
    _recordScrollDiagnostic(
      type: ThreadDetailDiagnosticEventType.scrollAnimate,
      pid: targetPid,
      scrollOffset: position.pixels,
      message:
          'target post animate index=$targetIndex -> ${targetOffset.toStringAsFixed(1)}',
    );
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
    _recordScrollDiagnostic(
      type: ThreadDetailDiagnosticEventType.scrollJump,
      pid: state.posts[targetIndex].pid,
      scrollOffset: position.pixels,
      message:
          'rough target jump attempt=${attempt + 1} -> ${targetOffset.toStringAsFixed(1)}',
    );
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

  void _recordScrollDiagnostic({
    required ThreadDetailDiagnosticEventType type,
    String? pid,
    double? scrollOffset,
    required String message,
  }) {
    final recorder = ref.read(threadDetailDiagnosticRecorderProvider);
    if (!recorder.enabled) {
      return;
    }
    recorder.record(
      type: type,
      pid: pid,
      scrollOffset: scrollOffset,
      message: message,
    );
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
    required this.onDisplaySettings,
  });

  final ThreadDetailPageState state;
  final VoidCallback onOnlyAuthor;
  final VoidCallback onAllPosts;
  final VoidCallback onReverseOrder;
  final VoidCallback onNormalOrder;
  final void Function(String label, String url) onCopyUrl;
  final VoidCallback onDisplaySettings;

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
        const PopupMenuItem<String>(
          key: Key('thread-detail-display-settings-menu-item'),
          value: 'display-settings',
          child: Text('显示设置'),
        ),
        if (state.homeUrl?.trim().isNotEmpty == true)
          const PopupMenuItem<String>(value: 'home', child: Text('返回首页')),
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
          case 'display-settings':
            onDisplaySettings();
            return;
          case 'home':
            onCopyUrl('首页链接', state.homeUrl!);
            return;
        }
      },
    );
  }
}

enum _ThreadPostAction { reply, rate, comment, selectCopy, copyAll }

class _ThreadPostActionSheet extends StatelessWidget {
  const _ThreadPostActionSheet({required this.post});

  final ThreadPost post;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('thread-post-action-sheet'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('thread-post-reply-action'),
                dense: true,
                leading: const Icon(Icons.reply_outlined),
                title: const Text('回复'),
                onTap: () => Navigator.of(context).pop(_ThreadPostAction.reply),
              ),
              if (post.rateUrl?.trim().isNotEmpty == true)
                ListTile(
                  key: const Key('thread-post-rate-action'),
                  dense: true,
                  leading: const Icon(Icons.favorite_border),
                  title: const Text('评分'),
                  onTap: () =>
                      Navigator.of(context).pop(_ThreadPostAction.rate),
                ),
              if (post.commentUrl?.trim().isNotEmpty == true)
                ListTile(
                  key: const Key('thread-post-comment-action'),
                  dense: true,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('点评'),
                  onTap: () =>
                      Navigator.of(context).pop(_ThreadPostAction.comment),
                ),
              ListTile(
                key: const Key('thread-post-select-copy-action'),
                dense: true,
                leading: const Icon(Icons.text_fields),
                title: const Text('选择复制'),
                onTap: () =>
                    Navigator.of(context).pop(_ThreadPostAction.selectCopy),
              ),
              ListTile(
                key: const Key('thread-post-copy-all-action'),
                dense: true,
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('全部复制'),
                onTap: () =>
                    Navigator.of(context).pop(_ThreadPostAction.copyAll),
              ),
            ],
          ),
        ),
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
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: ColoredBox(
            color: ThreadDetailNativePalette.resolve(
              AppTheme.light(),
            ).background,
            child: child,
          ),
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
