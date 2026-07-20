import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';

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

class _NovelReaderPageState extends ConsumerState<NovelReaderPage>
    with WidgetsBindingObserver {
  late final ScrollController _scrollController;
  late final ReaderOverlayController _overlayController;
  final NovelReaderThemeResolver _themeResolver =
      const NovelReaderThemeResolver();
  final NovelReaderTypographyResolver _typographyResolver =
      const NovelReaderTypographyResolver();
  final NovelReaderProgressPolicy _progressPolicy =
      const NovelReaderProgressPolicy();
  Timer? _displayPreviewThrottle;
  Timer? _displayPersistDebounce;
  NovelReaderPreferences? _pendingDisplayPreferences;
  NovelReaderPreferences? _lastPreviewedDisplayPreferences;
  NovelReaderPreferences? _lastPersistedDisplayPreferences;
  NovelReaderPreferences? _inFlightDisplayPreferences;
  int _displayPersistSerial = 0;
  int _readerSemanticsSuspendCount = 0;
  bool _hasRestoredOffset = false;
  bool _isProgrammaticScrollChange = false;
  bool _allowPopAfterProgressFlush = false;
  bool _isHandlingPop = false;

  NovelReaderArgs get _args => NovelReaderArgs(
    novelId: widget.novelId,
    episodeId: widget.initialEpisodeId,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overlayController = ReaderOverlayController();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayController.dispose();
    _displayPreviewThrottle?.cancel();
    _displayPersistDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveVisibleProgressNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(novelReaderControllerProvider(_args));
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final externalLauncher = ref.watch(forumWebViewExternalLauncherProvider);

    return PopScope<void>(
      canPop: _allowPopAfterProgressFlush,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_flushProgressAndPop());
      },
      child: Scaffold(
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => NovelReaderErrorView(
            error: error,
            onRetry: () => ref.invalidate(novelReaderControllerProvider(_args)),
            onUpdateWork: () => _updateWorkFromErrorView(),
            onOpenThread: () => _openFallbackSourceThread(),
          ),
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
              child: Builder(
                builder: (context) {
                  if (viewState.preferences.flowMode ==
                      NovelReaderFlowMode.vertical) {
                    _restoreOffsetIfNeeded(
                      episodeId: viewState.currentEpisode.episodeId,
                      offset: viewState.currentOffset,
                    );
                  }
                  final reader = ReaderOverlayScaffold(
                    controller: _overlayController,
                    topBar: _buildTopBarConfig(viewState),
                    bottomBar: _buildBottomBarConfig(viewState, controller),
                    bottomSafeFraction: 0.18,
                    child: _buildReaderList(
                      viewState,
                      typography,
                      const NovelForumHtmlRenderThemeFactory().fromPalette(
                        palette,
                      ),
                      imageHeaderBuilder,
                      externalLauncher,
                    ),
                  );
                  final readerSurfaceIdentity =
                      '${viewState.currentEpisode.episodeId}|'
                      '${viewState.document.rawHtmlHash}|'
                      '${viewState.preferences.flowMode.name}';
                  final chromePalette = const ReaderChromePaletteResolver()
                      .resolve(Theme.of(context));
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          excluding: _readerSemanticsSuspendCount > 0,
                          child: KeyedSubtree(
                            key: ValueKey<String>(readerSurfaceIdentity),
                            child: reader,
                          ),
                        ),
                      ),
                      if (viewState.transition != null)
                        Positioned.fill(
                          child: AbsorbPointer(
                            child: ColoredBox(
                              key: const Key('novel-reader-transition-mask'),
                              color: chromePalette.overlayScrim.withValues(
                                alpha: 0.18,
                              ),
                              child: Center(
                                child: DecoratedBox(
                                  key: const Key(
                                    'novel-reader-transition-indicator',
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        chromePalette.transitionCardBackground,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
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
          onPressed: () => _showReaderSnackBar('更多阅读操作将在后续阶段接入'),
        ),
      ],
    );
  }

  ReaderBottomBarConfig _buildBottomBarConfig(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    return ReaderBottomBarConfig(
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
        id: 'display',
        icon: Icons.tune,
        label: '显示',
        onPressed: () => _showDisplaySettingsSheet(viewState, controller),
      ),
    ];
  }

  Widget _buildReaderList(
    NovelReaderViewState viewState,
    NovelReaderTypography typography,
    ForumHtmlThemeContext htmlTheme,
    ImageRequestHeaderBuilder imageHeaderBuilder,
    ForumWebViewExternalLauncher externalLauncher,
  ) {
    if (viewState.preferences.flowMode != NovelReaderFlowMode.vertical) {
      return NovelReaderHtmlPagedSurface(
        rawHtml: viewState.currentContent.rawHtml,
        episode: viewState.currentEpisode,
        preferences: viewState.preferences,
        typography: typography,
        theme: htmlTheme,
        imageReferer: _imageRefererFor(viewState),
        imageHeaderBuilder: imageHeaderBuilder,
        onLinkTap: (link) => _openReaderLink(link, externalLauncher),
        onOpenImage: _openHtmlReaderImage,
        onImageFallback: (request) => _copyNovelImageUrl(request.url),
        onFallbackToVertical: () => _fallbackToVertical(
          ref.read(novelReaderControllerProvider(_args).notifier),
        ),
        onPageChanged: (_) => _overlayController.hideMenu(),
      );
    }
    final children = <Widget>[
      NovelReaderHtmlDocumentView(
        rawHtml: viewState.currentContent.rawHtml,
        episode: viewState.currentEpisode,
        preferences: viewState.preferences,
        typography: typography,
        theme: htmlTheme,
        imageReferer: _imageRefererFor(viewState),
        imageHeaderBuilder: imageHeaderBuilder,
        onLinkTap: (link) => _openReaderLink(link, externalLauncher),
        onOpenImage: _openHtmlReaderImage,
        onImageFallback: (request) => _copyNovelImageUrl(request.url),
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
            constraints: BoxConstraints(
              maxWidth: _safeContentMaxWidth(typography),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_isProgrammaticScrollChange) {
      return;
    }
    if (!_hasRestoredOffset) {
      // Once the user has started a real drag, stop any pending restore from
      // fighting the gesture mid-flight.
      _hasRestoredOffset = true;
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
    if (_hasRestoredOffset) {
      return;
    }
    if (offset <= 0) {
      _hasRestoredOffset = true;
      return;
    }
    final current = ref.read(novelReaderControllerProvider(_args)).value;
    if (current?.transition != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _hasRestoredOffset) {
        return;
      }
      final latest = ref.read(novelReaderControllerProvider(_args)).value;
      if (latest?.transition != null ||
          latest?.currentEpisode.episodeId != episodeId) {
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
    await _flushProgressAndPop();
  }

  Future<void> _flushProgressAndPop() async {
    if (_isHandlingPop) {
      return;
    }
    _isHandlingPop = true;
    try {
      await _saveVisibleProgressNow();
      if (!mounted) {
        return;
      }
      _allowPopAfterProgressFlush = true;
      Navigator.of(context).pop();
    } finally {
      _isHandlingPop = false;
    }
  }

  Future<void> _openDifferentEpisode(Future<bool> Function() action) async {
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
    final didSucceed = await action();
    if (!mounted || didSucceed) {
      return;
    }
    _showReaderSnackBar('章节切换失败，已保留当前章节');
  }

  Future<void> _saveVisibleProgressNow() async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState == null ||
        viewState.preferences.flowMode != NovelReaderFlowMode.vertical) {
      return;
    }
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
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
  }

  Future<void> _fallbackToVertical(NovelReaderController controller) async {
    final current = ref.read(novelReaderControllerProvider(_args)).value;
    if (current == null ||
        current.preferences.flowMode == NovelReaderFlowMode.vertical) {
      return;
    }
    final next = current.persistedPreferences.copyWith(
      flowMode: NovelReaderFlowMode.vertical,
    );
    controller.previewPreferences(next);
    try {
      await controller.commitPreferences(next);
    } catch (_) {
      controller.revertPreferencePreview();
      if (mounted) {
        _showReaderSnackBar('切回滚动模式失败');
      }
    }
  }

  Future<T> _runWithReaderSemanticsSuspended<T>(
    Future<T> Function() action,
  ) async {
    _suspendReaderSemantics();
    try {
      return await action();
    } finally {
      _resumeReaderSemantics();
    }
  }

  void _suspendReaderSemantics() {
    if (!mounted) {
      _readerSemanticsSuspendCount += 1;
      return;
    }
    setState(() {
      _readerSemanticsSuspendCount += 1;
    });
  }

  void _resumeReaderSemantics() {
    if (_readerSemanticsSuspendCount == 0) {
      return;
    }
    if (!mounted) {
      _readerSemanticsSuspendCount -= 1;
      return;
    }
    setState(() {
      _readerSemanticsSuspendCount -= 1;
    });
  }

  Future<void> _showChapterListSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    await _runWithReaderSemanticsSuspended(() async {
      final selected = await showModalBottomSheet<NovelEpisodeItem>(
        context: context,
        showDragHandle: true,
        builder: (context) => Consumer(
          builder: (context, ref, _) {
            final latest =
                ref.watch(novelReaderControllerProvider(_args)).value ??
                viewState;
            return NovelReaderChapterListSheet(viewState: latest);
          },
        ),
      );
      if (selected == null ||
          selected.episodeId == viewState.currentEpisode.episodeId) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _openDifferentEpisode(
        () => controller.openEpisodeFromCatalog(selected.episodeId),
      );
    });
  }

  Future<void> _showSearchSheet(NovelReaderViewState viewState) async {
    _overlayController.hideMenu();
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    await _runWithReaderSemanticsSuspended(() async {
      final selected = await showModalBottomSheet<NovelReaderSearchResult>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => NovelReaderSearchSheet(
          initialKeyword: viewState.searchKeyword,
          initialResults: viewState.searchResults,
          onSearch: (keyword) {
            controller.searchInCurrentChapter(keyword);
            return ref
                    .read(novelReaderControllerProvider(_args))
                    .value
                    ?.searchResults ??
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
    });
  }

  Future<void> _showDisplaySettingsSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    _overlayController.hideMenu();
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.5;
    _pendingDisplayPreferences = viewState.preferences;
    _lastPreviewedDisplayPreferences = viewState.preferences;
    _lastPersistedDisplayPreferences = viewState.persistedPreferences;
    _inFlightDisplayPreferences = null;
    await _runWithReaderSemanticsSuspended(() async {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        builder: (context) => NovelReaderDisplaySettingsSheet(
          initialPreferences: viewState.preferences,
          onPreferencesChanged: (preferences) =>
              _onDisplayPreferencesChanged(preferences, controller),
        ),
      );
      if (!mounted) {
        return;
      }
      await _flushDisplayPreferenceChanges(controller);
    });
  }

  void _onDisplayPreferencesChanged(
    NovelReaderPreferences preferences,
    NovelReaderController controller,
  ) {
    _pendingDisplayPreferences = preferences;
    _scheduleDisplayPreferencePreview(controller);
    _scheduleDisplayPreferencePersist(controller);
  }

  void _scheduleDisplayPreferencePreview(NovelReaderController controller) {
    if (_displayPreviewThrottle?.isActive == true) {
      return;
    }
    _applyPendingDisplayPreview(controller);
    _displayPreviewThrottle = Timer(const Duration(milliseconds: 90), () {
      _displayPreviewThrottle = null;
      _applyPendingDisplayPreview(controller);
    });
  }

  void _applyPendingDisplayPreview(NovelReaderController controller) {
    final preferences = _pendingDisplayPreferences;
    if (preferences == null ||
        preferences == _lastPreviewedDisplayPreferences) {
      return;
    }
    _lastPreviewedDisplayPreferences = preferences;
    controller.previewPreferences(preferences);
  }

  void _scheduleDisplayPreferencePersist(NovelReaderController controller) {
    _displayPersistDebounce?.cancel();
    _displayPersistDebounce = Timer(const Duration(milliseconds: 520), () {
      _displayPersistDebounce = null;
      unawaited(_persistPendingDisplayPreferences(controller));
    });
  }

  Future<void> _flushDisplayPreferenceChanges(
    NovelReaderController controller,
  ) async {
    _displayPreviewThrottle?.cancel();
    _displayPreviewThrottle = null;
    _displayPersistDebounce?.cancel();
    _displayPersistDebounce = null;
    _applyPendingDisplayPreview(controller);
    await _persistPendingDisplayPreferences(controller);
  }

  Future<void> _persistPendingDisplayPreferences(
    NovelReaderController controller,
  ) async {
    final preferences = _pendingDisplayPreferences;
    if (preferences == null ||
        preferences == _lastPersistedDisplayPreferences ||
        preferences == _inFlightDisplayPreferences) {
      return;
    }
    _inFlightDisplayPreferences = preferences;
    final serial = ++_displayPersistSerial;
    try {
      await controller.commitPreferences(preferences);
      if (serial == _displayPersistSerial) {
        _lastPersistedDisplayPreferences = preferences;
      }
    } catch (_) {
      if (!mounted || serial != _displayPersistSerial) {
        return;
      }
      controller.revertPreferencePreview();
      _showReaderSnackBar('显示设置保存失败');
    } finally {
      if (_inFlightDisplayPreferences == preferences) {
        _inFlightDisplayPreferences = null;
      }
    }
  }

  Future<void> _toggleEpisodeBookmark(NovelReaderViewState viewState) async {
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    await controller.toggleCurrentEpisodeBookmark();
    if (!mounted) {
      return;
    }
    final latest = ref.read(novelReaderControllerProvider(_args)).value;
    final isBookmarked =
        latest?.hasCurrentEpisodeBookmark ??
        !viewState.hasCurrentEpisodeBookmark;
    _showReaderSnackBar(isBookmarked ? '已添加书签' : '已移除书签');
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
        builder: (_) =>
            ThreadDetailPage(tid: tid, subject: _novelTitle(viewState)),
      ),
    );
  }

  String _imageRefererFor(NovelReaderViewState viewState) {
    final tid = viewState.currentEpisode.sourceTid.trim();
    if (tid.isEmpty) {
      return AppConfig.siteBaseUrl;
    }
    final page = viewState.currentEpisode.sourcePage;
    return Uri.parse(AppConfig.siteBaseUrl)
        .replace(
          path: '/forum.php',
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': tid,
            'mobile': '2',
            if (page != null && page > 1) 'page': page.toString(),
          },
        )
        .toString();
  }

  Future<void> _openFallbackSourceThread() async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState != null) {
      await _openSourceThread(viewState);
      return;
    }
    final tid =
        _sourceTidFromId(widget.initialEpisodeId) ??
        _sourceTidFromId(widget.novelId) ??
        widget.novelId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: tid, subject: widget.novelId),
      ),
    );
  }

  Future<void> _openReaderLink(
    NovelReaderLink link,
    ForumWebViewExternalLauncher externalLauncher,
  ) async {
    final destination = const YamiboForumLinkResolver().resolve(link.url);
    if (destination?.kind == YamiboForumLinkKind.thread ||
        destination?.kind == YamiboForumLinkKind.threadPost) {
      final tid = destination?.tid;
      if (tid != null && tid.trim().isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadDetailPage(tid: tid, subject: link.text),
          ),
        );
        return;
      }
    }
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
    _showReaderSnackBar('链接打开失败');
  }

  void _openHtmlReaderImage(ThreadImageOpenRequest request) {
    if (request.continuousImages.isEmpty) {
      final entry = request.initialEntry;
      if (entry != null) {
        _copyNovelImageUrl(entry.url);
      }
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadImageReaderPage(
          request: request,
          imageHeaderBuilder: ref.read(imageRequestHeaderBuilderProvider),
        ),
      ),
    );
  }

  Future<void> _copyNovelImageUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    _showReaderSnackBar('图片链接已复制');
  }

  void _showReaderSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        ),
      );
  }

  Future<void> _updateWorkFromErrorView() async {
    final didSucceed = await ref
        .read(novelReaderControllerProvider(_args).notifier)
        .updateWork();
    if (!mounted || didSucceed) {
      return;
    }
    _showReaderSnackBar('作品更新失败，已保留当前章节');
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

  String? _sourceTidFromId(String value) {
    final parts = value.split(':');
    if (parts.length >= 3 && parts.first == 'novel') {
      final tid = parts[2].trim();
      return tid.isEmpty ? null : tid;
    }
    return null;
  }

  double _safeContentMaxWidth(NovelReaderTypography typography) {
    return typography.contentMaxWidth < 160 ? 160 : typography.contentMaxWidth;
  }
}

class NovelReaderChapterListSheet extends StatefulWidget {
  const NovelReaderChapterListSheet({super.key, required this.viewState});

  final NovelReaderViewState viewState;

  static const double itemExtent = 72;

  @override
  State<NovelReaderChapterListSheet> createState() =>
      _NovelReaderChapterListSheetState();
}

class _NovelReaderChapterListSheetState
    extends State<NovelReaderChapterListSheet> {
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
    return viewState.episodes
        .where((episode) {
          return episode.episodeTitle.toLowerCase().contains(keyword) ||
              (episode.datelineText ?? '').toLowerCase().contains(keyword) ||
              (episode.sourcePid ?? '').toLowerCase().contains(keyword);
        })
        .toList(growable: false);
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
          if (isCurrent)
            const Text('当前')
          else if (isLastRead)
            const Text('上次阅读'),
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

class NovelReaderErrorView extends StatelessWidget {
  const NovelReaderErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onUpdateWork,
    required this.onOpenThread,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onUpdateWork;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          key: const Key('novel-reader-error-view'),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    '章节暂时无法显示',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('novel-reader-error-retry'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('novel-reader-error-update-work'),
                        onPressed: onUpdateWork,
                        icon: const Icon(Icons.sync),
                        label: const Text('更新作品'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('novel-reader-error-open-thread'),
                        onPressed: onOpenThread,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('打开原帖'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
                              () =>
                                  _results = const <NovelReaderSearchResult>[],
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
                          key: Key(
                            'novel-reader-search-result-${result.resultId}',
                          ),
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
