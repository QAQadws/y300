import 'package:y300/features/thread/presentation/services/thread_post_navigation.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_content_projection_providers.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:y300/features/thread/presentation/mappers/thread_history_visit_mapper.dart';
import 'package:y300/features/thread/presentation/services/thread_history_commit_guard.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_prewarmer.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_store.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/thread_text_resolver.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_quick_scroll_button.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/app_popup_menu.dart';

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
  late final ThreadDetailQuickScrollCoordinator _quickScrollCoordinator;
  Timer? _highlightClearTimer;
  String? _highlightPostPid;
  String? _latestImageReferer;
  bool _quickScrollMetricsSyncScheduled = false;

  /// 跨重建保留的图片真实尺寸快照，供 render plan 锁定首帧高度（防上滑回溯）。
  final ThreadPostImageDimensionStore _imageDimensionStore =
      ThreadPostImageDimensionStore();
  ThreadPostImageDimensionPrewarmer? _imageDimensionPrewarmer;
  String? _prewarmSignature;
  final ThreadHistoryCommitGuard _historyCommitGuard =
      ThreadHistoryCommitGuard();
  bool _didReportHistoryDuplicate = false;
  bool _postActionActive = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _quickScrollCoordinator = ThreadDetailQuickScrollCoordinator(
      scrollController: _scrollController,
    );
    _activateTargetHighlight(widget.targetPid);
  }

  @override
  void didUpdateWidget(covariant ThreadDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetPid?.trim() != widget.targetPid?.trim()) {
      _activateTargetHighlight(widget.targetPid);
    }
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _quickScrollCoordinator.dispose();
    _scrollController.dispose();
    _imageDimensionStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
    final conversionMode = ref.watch(appServerContentConversionModeProvider);
    final converter = ref.watch(textConverterProvider(conversionMode));
    final projectionCandidate = ref
        .watch(threadDetailContentProjectionProvider(args))
        .value;
    final projection = _resolveProjection(
      state,
      mode: conversionMode,
      converterId: converter.id,
      candidate: projectionCandidate,
    );
    final imageReferer = ref.watch(
      forumImageRefererForSourceProvider(_imageRefererFor(state)),
    );
    final htmlFirstPrecacheService = ref.watch(
      forumImagePrecacheServiceProvider,
    );
    final historyRecorder = ref.watch(historyVisitRecorderProvider);
    final historyDiagnostics = ref.watch(historyDiagnosticRecorderProvider);
    _latestImageReferer = imageReferer;
    ref.listen<AsyncValue<ThreadDetailPageState>>(
      threadDetailControllerProvider(args),
      (previous, next) {
        final previousNotice = previous?.value?.threadFavoriteNotice;
        final nextNotice = next.value?.threadFavoriteNotice;
        if (nextNotice == null || nextNotice == previousNotice) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ThreadTextResolver.actionNotice(l10n, nextNotice)),
          ),
        );
      },
    );
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    _schedulePrewarmImageDimensions(state);
    if (state.posts.isNotEmpty) {
      _scheduleQuickScrollMetricsSync();
    }
    _scheduleHistoryVisit(
      asyncState: asyncState,
      state: state,
      recorder: historyRecorder,
      diagnostics: historyDiagnostics,
    );

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
                forumName: projection.displayForumName,
                initialForumName: widget.initialForumName,
              ),
            ),
          ),
        ),
        actions: [
          if (state.supports(ThreadDetailCapability.favoriteEntry))
            IconButton(
              key: const Key('thread-detail-favorite-button'),
              tooltip: state.isThreadFavorited
                  ? l10n.threadDetailUnfavorite
                  : l10n.threadDetailFavorite,
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
          if (state.supports(ThreadDetailCapability.replyAction))
            IconButton(
              key: const Key('thread-detail-appbar-reply-button'),
              tooltip: l10n.threadDetailReplyPost,
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
      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleQuickScrollMetricsNotification,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleQuickScrollNotification,
          child: Column(
            children: [
              Expanded(
                child: (asyncState.isLoading && state.posts.isEmpty)
                    ? ThreadDetailLoading(
                        key: ValueKey(args),
                        subject: projection.displaySubject,
                      )
                    : (asyncState.hasError || state.errorMessage != null) &&
                          state.posts.isEmpty
                    ? _ThreadErrorView(
                        subject: projection.displaySubject,
                        message: state.loadFailure == null
                            ? ThreadTextResolver.loadFailure(
                                l10n,
                                ThreadUiErrorCode.loadFailed,
                                state.errorMessage,
                              )
                            : ThreadTextResolver.loadFailure(
                                l10n,
                                state.loadFailure!.code,
                                state.loadFailure!.detail,
                              ),
                        onRetry: controller.refresh,
                      )
                    : ForumPullToRefresh(
                        onRefresh: () => controller.refresh(forceNetwork: true),
                        child: ThreadDetailContent(
                          state: state,
                          projection: projection,
                          scrollController: _scrollController,
                          highlightPostPid: _highlightPostPid,
                          targetPid: widget.targetPid,
                          imageReferer: _imageRefererFor(state),
                          imageDimensionStore: _imageDimensionStore,
                          onLoadPreviousPage: () {
                            unawaited(
                              _runPageActionAndScrollTop(
                                controller.loadPreviousPage,
                              ),
                            );
                          },
                          onLoadNextPage: () {
                            unawaited(
                              _runPageActionAndScrollTop(
                                controller.loadNextPage,
                              ),
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
                            final postProjection = projection.findByPid(
                              post.pid,
                            );
                            _openPostActions(
                              args,
                              state,
                              controller,
                              post,
                              postProjection?.displayPost ?? post,
                              plan,
                            );
                          },
                          htmlImagePrecacheService: htmlFirstPrecacheService,
                          onTogglePollOption: controller.togglePollOption,
                          onSubmitPollVote: controller.submitPollVote,
                          onLoadAllRatings: controller.loadAllRatings,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ThreadDetailQuickScrollButton(
          coordinator: _quickScrollCoordinator,
          hasContent: state.posts.isNotEmpty,
          backgroundColor: palette.cardElevated,
          foregroundColor: palette.title,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  bool _handleQuickScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification case UserScrollNotification(:final direction)) {
      _quickScrollCoordinator.updateUserDirection(direction);
    }
    _quickScrollCoordinator.updateMetrics(notification.metrics);
    return false;
  }

  bool _handleQuickScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.depth == 0) {
      _quickScrollCoordinator.updateMetrics(notification.metrics);
    }
    return false;
  }

  void _scheduleQuickScrollMetricsSync() {
    if (_quickScrollMetricsSyncScheduled) {
      return;
    }
    _quickScrollMetricsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quickScrollMetricsSyncScheduled = false;
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _quickScrollCoordinator.updateMetrics(_scrollController.position);
    });
  }

  void _scheduleHistoryVisit({
    required AsyncValue<ThreadDetailPageState> asyncState,
    required ThreadDetailPageState state,
    required HistoryVisitRecorder recorder,
    required HistoryDiagnosticRecorder diagnostics,
  }) {
    if (!asyncState.hasValue ||
        state.isLoadingInitial ||
        state.errorMessage != null ||
        state.posts.isEmpty) {
      return;
    }
    final routeTid = widget.tid.trim();
    final visibleTid = state.tid.trim().isEmpty ? routeTid : state.tid.trim();
    final routeSubject = widget.subject;
    final routeForumName = widget.initialForumName;
    final routePage = widget.initialPage;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.tid.trim() != routeTid) {
        return;
      }
      if (!_historyCommitGuard.tryCommit(visibleTid)) {
        if (!_didReportHistoryDuplicate) {
          _didReportHistoryDuplicate = true;
          diagnostics.recordSkip(
            surface: HistoryVisitSurface.threadNative,
            reason: 'route_session_duplicate',
          );
        }
        return;
      }
      try {
        final draft = const ThreadHistoryVisitMapper().map(
          state: state,
          routeTid: routeTid,
          routeSubject: routeSubject,
          routeForumName: routeForumName,
          routePage: routePage,
        );
        await recorder.record(draft);
      } catch (error) {
        debugPrint(
          '[ThreadDetail][native][history_record_failure] '
          'error=${error.runtimeType}',
        );
      }
    });
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

  Future<void> _handleReplyComposerResult(
    ThreadDetailArgs args,
    ReplyComposerResult? result,
  ) async {
    if (!mounted || result == null || !result.sent) {
      return;
    }
    _showActionNotice(
      ThreadActionNotice(
        code: ThreadActionNoticeCode.success,
        action: ThreadActionKind.reply,
        detail: ComposerTextResolver.submitSuccess(
          AppLocalizations.of(context),
          ComposerKind.reply,
          result.rawSuccessDetail,
        ),
      ),
    );
    await ref
        .read(threadDetailControllerProvider(args).notifier)
        .refreshAfterMutation();
  }

  Future<void> _copyActionUrl(String label, String url) {
    return _copyUrl(label, url);
  }

  Future<void> _copyThreadUrl(ThreadDetailPageState state) {
    return _copyUrl(
      AppLocalizations.of(context).threadDetailPostLink,
      _threadUrlForCopy(state),
    );
  }

  void _openDisplaySettings() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: false,
        builder: (context) => const ForumHtmlReaderSettingsSheet(
          key: Key('thread-detail-display-settings-sheet'),
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

  ThreadPostNavigation get _postNavigation => ThreadPostNavigation(
    context: context,
    ref: ref,
    tid: widget.tid,
    imageReferer: _latestImageReferer,
    isCurrent: () => mounted,
  );
  void _openPostImages(ThreadPost post, ThreadPostImageOpenRequest request) =>
      _postNavigation.openImages(post, request);

  Future<void> _openPostActions(
    ThreadDetailArgs args,
    ThreadDetailPageState state,
    ThreadDetailController controller,
    ThreadPost sourcePost,
    ThreadPost displayPost,
    ThreadPostBodyRenderPlan plan,
  ) async {
    if (_postActionActive) return;
    _postActionActive = true;
    final invalidation = ref.read(nativePageCacheInvalidationServiceProvider);
    try {
      final mutation = await ThreadPostActions(
        context: context,
        ref: ref,
        target: ThreadPostActionContext(
          tid: args.tid,
          fid: state.fid,
          subject: state.subject,
          page: state.currentPage,
          capabilities: state.capabilities,
          sourceUri: Uri.tryParse(_threadUrlForCopy(state)),
        ),
        imageReferer: _imageRefererFor(state),
        isCurrent: () => mounted && widget.tid == args.tid,
      ).show(sourcePost: sourcePost, displayPost: displayPost, plan: plan);
      if (mutation == null) return;
      try {
        await invalidation.invalidateThread(args.tid);
      } catch (_) {
        // A confirmed write remains valid if cache maintenance fails.
      }
      if (mounted && widget.tid == args.tid) await controller.refresh();
    } finally {
      _postActionActive = false;
    }
  }

  void _openAuthorProfile(ThreadPost post) => _postNavigation.openAuthor(post);
  void _openCommentAuthorProfile(ThreadPostCommentEntry comment) =>
      _postNavigation.openCommentAuthor(comment);

  void _activateTargetHighlight(String? rawPid) {
    _highlightClearTimer?.cancel();
    final pid = rawPid?.trim();
    _highlightPostPid = pid == null || pid.isEmpty ? null : pid;
    if (_highlightPostPid == null) {
      return;
    }
    _highlightClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _highlightPostPid == pid) {
        setState(() => _highlightPostPid = null);
      }
    });
  }

  void _openForumLink(String url) => _postNavigation.openLink(url);
  Future<void> _copyUrl(String label, String url) =>
      _postNavigation.copyUrl(label, url);

  void _showActionNotice(ThreadActionNotice notice) {
    _showSnackBar(
      ThreadTextResolver.actionNotice(AppLocalizations.of(context), notice),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  ThreadDetailContentProjection _resolveProjection(
    ThreadDetailPageState source, {
    required TextConversionMode mode,
    required String converterId,
    required ThreadDetailContentProjection? candidate,
  }) {
    final sourceRevision = ThreadDetailContentProjector.sourceRevisionFor(
      source,
    );
    if (candidate != null &&
        candidate.mode == mode &&
        candidate.converterId == converterId &&
        candidate.sourceRevision == sourceRevision) {
      return candidate.rebaseTransientState(source);
    }
    return ThreadDetailContentProjection.raw(
      source,
      mode: mode,
      converterId: converterId,
      sourceRevision: sourceRevision,
    );
  }
}

class _ThreadDetailAppBarTitle extends StatelessWidget {
  const _ThreadDetailAppBarTitle({
    required this.forumName,
    this.initialForumName,
  });

  final String? forumName;
  final String? initialForumName;

  @override
  Widget build(BuildContext context) {
    final parsedForumName = forumName?.trim();
    final fallbackForumName = initialForumName?.trim();
    final resolvedForumName = parsedForumName?.isNotEmpty == true
        ? parsedForumName
        : fallbackForumName;
    return Text(
      resolvedForumName == null || resolvedForumName.isEmpty
          ? AppLocalizations.of(context).threadDetailTitle
          : resolvedForumName,
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
    final l10n = AppLocalizations.of(context);
    return AppPopupMenuButton<String>(
      key: const Key('thread-detail-more-menu'),
      tooltip: l10n.threadDetailMore,
      itemBuilder: (context) => [
        if (state.supports(ThreadDetailCapability.alternateViews)) ...[
          AppPopupMenuItem<String>(
            value: state.isOnlyAuthorView ? 'all-posts' : 'only-author',
            label: state.isOnlyAuthorView
                ? l10n.threadDetailAllPosts
                : l10n.threadDetailOnlyAuthor,
          ),
          AppPopupMenuItem<String>(
            value: state.isReverseOrderView ? 'normal-order' : 'reverse-order',
            label: state.isReverseOrderView
                ? l10n.threadDetailNormalOrder
                : l10n.threadDetailReverseOrder,
          ),
        ],
        AppPopupMenuItem<String>(
          key: const Key('thread-detail-display-settings-menu-item'),
          value: 'display-settings',
          label: l10n.threadDetailDisplaySettings,
        ),
        if (state.homeUrl?.trim().isNotEmpty == true)
          AppPopupMenuItem<String>(
            value: 'home',
            label: l10n.threadDetailBackHome,
          ),
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
            onCopyUrl(l10n.threadDetailHomeLink, state.homeUrl!);
            return;
        }
      },
    );
  }
}

class _ThreadErrorView extends StatelessWidget {
  const _ThreadErrorView({
    required this.subject,
    required this.message,
    required this.onRetry,
  });

  final String subject;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ThreadDetailEntrySurface(
      subject: subject,
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
              child: Text(l10n.commonRetry),
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
      imageReferer: null,
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
