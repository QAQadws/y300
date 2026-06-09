import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class NovelReaderPage extends ConsumerStatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.novelId,
    required this.initialEpisodeId,
  });

  final String novelId;
  final String initialEpisodeId;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage> {
  late final ScrollController _scrollController;
  late final ReaderOverlayController _overlayController;
  final NovelReaderThemeResolver _themeResolver = const NovelReaderThemeResolver();
  final NovelReaderTypographyResolver _typographyResolver =
      const NovelReaderTypographyResolver();
  final NovelReaderPaginator _paginator = const NovelReaderPaginator();
  final NovelReaderProgressPolicy _progressPolicy = const NovelReaderProgressPolicy();
  PageController? _pageController;
  NovelReaderPageLayout? _currentPagedLayout;
  String? _pagedEpisodeId;
  NovelReaderFlowMode? _pagedFlowMode;
  int? _pagedPageCount;
  final Set<PageController> _pendingPageControllerDisposals = <PageController>{};
  final Map<String, GlobalKey> _nodeKeys = <String, GlobalKey>{};
  int _currentPageIndex = 0;
  bool _hasRestoredOffset = false;
  bool _isProgrammaticScrollChange = false;

  NovelReaderArgs get _args =>
      NovelReaderArgs(novelId: widget.novelId, episodeId: widget.initialEpisodeId);

  @override
  void initState() {
    super.initState();
    _overlayController = ReaderOverlayController();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(novelReaderControllerProvider(_args));
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final externalLauncher = ref.watch(forumWebViewExternalLauncherProvider);

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          final theme = Theme.of(context);
          final palette = _themeResolver.resolve(
            preferences: viewState.preferences,
            theme: theme,
            platformBrightness: MediaQuery.platformBrightnessOf(context),
          );
          final typography = _typographyResolver.resolve(
            preferences: viewState.preferences,
            theme: theme,
            palette: palette,
          );
          return ColoredBox(
            color: palette.background,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isPaged = _isPagedMode(viewState.preferences.flowMode);
                if (!isPaged) {
                  _currentPagedLayout = null;
                  _resetPagedController();
                  _restoreOffsetIfNeeded(
                    episodeId: viewState.currentEpisode.episodeId,
                    offset: viewState.currentOffset,
                  );
                }
                final pagedLayout = isPaged
                    ? _buildPagedLayout(viewState, typography, constraints)
                    : null;
                final pageIndex = pagedLayout == null
                    ? 0
                    : _ensurePagedController(viewState, pagedLayout);
                return ReaderOverlayScaffold(
                  controller: _overlayController,
                  topBar: _buildTopBarConfig(viewState),
                  bottomBar: _buildBottomBarConfig(
                    viewState,
                    controller,
                    pagedLayout: pagedLayout,
                    pageIndex: pageIndex,
                  ),
                  bottomSafeFraction: 0.18,
                  onLeftTap: pagedLayout == null
                      ? null
                      : () => _handlePagedSideTap(
                            isLeftTap: true,
                            viewState: viewState,
                            controller: controller,
                            layout: pagedLayout,
                          ),
                  onRightTap: pagedLayout == null
                      ? null
                      : () => _handlePagedSideTap(
                            isLeftTap: false,
                            viewState: viewState,
                            controller: controller,
                            layout: pagedLayout,
                          ),
                  child: pagedLayout == null
                      ? _buildReaderList(
                          viewState,
                          typography,
                          imageHeaderBuilder,
                          externalLauncher,
                        )
                      : _buildPagedReader(
                          viewState,
                          typography,
                          imageHeaderBuilder,
                          externalLauncher,
                          pagedLayout,
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  ReaderTopBarConfig _buildTopBarConfig(NovelReaderViewState viewState) {
    return ReaderTopBarConfig(
      title: _novelTitle(viewState),
      subtitle: viewState.currentEpisode.episodeTitle,
      onBack: () => _popReader(),
      actions: [
        ReaderToolbarAction(
          id: 'bookmark',
          icon: viewState.hasCurrentEpisodeBookmark
              ? Icons.bookmark
              : Icons.bookmark_border,
          label: '书签',
          onPressed: () => _toggleEpisodeBookmark(viewState),
        ),
        ReaderToolbarAction(
          id: 'search',
          icon: Icons.search,
          label: '搜索',
          onPressed: () => _showSearchSheet(viewState),
        ),
        ReaderToolbarAction(
          id: 'open-thread',
          icon: Icons.open_in_new,
          label: '打开原帖',
          onPressed: () => _openSourceThread(viewState),
        ),
        ReaderToolbarAction(
          id: 'more',
          icon: Icons.more_vert,
          label: '更多',
          onPressed: () => _showPlaceholder('更多阅读操作将在后续阶段接入'),
        ),
      ],
    );
  }

  ReaderBottomBarConfig _buildBottomBarConfig(
    NovelReaderViewState viewState,
    NovelReaderController controller, {
    NovelReaderPageLayout? pagedLayout,
    int pageIndex = 0,
  }) {
    if (pagedLayout != null) {
      final current = pagedLayout.clampPageIndex(pageIndex);
      return ReaderBottomBarConfig(
        showProgress: viewState.preferences.showProgressIndicator,
        progress: ReaderProgressConfig(
          current: current + 1,
          total: pagedLayout.pageCount,
          previousEnabled: current > 0 || viewState.hasPreviousEpisode,
          nextEnabled: current < pagedLayout.pageCount - 1 || viewState.hasNextEpisode,
          previousTooltip: '上一页',
          nextTooltip: '下一页',
          onPrevious: () => _goToPreviousPageOrEpisode(
            viewState: viewState,
            controller: controller,
            layout: pagedLayout,
          ),
          onNext: () => _goToNextPageOrEpisode(
            viewState: viewState,
            controller: controller,
            layout: pagedLayout,
          ),
          onChanged: (_) {},
          onChangeEnd: (value) => _jumpToPagedIndex(
            value.round(),
            controller: controller,
            layout: pagedLayout,
          ),
        ),
        actions: _buildBottomActions(viewState, controller),
      );
    }
    final total = viewState.episodes.isEmpty ? 1 : viewState.episodes.length;
    final currentIndex = viewState.currentEpisodeIndex;
    final current = currentIndex < 0 ? 1 : currentIndex + 1;
    return ReaderBottomBarConfig(
      showProgress: viewState.preferences.showProgressIndicator,
      progress: ReaderProgressConfig(
        current: current,
        total: total,
        previousEnabled: viewState.hasPreviousEpisode,
        nextEnabled: viewState.hasNextEpisode,
        onPrevious: () => _switchToPreviousEpisode(controller),
        onNext: () => _switchToNextEpisode(controller),
        onChanged: (_) {},
        onChangeEnd: (value) => _openEpisodeBySlider(value, viewState, controller),
      ),
      actions: _buildBottomActions(viewState, controller),
    );
  }

  List<ReaderToolbarAction> _buildBottomActions(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    return [
      ReaderToolbarAction(
        id: 'catalog',
        icon: Icons.format_list_bulleted,
        label: '目录',
        onPressed: () => _showChapterListSheet(viewState, controller),
      ),
      ReaderToolbarAction(
        id: 'bookmark',
        icon: Icons.bookmarks_outlined,
        label: '书签',
        onPressed: () => _showBookmarkSheet(viewState, controller),
      ),
      ReaderToolbarAction(
        id: 'display',
        icon: Icons.tune,
        label: '显示',
        onPressed: () => _showDisplaySettingsSheet(viewState, controller),
      ),
      ReaderToolbarAction(
        id: 'cache',
        icon: Icons.download_for_offline_outlined,
        label: '缓存',
        onPressed: () => _showPlaceholder('章节缓存将在后续阶段接入'),
      ),
      ReaderToolbarAction(
        id: 'mode',
        icon: Icons.view_stream_outlined,
        label: '模式',
        onPressed: () => _showPlaceholder('阅读模式将在后续阶段接入'),
      ),
    ];
  }

  Widget _buildReaderList(
    NovelReaderViewState viewState,
    NovelReaderTypography typography,
    ImageRequestHeaderBuilder imageHeaderBuilder,
    ForumWebViewExternalLauncher externalLauncher,
  ) {
    final children = <Widget>[
      if (viewState.preferences.showChapterTitle) ...[
        Text(
          viewState.currentEpisode.episodeTitle,
          key: const Key('novel-reader-inline-chapter-title'),
          style: typography.chapterTitle,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: viewState.preferences.paragraphSpacing * 1.6),
      ],
      NovelReaderDocumentView(
        document: viewState.document,
        typography: typography,
        paragraphSpacing: viewState.preferences.paragraphSpacing,
        imageHeaderBuilder: imageHeaderBuilder,
        onLinkTap: (link) => _openReaderLink(link, externalLauncher),
        highlightedResult: viewState.currentSearchResult,
        nodeKeyBuilder: _nodeKeyFor,
      ),
      if (viewState.nextEpisode != null) ...[
        SizedBox(height: viewState.preferences.paragraphSpacing * 2),
        NovelReaderNextChapterTransition(
          nextEpisode: viewState.nextEpisode!,
          onPressed: () => _openDifferentEpisode(
            () => ref
                .read(novelReaderControllerProvider(_args).notifier)
                .goToNextEpisode(),
          ),
        ),
      ],
    ];
    return ListView(
      key: const Key('novel-reader-paragraph-list'),
      controller: _scrollController,
      padding: EdgeInsets.all(viewState.preferences.pagePadding),
      children: [
        Center(
          child: ConstrainedBox(
            key: const Key('novel-reader-content-column'),
            constraints: BoxConstraints(maxWidth: _safeContentMaxWidth(typography)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  NovelReaderPageLayout _buildPagedLayout(
    NovelReaderViewState viewState,
    NovelReaderTypography typography,
    BoxConstraints constraints,
  ) {
    final horizontalPadding = viewState.preferences.pagePadding * 2;
    final verticalPadding = viewState.preferences.pagePadding * 2;
    final contentMaxWidth = _safeContentMaxWidth(typography);
    final availableWidth = (constraints.maxWidth - horizontalPadding)
        .clamp(160.0, contentMaxWidth)
        .toDouble();
    final availableHeight =
        (constraints.maxHeight - verticalPadding).clamp(160.0, 10000.0).toDouble();
    final layout = _paginator.paginate(
      document: viewState.document,
      typography: NovelReaderPaginationMetrics(
        bodyFontSize: typography.body.fontSize ?? viewState.preferences.fontSize,
        bodyLineHeight: typography.body.height ?? viewState.preferences.lineHeight,
        headingFontSize:
            typography.chapterTitle.fontSize ?? viewState.preferences.fontSize + 4,
        headingLineHeight:
            typography.chapterTitle.height ?? viewState.preferences.lineHeight,
        paragraphSpacing: viewState.preferences.paragraphSpacing,
      ),
      viewportSize: NovelReaderViewport(
        width: availableWidth,
        height: availableHeight,
      ),
    );
    _currentPagedLayout = layout;
    return layout;
  }

  int _ensurePagedController(
    NovelReaderViewState viewState,
    NovelReaderPageLayout layout,
  ) {
    final flowMode = viewState.preferences.flowMode;
    final episodeId = viewState.currentEpisode.episodeId;
    final shouldReset = _pageController == null ||
        _pagedEpisodeId != episodeId ||
        _pagedFlowMode != flowMode;
    if (shouldReset) {
      final oldController = _pageController;
      _currentPageIndex = _progressPolicy.restorePageIndex(
        viewState.progressSnapshot,
        layout: layout,
      );
      _pageController = PageController(initialPage: _currentPageIndex);
      _pagedEpisodeId = episodeId;
      _pagedFlowMode = flowMode;
      _pagedPageCount = layout.pageCount;
      if (oldController != null) {
        _disposePageControllerAfterFrame(oldController);
      }
      return _currentPageIndex;
    }

    final pageCountChanged = _pagedPageCount != layout.pageCount;
    final clamped = pageCountChanged
        ? _progressPolicy.restorePageIndex(viewState.progressSnapshot, layout: layout)
        : layout.clampPageIndex(_currentPageIndex);
    _pagedPageCount = layout.pageCount;
    if (clamped != _currentPageIndex) {
      _currentPageIndex = clamped;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _pageController;
        if (!mounted || controller == null || !controller.hasClients) {
          return;
        }
        controller.jumpToPage(clamped);
        unawaited(
          ref
              .read(novelReaderControllerProvider(_args).notifier)
              .onPagedPageChanged(clamped, layout),
        );
      });
    }
    return _currentPageIndex;
  }

  void _resetPagedController() {
    final oldController = _pageController;
    if (oldController == null) {
      return;
    }
    _pageController = null;
    _pagedEpisodeId = null;
    _pagedFlowMode = null;
    _pagedPageCount = null;
    _currentPageIndex = 0;
    _disposePageControllerAfterFrame(oldController);
  }

  void _disposePageControllerAfterFrame(PageController controller) {
    if (!_pendingPageControllerDisposals.add(controller)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingPageControllerDisposals.remove(controller);
      controller.dispose();
    });
  }

  Widget _buildPagedReader(
    NovelReaderViewState viewState,
    NovelReaderTypography typography,
    ImageRequestHeaderBuilder imageHeaderBuilder,
    ForumWebViewExternalLauncher externalLauncher,
    NovelReaderPageLayout layout,
  ) {
    return PageView.builder(
      key: const Key('novel-reader-paged-view'),
      controller: _pageController,
      reverse: viewState.preferences.flowMode == NovelReaderFlowMode.pagedRtl,
      itemCount: layout.pageCount,
      onPageChanged: (index) {
        _currentPageIndex = layout.clampPageIndex(index);
        _overlayController.hideMenu();
        unawaited(
          ref
              .read(novelReaderControllerProvider(_args).notifier)
              .onPagedPageChanged(_currentPageIndex, layout),
        );
      },
      itemBuilder: (context, index) {
        return SingleChildScrollView(
          key: Key('novel-reader-page-$index'),
          padding: EdgeInsets.all(viewState.preferences.pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _safeContentMaxWidth(typography)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index == 0 && viewState.preferences.showChapterTitle) ...[
                    Text(
                      viewState.currentEpisode.episodeTitle,
                      key: const Key('novel-reader-inline-chapter-title'),
                      style: typography.chapterTitle,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: viewState.preferences.paragraphSpacing * 1.6),
                  ],
                  NovelReaderDocumentView(
                    document: layout.documentForPage(index),
                    typography: typography,
                    paragraphSpacing: viewState.preferences.paragraphSpacing,
                    imageHeaderBuilder: imageHeaderBuilder,
                    onLinkTap: (link) => _openReaderLink(link, externalLauncher),
                    highlightedResult: viewState.currentSearchResult,
                    nodeKeyBuilder: _nodeKeyFor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_isProgrammaticScrollChange) {
      return;
    }
    _overlayController.hideMenu();
    ref
        .read(novelReaderControllerProvider(_args).notifier)
        .onScrollOffsetChanged(
          _scrollController.offset,
          maxScrollExtent: _scrollController.position.maxScrollExtent,
        );
  }

  void _restoreOffsetIfNeeded({
    required String episodeId,
    required double offset,
  }) {
    if (_hasRestoredOffset || offset <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _hasRestoredOffset) {
        return;
      }
      final current = ref.read(novelReaderControllerProvider(_args)).value;
      if (current?.currentEpisode.episodeId != episodeId) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _isProgrammaticScrollChange = true;
      try {
        _scrollController.jumpTo(offset.clamp(0.0, max).toDouble());
      } finally {
        _isProgrammaticScrollChange = false;
      }
      _hasRestoredOffset = true;
    });
  }

  Future<void> _popReader() async {
    await _saveVisibleProgressNow();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _switchToPreviousEpisode(NovelReaderController controller) async {
    await _openDifferentEpisode(() => controller.goToPreviousEpisode());
  }

  Future<void> _switchToNextEpisode(NovelReaderController controller) async {
    await _openDifferentEpisode(() => controller.goToNextEpisode());
  }

  Future<void> _openEpisodeBySlider(
    double value,
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    if (viewState.episodes.isEmpty) {
      return;
    }
    final index = value.round().clamp(0, viewState.episodes.length - 1).toInt();
    final episode = viewState.episodes[index];
    if (episode.episodeId == viewState.currentEpisode.episodeId) {
      return;
    }
    await _openDifferentEpisode(
      () => controller.openEpisodeFromCatalog(episode.episodeId),
    );
  }

  Future<void> _openDifferentEpisode(Future<void> Function() action) async {
    await _saveVisibleProgressNow();
    _hasRestoredOffset = false;
    if (_scrollController.hasClients) {
      _isProgrammaticScrollChange = true;
      try {
        _scrollController.jumpTo(0);
      } finally {
        _isProgrammaticScrollChange = false;
      }
    }
    _overlayController.hideMenu();
    await action();
  }

  Future<void> _saveVisibleProgressNow() async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState == null) {
      return;
    }
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    if (!_isPagedMode(viewState.preferences.flowMode)) {
      final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
      final maxScrollExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      await controller.saveCurrentProgressNow(
        _progressPolicy.verticalSnapshot(
          novelId: widget.novelId,
          episodeId: viewState.currentEpisode.episodeId,
          scrollOffset: offset,
          maxScrollExtent: maxScrollExtent,
        ),
      );
      return;
    }
    final layout = _currentPagedLayout;
    if (layout == null) {
      return;
    }
    await controller.saveCurrentProgressNow(
      _progressPolicy.pagedSnapshot(
        novelId: widget.novelId,
        episodeId: viewState.currentEpisode.episodeId,
        flowMode: viewState.preferences.flowMode,
        pageIndex: _currentPageIndex,
        layout: layout,
      ),
    );
  }

  void _handlePagedSideTap({
    required bool isLeftTap,
    required NovelReaderViewState viewState,
    required NovelReaderController controller,
    required NovelReaderPageLayout layout,
  }) {
    final isRtl = viewState.preferences.flowMode == NovelReaderFlowMode.pagedRtl;
    final shouldGoNext = isRtl ? isLeftTap : !isLeftTap;
    if (shouldGoNext) {
      _goToNextPageOrEpisode(
        viewState: viewState,
        controller: controller,
        layout: layout,
      );
      return;
    }
    _goToPreviousPageOrEpisode(
      viewState: viewState,
      controller: controller,
      layout: layout,
    );
  }

  void _goToPreviousPageOrEpisode({
    required NovelReaderViewState viewState,
    required NovelReaderController controller,
    required NovelReaderPageLayout layout,
  }) {
    final current = layout.clampPageIndex(_currentPageIndex);
    if (current > 0) {
      _jumpToPagedIndex(
        current - 1,
        controller: controller,
        layout: layout,
      );
      return;
    }
    if (viewState.hasPreviousEpisode) {
      unawaited(_openDifferentEpisode(() => controller.goToPreviousEpisode()));
    }
  }

  void _goToNextPageOrEpisode({
    required NovelReaderViewState viewState,
    required NovelReaderController controller,
    required NovelReaderPageLayout layout,
  }) {
    final current = layout.clampPageIndex(_currentPageIndex);
    if (current < layout.pageCount - 1) {
      _jumpToPagedIndex(
        current + 1,
        controller: controller,
        layout: layout,
      );
      return;
    }
    if (viewState.hasNextEpisode) {
      unawaited(_openDifferentEpisode(() => controller.goToNextEpisode()));
    }
  }

  void _jumpToPagedIndex(
    int pageIndex, {
    required NovelReaderController controller,
    required NovelReaderPageLayout layout,
  }) {
    final target = layout.clampPageIndex(pageIndex);
    _currentPageIndex = target;
    _overlayController.hideMenu();
    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(target);
    }
    unawaited(controller.onPagedPageChanged(target, layout));
  }

  Future<void> _showChapterListSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    final selected = await showModalBottomSheet<NovelEpisodeItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => NovelReaderChapterListSheet(viewState: viewState),
    );
    if (selected == null || selected.episodeId == viewState.currentEpisode.episodeId) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _openDifferentEpisode(
      () => controller.openEpisodeFromCatalog(selected.episodeId),
    );
  }

  Future<void> _showSearchSheet(NovelReaderViewState viewState) async {
    _overlayController.hideMenu();
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    final selected = await showModalBottomSheet<NovelReaderSearchResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => NovelReaderSearchSheet(
        initialKeyword: viewState.searchKeyword,
        initialResults: viewState.searchResults,
        onSearch: (keyword) {
          controller.searchInCurrentChapter(keyword);
          return ref.read(novelReaderControllerProvider(_args)).value?.searchResults ??
              const <NovelReaderSearchResult>[];
        },
        onClear: controller.clearSearch,
      ),
    );
    if (selected == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    controller.selectSearchResult(selected.resultId);
    await _jumpToAnchor(selected.anchor);
  }

  Future<void> _showBookmarkSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    _overlayController.hideMenu();
    final action = await showModalBottomSheet<_BookmarkSheetAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => NovelReaderBookmarkSheet(
        bookmarks: viewState.currentEpisodeBookmarks,
      ),
    );
    if (action == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    switch (action.type) {
      case _BookmarkSheetActionType.add:
        await controller.addBookmarkAtCurrentPosition(_currentAnchor(viewState));
        if (!mounted) {
          return;
        }
        _showPlaceholder('已添加书签');
        break;
      case _BookmarkSheetActionType.open:
        final bookmark = action.bookmark;
        if (bookmark != null) {
          await _jumpToAnchor(bookmark.anchor);
        }
        break;
      case _BookmarkSheetActionType.remove:
        final bookmark = action.bookmark;
        if (bookmark != null) {
          await controller.removeBookmark(bookmark.bookmarkId);
          if (!mounted) {
            return;
          }
          _showPlaceholder('已移除书签');
        }
        break;
    }
  }

  void _showDisplaySettingsSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    _overlayController.hideMenu();
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: NovelReaderDisplaySettingsSheet(
            preferences: viewState.preferences,
            onPreferencesChanged: controller.updatePreferences,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleEpisodeBookmark(NovelReaderViewState viewState) async {
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    await controller.toggleCurrentEpisodeBookmark();
    if (!mounted) {
      return;
    }
    final latest = ref.read(novelReaderControllerProvider(_args)).value;
    final isBookmarked =
        latest?.hasCurrentEpisodeBookmark ?? !viewState.hasCurrentEpisodeBookmark;
    _showPlaceholder(isBookmarked ? '已添加书签' : '已移除书签');
  }

  GlobalKey _nodeKeyFor(String nodeId) {
    return _nodeKeys.putIfAbsent(nodeId, () => GlobalKey());
  }

  NovelReaderTextAnchor _currentAnchor(NovelReaderViewState viewState) {
    final layout = _currentPagedLayout;
    if (_isPagedMode(viewState.preferences.flowMode) && layout != null) {
      final pageIndex = layout.clampPageIndex(_currentPageIndex);
      return NovelReaderTextAnchor(
        episodeId: viewState.currentEpisode.episodeId,
        nodeId: layout.anchorForPage(pageIndex),
        pageIndex: pageIndex,
        progressPercent:
            layout.pageCount <= 1 ? 0 : pageIndex / (layout.pageCount - 1),
      );
    }
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final max = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    return NovelReaderTextAnchor(
      episodeId: viewState.currentEpisode.episodeId,
      scrollOffset: offset,
      progressPercent: max <= 0 ? 0 : (offset / max).clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<void> _jumpToAnchor(NovelReaderTextAnchor anchor) async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState == null) {
      return;
    }
    if (anchor.episodeId != viewState.currentEpisode.episodeId) {
      await _openDifferentEpisode(
        () => ref
            .read(novelReaderControllerProvider(_args).notifier)
            .openEpisodeFromCatalog(anchor.episodeId),
      );
      if (!mounted) {
        return;
      }
    }
    final latest = ref.read(novelReaderControllerProvider(_args)).value;
    if (latest == null) {
      return;
    }
    if (_isPagedMode(latest.preferences.flowMode)) {
      final layout = _currentPagedLayout;
      if (layout == null) {
        return;
      }
      final anchorIndex = layout.pageIndexForAnchor(anchor.nodeId);
      _jumpToPagedIndex(
        anchorIndex >= 0 ? anchorIndex : anchor.pageIndex,
        controller: ref.read(novelReaderControllerProvider(_args).notifier),
        layout: layout,
      );
      return;
    }
    final nodeId = anchor.nodeId;
    if (nodeId != null) {
      final context = _nodeKeys[nodeId]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          alignment: 0.16,
        );
        return;
      }
    }
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(anchor.scrollOffset.clamp(0.0, max).toDouble());
    }
  }

  Future<void> _openSourceThread(NovelReaderViewState viewState) async {
    final tid = (viewState.novel?.sourceTid.trim().isNotEmpty == true)
        ? viewState.novel!.sourceTid
        : viewState.currentEpisode.sourceTid;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: tid, subject: _novelTitle(viewState)),
      ),
    );
  }

  Future<void> _openReaderLink(
    NovelReaderLink link,
    ForumWebViewExternalLauncher externalLauncher,
  ) async {
    final tid = link.tid;
    if (tid != null && tid.trim().isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThreadDetailPage(tid: tid, subject: link.text),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      return;
    }
    final launched = await externalLauncher.launch(uri);
    if (!mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接打开失败')),
    );
  }

  void _showPlaceholder(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _novelTitle(NovelReaderViewState viewState) {
    final title = viewState.novel?.title.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final episodeTitle = viewState.currentEpisode.episodeTitle.trim();
    if (episodeTitle.isNotEmpty) {
      return episodeTitle;
    }
    return widget.novelId;
  }

  bool _isPagedMode(NovelReaderFlowMode flowMode) {
    return flowMode != NovelReaderFlowMode.vertical;
  }

  double _safeContentMaxWidth(NovelReaderTypography typography) {
    return typography.contentMaxWidth < 160 ? 160 : typography.contentMaxWidth;
  }
}

class NovelReaderChapterListSheet extends StatefulWidget {
  const NovelReaderChapterListSheet({
    super.key,
    required this.viewState,
  });

  final NovelReaderViewState viewState;

  static const double itemExtent = 72;

  @override
  State<NovelReaderChapterListSheet> createState() =>
      _NovelReaderChapterListSheetState();
}

class _NovelReaderChapterListSheetState extends State<NovelReaderChapterListSheet> {
  late final ScrollController _scrollController;
  String _keyword = '';

  NovelReaderViewState get viewState => widget.viewState;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEpisodes = _filteredEpisodes();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          key: const Key('novel-reader-chapter-list-sheet'),
          children: [
            ReaderSheetTitle(title: '目录'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('novel-reader-chapter-search-field'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索章节',
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _keyword = value.trim();
                  });
                },
              ),
            ),
            Expanded(
              child: filteredEpisodes.isEmpty
                  ? const Center(
                      key: Key('novel-reader-chapter-search-empty'),
                      child: Text('没有匹配的章节'),
                    )
                  : ListView.builder(
                      controller: _keyword.isEmpty ? _scrollController : null,
                      itemExtent: NovelReaderChapterListSheet.itemExtent,
                      itemCount: filteredEpisodes.length,
                      itemBuilder: (context, index) {
                        return _ChapterListTile(
                          episode: filteredEpisodes[index],
                          currentEpisodeId: viewState.currentEpisode.episodeId,
                          readingProgressEpisodeId:
                              viewState.readingProgress?.episodeId,
                          bookmarkEpisodeIds: viewState.bookmarkEpisodeIds,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToCurrentEpisode() {
    if (!mounted || _keyword.isNotEmpty || !_scrollController.hasClients) {
      return;
    }
    final offset = _currentEpisodeInitialOffset();
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return;
    }
    _scrollController.jumpTo(offset.clamp(0.0, max).toDouble());
  }

  double _currentEpisodeInitialOffset() {
    final currentIndex = viewState.currentEpisodeIndex;
    if (currentIndex <= 0) {
      return 0;
    }
    final anchoredIndex = currentIndex <= 2 ? 0 : currentIndex - 2;
    return anchoredIndex * NovelReaderChapterListSheet.itemExtent;
  }

  List<NovelEpisodeItem> _filteredEpisodes() {
    final keyword = _keyword.toLowerCase();
    if (keyword.isEmpty) {
      return viewState.episodes;
    }
    return viewState.episodes.where((episode) {
      return episode.episodeTitle.toLowerCase().contains(keyword) ||
          (episode.datelineText ?? '').toLowerCase().contains(keyword) ||
          (episode.sourcePid ?? '').toLowerCase().contains(keyword);
    }).toList(growable: false);
  }
}

class _ChapterListTile extends StatelessWidget {
  const _ChapterListTile({
    required this.episode,
    required this.currentEpisodeId,
    required this.readingProgressEpisodeId,
    required this.bookmarkEpisodeIds,
  });

  final NovelEpisodeItem episode;
  final String currentEpisodeId;
  final String? readingProgressEpisodeId;
  final Set<String> bookmarkEpisodeIds;

  @override
  Widget build(BuildContext context) {
    final isCurrent = episode.episodeId == currentEpisodeId;
    final isLastRead =
        !isCurrent && episode.episodeId == readingProgressEpisodeId;
    final isBookmarked = bookmarkEpisodeIds.contains(episode.episodeId);
    return ListTile(
      key: Key('novel-reader-chapter-${episode.episodeId}'),
      selected: isCurrent,
      leading: Icon(
        isBookmarked
            ? Icons.bookmark
            : isCurrent
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
      ),
      title: Text(
        episode.episodeTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: episode.datelineText == null
          ? null
          : Text(
              episode.datelineText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Wrap(
        spacing: 6,
        children: [
          if (isBookmarked)
            Text(
              '书签',
              key: Key('novel-reader-chapter-bookmark-${episode.episodeId}'),
            ),
          if (isCurrent) const Text('当前') else if (isLastRead) const Text('上次阅读'),
        ],
      ),
      onTap: () => Navigator.of(context).pop(episode),
    );
  }
}

class NovelReaderNextChapterTransition extends StatelessWidget {
  const NovelReaderNextChapterTransition({
    super.key,
    required this.nextEpisode,
    required this.onPressed,
  });

  final NovelEpisodeItem nextEpisode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('novel-reader-next-chapter-transition'),
      child: OutlinedButton.icon(
        key: const Key('novel-reader-next-chapter-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward),
        label: Text('下一章：${nextEpisode.episodeTitle}'),
      ),
    );
  }
}

class NovelReaderSearchSheet extends StatefulWidget {
  const NovelReaderSearchSheet({
    super.key,
    required this.initialKeyword,
    required this.initialResults,
    required this.onSearch,
    required this.onClear,
  });

  final String initialKeyword;
  final List<NovelReaderSearchResult> initialResults;
  final List<NovelReaderSearchResult> Function(String keyword) onSearch;
  final VoidCallback onClear;

  @override
  State<NovelReaderSearchSheet> createState() => _NovelReaderSearchSheetState();
}

class _NovelReaderSearchSheetState extends State<NovelReaderSearchSheet> {
  late final TextEditingController _controller;
  late List<NovelReaderSearchResult> _results;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
    _results = widget.initialResults;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          key: const Key('novel-reader-search-sheet'),
          children: [
            ReaderSheetTitle(title: '本章搜索'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('novel-reader-search-field'),
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            widget.onClear();
                            setState(
                              () => _results = const <NovelReaderSearchResult>[],
                            );
                          },
                        ),
                  hintText: '搜索当前章节',
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _results = widget.onSearch(value);
                  });
                },
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      key: Key('novel-reader-search-empty'),
                      child: Text('没有搜索结果'),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return ListTile(
                          key: Key('novel-reader-search-result-${result.resultId}'),
                          leading: Text('${index + 1}'),
                          title: Text(
                            result.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('位置 ${result.anchor.textOffset}'),
                          onTap: () => Navigator.of(context).pop(result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class NovelReaderBookmarkSheet extends StatelessWidget {
  const NovelReaderBookmarkSheet({
    super.key,
    required this.bookmarks,
  });

  final List<NovelReaderBookmark> bookmarks;

  @override
  Widget build(BuildContext context) {
    final positionBookmarks = bookmarks
        .where((bookmark) => !bookmark.bookmarkId.startsWith('episode-bookmark:'))
        .toList(growable: false);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          key: const Key('novel-reader-bookmark-sheet'),
          children: [
            ReaderSheetTitle(title: '书签'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.icon(
                key: const Key('novel-reader-add-position-bookmark'),
                onPressed: () => Navigator.of(context).pop(
                  const _BookmarkSheetAction.add(),
                ),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('添加当前位置'),
              ),
            ),
            Expanded(
              child: positionBookmarks.isEmpty
                  ? const Center(
                      key: Key('novel-reader-bookmark-empty'),
                      child: Text('本章还没有位置书签'),
                    )
                  : ListView.builder(
                      itemCount: positionBookmarks.length,
                      itemBuilder: (context, index) {
                        final bookmark = positionBookmarks[index];
                        return ListTile(
                          key: Key('novel-reader-bookmark-${bookmark.bookmarkId}'),
                          leading: const Icon(Icons.bookmark),
                          title: Text(
                            bookmark.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(bookmark.title),
                          onTap: () => Navigator.of(context).pop(
                            _BookmarkSheetAction.open(bookmark),
                          ),
                          trailing: IconButton(
                            key: Key(
                              'novel-reader-remove-bookmark-${bookmark.bookmarkId}',
                            ),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => Navigator.of(context).pop(
                              _BookmarkSheetAction.remove(bookmark),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BookmarkSheetActionType {
  add,
  open,
  remove,
}

class _BookmarkSheetAction {
  const _BookmarkSheetAction.add()
      : type = _BookmarkSheetActionType.add,
        bookmark = null;

  const _BookmarkSheetAction.open(this.bookmark)
      : type = _BookmarkSheetActionType.open;

  const _BookmarkSheetAction.remove(this.bookmark)
      : type = _BookmarkSheetActionType.remove;

  final _BookmarkSheetActionType type;
  final NovelReaderBookmark? bookmark;
}
