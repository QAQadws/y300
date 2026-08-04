import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_catalog_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_management_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_tile.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_filter_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_header.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_metadata_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_misc_sections.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';
import 'package:y300/features/library_shared/presentation/services/route_content_presentation_guard.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_shelf_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/widgets/cover_focal_point_picker.dart';
import 'package:y300/features/library_shared/presentation/widgets/library_sort_option_tile.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 统一详情页骨架（Phase 4）
///
/// 设计要点：
/// 1. 顶部视觉区是一个整体：背景模糊图 + 封面 + 元信息。
/// 2. AppBar 标题在顶部展开态隐藏，滚动折叠到阈值后再显示。
/// 3. 详情逻辑仅依赖 DetailModuleAdapter，避免与具体模块耦合。
class UnifiedDetailPage extends StatefulWidget {
  const UnifiedDetailPage({
    super.key,
    required this.adapter,
    required this.workId,
    required this.onOpenReader,
    required this.onOpenThread,
    this.imageHeaderBuilder,
    this.pickCoverImage,
    this.shelfRefreshBus,
    this.chapterStatus,
    this.chapterModeControl,
    this.onOpenChapter,
    this.onContinue,
    this.onRefreshCompleted,
    this.onFirstContentPresented,
  });

  final DetailModuleAdapter adapter;
  final String workId;
  final Future<void> Function(BuildContext context, ReaderRouteTarget target)
  onOpenReader;
  final Future<void> Function(BuildContext context, ThreadRouteTarget target)
  onOpenThread;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  /// 选择本地封面图片的回调，返回所选图片的本地路径（取消返回 null）。
  ///
  /// 由具体模块外壳（如漫画详情页）用各自的图片选择器注入，使本共享页不直接
  /// 依赖 image_picker。仅当 adapter 实现 [DetailCoverEditor] 时才会被调用。
  final Future<String?> Function()? pickCoverImage;
  final LibraryShelfRefreshBus? shelfRefreshBus;
  final Widget? chapterStatus;
  final Widget? chapterModeControl;
  final Future<void> Function(BuildContext context, LibraryChapterItem chapter)?
  onOpenChapter;
  final Future<void> Function(BuildContext context, ReaderRouteTarget target)?
  onContinue;
  final Future<void> Function(DetailRefreshResult result)? onRefreshCompleted;
  final FutureOr<void> Function(
    LibraryDetailHeader header,
    List<LibraryChapterItem> chapters,
  )?
  onFirstContentPresented;

  @override
  State<UnifiedDetailPage> createState() => _UnifiedDetailPageState();
}

class _UnifiedDetailPageState extends State<UnifiedDetailPage> {
  // 阈值适当降低，确保常见拖动距离能稳定触发折叠标题显示。
  static const double _collapsedTitleRevealOffset = 120;
  static const double _chapterDownloadIconSize = 28;

  late final UnifiedDetailController _controller;
  late final ScrollController _scrollController;

  bool _introExpanded = false;
  bool _showCollapsedTitle = false;
  int _lastHandledRefreshSignalSequence = 0;
  final Set<String> _downloadingEpisodeIds = <String>{};
  final Set<String> _readingStateMutationEpisodeIds = <String>{};
  bool _isResettingWorkReading = false;
  Future<void>? _refreshInFlight;
  Listenable? _chapterDownloadActivityListenable;
  final RouteContentPresentationGuard _contentPresentationGuard =
      RouteContentPresentationGuard();

  DetailChapterDownloadAdapter? get _downloadAdapter {
    final adapter = widget.adapter;
    return adapter is DetailChapterDownloadAdapter
        ? adapter as DetailChapterDownloadAdapter
        : null;
  }

  bool get _supportsChapterDownloads => _downloadAdapter != null;

  DetailChapterDownloadActivityAdapter? get _downloadActivityAdapter {
    final adapter = widget.adapter;
    return adapter is DetailChapterDownloadActivityAdapter
        ? adapter as DetailChapterDownloadActivityAdapter
        : null;
  }

  DetailChapterReadStateAdapter? get _readStateAdapter {
    final adapter = widget.adapter;
    return adapter is DetailChapterReadStateAdapter
        ? adapter as DetailChapterReadStateAdapter
        : null;
  }

  bool get _supportsChapterReadState => _readStateAdapter != null;

  bool get _supportsFullRefresh => widget.adapter is DetailFullRefreshAdapter;

  DetailWorkReadingResetAdapter? get _workReadingResetAdapter {
    final adapter = widget.adapter;
    return adapter is DetailWorkReadingResetAdapter
        ? adapter as DetailWorkReadingResetAdapter
        : null;
  }

  DetailChapterManagementAdapter? get _chapterManagementAdapter {
    final adapter = widget.adapter;
    return adapter is DetailChapterManagementAdapter
        ? adapter as DetailChapterManagementAdapter
        : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = UnifiedDetailController(
      adapter: widget.adapter,
      workId: widget.workId,
    );
    _scrollController = ScrollController()..addListener(_handleScroll);
    widget.shelfRefreshBus?.signal.addListener(_handleShelfRefreshSignal);
    _bindChapterDownloadActivity();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
      _scheduleFirstContentPresented();
    });
  }

  @override
  void dispose() {
    widget.shelfRefreshBus?.signal.removeListener(_handleShelfRefreshSignal);
    _chapterDownloadActivityListenable?.removeListener(
      _handleChapterDownloadActivityChanged,
    );
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UnifiedDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shelfRefreshBus, widget.shelfRefreshBus)) {
      oldWidget.shelfRefreshBus?.signal.removeListener(
        _handleShelfRefreshSignal,
      );
      widget.shelfRefreshBus?.signal.addListener(_handleShelfRefreshSignal);
    }
    if (!identical(oldWidget.adapter, widget.adapter)) {
      _bindChapterDownloadActivity();
    }
  }

  void _bindChapterDownloadActivity() {
    final next = _downloadActivityAdapter?.chapterDownloadActivityListenable;
    if (identical(next, _chapterDownloadActivityListenable)) {
      return;
    }
    _chapterDownloadActivityListenable?.removeListener(
      _handleChapterDownloadActivityChanged,
    );
    _chapterDownloadActivityListenable = next;
    next?.addListener(_handleChapterDownloadActivityChanged);
  }

  void _handleChapterDownloadActivityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _isChapterDownloading(String episodeId) {
    if (_downloadingEpisodeIds.contains(episodeId)) {
      return true;
    }
    return _downloadActivityAdapter?.isChapterDownloadActive(
          workId: widget.workId,
          episodeId: episodeId,
        ) ??
        false;
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients &&
        _scrollController.offset >= _collapsedTitleRevealOffset;
    if (shouldShow != _showCollapsedTitle && mounted) {
      setState(() => _showCollapsedTitle = shouldShow);
    }
  }

  void _handleShelfRefreshSignal() {
    final signal = widget.shelfRefreshBus?.signal.value;
    if (signal == null ||
        signal.sequence <= _lastHandledRefreshSignalSequence ||
        !signal.modules.contains(widget.adapter.moduleKey)) {
      return;
    }
    final workId = signal.workId?.trim();
    if (workId == null || workId.isEmpty || workId != widget.workId) {
      return;
    }
    _lastHandledRefreshSignalSequence = signal.sequence;
    _reloadAfterExternalMutation();
  }

  Future<void> _reloadAfterExternalMutation() async {
    await _controller.reload();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _scheduleFirstContentPresented() {
    if (widget.onFirstContentPresented == null) {
      return;
    }
    final routeWorkId = widget.workId;
    final state = _controller.state;
    final header = state.header;
    if (header == null || state.isLoading || state.errorMessage != null) {
      return;
    }
    final chapters = List<LibraryChapterItem>.unmodifiable(state.chapters);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.workId != routeWorkId) {
        return;
      }
      if (!_contentPresentationGuard.tryCommit(routeWorkId)) {
        return;
      }
      try {
        await widget.onFirstContentPresented?.call(header, chapters);
      } catch (error, stackTrace) {
        debugPrint(
          '[UnifiedDetailPage][first_content_callback_failure] '
          'workId=$routeWorkId error=${error.runtimeType}\n$stackTrace',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = _controller.state;
    final header = state.header;
    final topInset = MediaQuery.of(context).padding.top;
    final detailPalette = const UnifiedDetailPaletteResolver().resolve(
      Theme.of(context),
    );
    final headerHasCover = header != null && hasUnifiedDetailCover(header);
    final expandedAppBarForeground = headerHasCover
        ? detailPalette.onHeader
        : detailPalette.collapsedAppBarForeground;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: detailPalette.pageBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _showCollapsedTitle ? 1 : 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          builder: (context, progress, _) {
            final appBarForeground = Color.lerp(
              expandedAppBarForeground,
              detailPalette.collapsedAppBarForeground,
              progress,
            )!;
            return AppBar(
              backgroundColor: detailPalette.collapsedAppBarBackground
                  .withValues(alpha: progress),
              forceMaterialTransparency: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: appBarForeground,
              iconTheme: IconThemeData(color: appBarForeground),
              titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: appBarForeground,
                fontWeight: FontWeight.normal,
              ),
              title: Opacity(
                opacity: progress,
                child: Text(
                  header == null
                      ? ''
                      : LibraryShelfTextResolver.workTitle(
                          l10n,
                          widget.adapter.moduleKey,
                          header.title,
                          header.workId,
                        ),
                  key: const Key('unified-detail-collapsed-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              actions: [
                if (_supportsChapterDownloads)
                  PopupMenuButton<String>(
                    key: const Key('unified-detail-appbar-download'),
                    tooltip: l10n.libraryDetailDownload,
                    icon: const Icon(Icons.file_download),
                    onSelected: _handleDownloadMenuAction,
                    itemBuilder: _downloadMenuItems,
                  ),
                IconButton(
                  key: const Key('unified-detail-appbar-filter'),
                  tooltip: l10n.libraryDetailFilterAndSort,
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showChapterFilterSheet,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text(l10n.libraryDetailRefresh),
                    ),
                    PopupMenuItem(
                      value: 'change-category',
                      child: Text(l10n.libraryDetailChangeCategory),
                    ),
                    if (widget.adapter is DetailMetadataEditor)
                      PopupMenuItem(
                        key: const Key('unified-detail-edit-metadata'),
                        value: 'edit-metadata',
                        child: Text(l10n.libraryDetailEditMetadata),
                      ),
                    if (widget.adapter is DetailCatalogEditor)
                      PopupMenuItem(
                        key: const Key('unified-detail-configure-catalog'),
                        value: 'configure-catalog',
                        child: Text(l10n.libraryDetailConfigureCatalog),
                      ),
                    // 章节长按之外的第二个入口：隐藏全部章节后列表为空，
                    // 长按目标随之消失，只靠长按会把“全部显示”永久锁死。
                    if (_chapterManagementAdapter != null)
                      PopupMenuItem(
                        key: const Key('unified-detail-manage-chapters'),
                        value: 'manage-chapters',
                        child: Text(l10n.libraryDetailManageChapters),
                      ),
                    if (_supportsCoverEditing) ...[
                      PopupMenuItem(
                        key: const Key('unified-detail-set-cover'),
                        value: 'set-custom-cover',
                        child: Text(l10n.libraryDetailSetCustomCover),
                      ),
                      if (_canRemoveCover)
                        PopupMenuItem(
                          key: const Key('unified-detail-remove-cover'),
                          value: 'remove-custom-cover',
                          child: Text(l10n.libraryDetailRemoveCustomCover),
                        ),
                    ],
                    PopupMenuItem(
                      value: 'edit-intro',
                      child: Text(l10n.libraryDetailEditIntro),
                    ),
                  ],
                  onSelected: (value) async {
                    await _handleMoreAction(value);
                  },
                ),
              ],
            );
          },
        ),
      ),
      body: state.isLoading && header == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              // 从屏幕顶部出现刷新指示器。
              edgeOffset: 0,
              displacement: 28,
              elevation: 0,
              onRefresh: _refreshAndShowFeedback,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  if (header != null)
                    SliverToBoxAdapter(
                      child: UnifiedDetailHeaderSection(
                        header: header,
                        moduleKey: widget.adapter.moduleKey,
                        topInset: topInset,
                        palette: detailPalette,
                        imageHeaderBuilder: widget.imageHeaderBuilder,
                        onToggleShelf: () => _showMoveCategorySheet(),
                        onRefresh: _refreshAndShowFeedback,
                        onRefreshLongPress: _supportsFullRefresh
                            ? () => _refreshAndShowFeedback(full: true)
                            : null,
                        onOpenThread: () async {
                          final target = await widget.adapter
                              .getThreadRouteTarget(workId: widget.workId);
                          if (!context.mounted || target == null) {
                            return;
                          }
                          await widget.onOpenThread(context, target);
                        },
                      ),
                    ),
                  if (state.errorMessage != null &&
                      state.errorMessage!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: UnifiedDetailErrorPanel(
                        message: state.errorMessage!,
                        topPadding: header == null
                            ? topInset + kToolbarHeight
                            : 10,
                        onRetry: _retryLoad,
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: UnifiedDetailIntroSection(
                        intro: header.intro?.trim().isNotEmpty == true
                            ? header.intro!
                            : l10n.libraryDetailNoIntro,
                        expanded: _introExpanded,
                        onToggle: () =>
                            setState(() => _introExpanded = !_introExpanded),
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: UnifiedDetailTagStrip(
                        sourceTagName: header.sourceTagName,
                        sourceTypeId: header.sourceTypeId,
                      ),
                    ),
                  if (widget.chapterStatus != null)
                    SliverToBoxAdapter(child: widget.chapterStatus),
                  SliverToBoxAdapter(
                    child: UnifiedDetailChapterToolbar(
                      chapterCount: state.chapters.length,
                      filterSummary: _chapterFilterSummary(state.filters),
                      hasActiveFilter: _hasActiveChapterFilter(state.filters),
                      modeControl: widget.chapterModeControl,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: state.chapters.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    addSemanticIndexes: false,
                    itemBuilder: (context, index) {
                      final chapter = state.chapters[index];
                      return UnifiedDetailChapterTile(
                        tileKey: ValueKey<String>(
                          'unified-detail-chapter-${chapter.episodeId}',
                        ),
                        chapter: chapter,
                        subtitle: _chapterSubtitle(chapter),
                        isDownloading: _isChapterDownloading(chapter.episodeId),
                        downloadIconSize: _chapterDownloadIconSize,
                        onTap: () => _openChapter(chapter),
                        onLongPress: () => _showChapterActions(chapter),
                        onToggleReadState: _supportsChapterReadState
                            ? () => _toggleChapterReadingState(chapter)
                            : null,
                        readStateMutationLocked:
                            _isResettingWorkReading ||
                            _readingStateMutationEpisodeIds.contains(
                              chapter.episodeId,
                            ),
                        onToggleDownload: _supportsChapterDownloads
                            ? () => _toggleChapterDownload(chapter)
                            : null,
                      );
                    },
                  ),
                  // 预留足够底部滚动空间，保证短列表场景也能触发折叠标题阈值。
                  const SliverToBoxAdapter(child: SizedBox(height: 320)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final target = await widget.adapter.getReaderRouteTarget(
            workId: widget.workId,
            preferContinue: true,
          );
          if (!context.mounted || target == null) {
            return;
          }
          final handler = widget.onContinue ?? widget.onOpenReader;
          await handler(context, target);
          if (!context.mounted) {
            return;
          }
          await _controller.reload();
          if (mounted) {
            setState(() {});
          }
        },
        icon: const Icon(Icons.play_arrow),
        label: Text(l10n.libraryDetailContinue),
      ),
    );
  }

  Future<void> _openChapter(LibraryChapterItem chapter) async {
    final customHandler = widget.onOpenChapter;
    if (customHandler != null) {
      await customHandler(context, chapter);
    } else {
      final target = ReaderRouteTarget(
        workId: widget.workId,
        episodeId: chapter.episodeId,
      );
      await widget.onOpenReader(context, target);
    }
    if (!mounted) {
      return;
    }
    await _controller.reload();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleChapterDownload(LibraryChapterItem chapter) async {
    if (_isChapterDownloading(chapter.episodeId)) {
      return;
    }

    if (chapter.isDownloaded) {
      try {
        await _controller.deleteChapterDownload(episodeId: chapter.episodeId);
        if (mounted) {
          setState(() {});
        }
      } catch (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          _showDetailSnackBar(
            l10n.libraryDetailDeleteDownloadFailed(
              LibraryDetailTextResolver.safeError(l10n, error),
            ),
          );
        }
      }
      return;
    }

    setState(() {
      _downloadingEpisodeIds.add(chapter.episodeId);
    });
    try {
      await _controller.markChapterDownloaded(
        episodeId: chapter.episodeId,
        isDownloaded: true,
      );
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showDetailSnackBar(
          l10n.libraryDetailDownloadFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingEpisodeIds.remove(chapter.episodeId);
        });
      }
    }
  }

  Future<void> _toggleChapterReadingState(LibraryChapterItem chapter) async {
    if (_isResettingWorkReading ||
        _readingStateMutationEpisodeIds.contains(chapter.episodeId)) {
      return;
    }
    setState(() {
      _readingStateMutationEpisodeIds.add(chapter.episodeId);
    });
    try {
      await _controller.toggleChapterReadingState(
        episodeId: chapter.episodeId,
        isCurrentlyRead: chapter.isRead,
      );
    } catch (_) {
      if (mounted) {
        _showDetailSnackBar(
          AppLocalizations.of(context).libraryDetailReadStateUpdateFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _readingStateMutationEpisodeIds.remove(chapter.episodeId);
        });
      }
    }
  }

  String _chapterSubtitle(LibraryChapterItem chapter) {
    final date = chapter.publishTimeText ?? '-';
    final sourcePid = chapter.sourcePid?.trim();
    if (sourcePid != null && sourcePid.isNotEmpty) {
      return '$date  Pid:$sourcePid';
    }
    return '$date  Tid:${chapter.sourceTid ?? '-'}';
  }

  List<PopupMenuEntry<String>> _downloadMenuItems(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      PopupMenuItem(
        value: 'download-unread',
        child: Text(l10n.libraryDetailDownloadUnread),
      ),
      PopupMenuItem(
        value: 'download-all',
        child: Text(l10n.libraryDetailDownloadAll),
      ),
    ];
  }

  Future<void> _handleDownloadMenuAction(String value) async {
    final downloadAdapter = _downloadAdapter;
    if (downloadAdapter == null) {
      return;
    }
    try {
      if (value == 'download-unread') {
        await downloadAdapter.downloadUnread(workId: widget.workId);
        return;
      }
      if (value == 'download-all') {
        await downloadAdapter.downloadAll(workId: widget.workId);
      }
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showDetailSnackBar(
          l10n.libraryDetailDownloadFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
      }
    }
  }

  String _chapterFilterSummary(LibraryFilterSet filters) {
    final l10n = AppLocalizations.of(context);
    if (!_hasActiveChapterFilter(filters)) {
      return l10n.libraryDetailAllChapters;
    }
    final labels = <String>[
      if (_supportsChapterDownloads)
        ?_filterSummaryPart(l10n.libraryDetailDownloaded, filters.downloaded),
      if (_supportsChapterReadState)
        ?_filterSummaryPart(l10n.libraryDetailUnread, filters.unread),
      ?_filterSummaryPart(l10n.libraryDetailBookmarked, filters.bookmarked),
    ];
    return labels.isEmpty ? l10n.libraryDetailAllChapters : labels.join(' / ');
  }

  bool _hasActiveChapterFilter(LibraryFilterSet filters) {
    return (_supportsChapterDownloads &&
            filters.downloaded != TriStateFilterValue.ignore) ||
        (_supportsChapterReadState &&
            filters.unread != TriStateFilterValue.ignore) ||
        filters.bookmarked != TriStateFilterValue.ignore;
  }

  String? _filterSummaryPart(String label, TriStateFilterValue value) {
    return switch (value) {
      TriStateFilterValue.ignore => null,
      TriStateFilterValue.include => label,
      TriStateFilterValue.exclude => AppLocalizations.of(
        context,
      ).libraryDetailExcludeFilter(label),
    };
  }

  Future<void> _showChapterFilterSheet() async {
    var selectedFilters = _controller.state.filters;
    if (!_supportsChapterDownloads &&
        selectedFilters.downloaded != TriStateFilterValue.ignore) {
      selectedFilters = selectedFilters.copyWith(
        downloaded: TriStateFilterValue.ignore,
      );
    }
    if (!_supportsChapterReadState &&
        selectedFilters.unread != TriStateFilterValue.ignore) {
      selectedFilters = selectedFilters.copyWith(
        unread: TriStateFilterValue.ignore,
      );
    }
    var selectedDirection = _controller.state.chapterSortOption.direction;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final l10n = AppLocalizations.of(context);
            final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.86;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: SingleChildScrollView(
                  child: Padding(
                    key: const Key('unified-detail-chapter-filter-sheet'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UnifiedDetailSheetSectionHeader(
                          title: l10n.libraryDetailFilter,
                        ),
                        if (_supportsChapterDownloads)
                          UnifiedDetailTriStateLine(
                            lineKey: const Key(
                              'unified-detail-filter-downloaded',
                            ),
                            label: l10n.libraryDetailDownloaded,
                            value: selectedFilters.downloaded,
                            onChanged: (v) => setSheetState(
                              () => selectedFilters = selectedFilters.copyWith(
                                downloaded: v,
                              ),
                            ),
                          ),
                        if (_supportsChapterReadState)
                          UnifiedDetailTriStateLine(
                            lineKey: const Key('unified-detail-filter-unread'),
                            label: l10n.libraryDetailUnread,
                            value: selectedFilters.unread,
                            onChanged: (v) => setSheetState(
                              () => selectedFilters = selectedFilters.copyWith(
                                unread: v,
                              ),
                            ),
                          ),
                        UnifiedDetailTriStateLine(
                          lineKey: const Key(
                            'unified-detail-filter-bookmarked',
                          ),
                          label: l10n.libraryDetailBookmarked,
                          value: selectedFilters.bookmarked,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(
                              bookmarked: v,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        UnifiedDetailSheetSectionHeader(
                          title: l10n.libraryDetailSort,
                        ),
                        LibrarySortOptionTile(
                          key: const Key('unified-detail-sort-source'),
                          label: l10n.libraryDetailSortBySource,
                          selected: true,
                          direction: selectedDirection,
                          onTap: () {
                            setSheetState(() {
                              selectedDirection =
                                  selectedDirection == LibrarySortDirection.asc
                                  ? LibrarySortDirection.desc
                                  : LibrarySortDirection.asc;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: Text(l10n.commonCancel),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: const Key(
                                  'unified-detail-apply-filter-sort',
                                ),
                                onPressed: () async {
                                  await _controller.updateChapterQuery(
                                    filters: selectedFilters,
                                    sortOption: LibraryChapterSortOption(
                                      direction: selectedDirection,
                                    ),
                                  );
                                  if (!mounted || !sheetContext.mounted) {
                                    return;
                                  }
                                  Navigator.of(sheetContext).pop();
                                  setState(() {});
                                },
                                child: Text(l10n.commonApply),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showChapterActions(LibraryChapterItem chapter) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: ValueKey<String>(
                    'unified-detail-chapter-bookmark-action-${chapter.episodeId}',
                  ),
                  leading: Icon(
                    chapter.isBookmarked
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined,
                  ),
                  title: Text(
                    chapter.isBookmarked
                        ? l10n.libraryDetailRemoveBookmark
                        : l10n.libraryDetailAddBookmark,
                  ),
                  onTap: () async {
                    await _controller.markChapterBookmarked(
                      episodeId: chapter.episodeId,
                      isBookmarked: !chapter.isBookmarked,
                    );
                    if (!mounted || !sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    setState(() {});
                  },
                ),
                if (_workReadingResetAdapter != null)
                  ListTile(
                    key: const Key('unified-detail-work-reset-reading-action'),
                    leading: const Icon(Icons.remove_done),
                    title: Text(l10n.libraryDetailResetWorkReading),
                    onTap: () async {
                      if (!sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      await _confirmAndResetWorkReadingState();
                    },
                  ),
                if (_supportsChapterDownloads && chapter.isDownloaded)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(l10n.libraryDetailDeleteChapterDownload),
                    onTap: () async {
                      await _controller.deleteChapterDownload(
                        episodeId: chapter.episodeId,
                      );
                      if (!mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      setState(() {});
                    },
                  ),
                if (_chapterManagementAdapter != null)
                  ListTile(
                    key: const Key('unified-detail-chapter-management-action'),
                    leading: const Icon(Icons.playlist_add_check),
                    title: Text(l10n.libraryDetailManageChapters),
                    onTap: () async {
                      if (!sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      await _showChapterManagementSheet();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChapterManagementSheet() async {
    final adapter = _chapterManagementAdapter;
    if (adapter == null) {
      return;
    }
    var changed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return UnifiedDetailChapterManagementSheet(
          workId: widget.workId,
          adapter: adapter,
          onChanged: () => changed = true,
        );
      },
    );
    // 章节可见性直接决定详情列表与阅读器导航，关闭后必须重新加载一次；
    // 没有任何写入时跳过，避免长列表白重排一遍。
    if (!changed || !mounted) {
      return;
    }
    await _controller.reload();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmAndResetWorkReadingState() async {
    if (_isResettingWorkReading) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.libraryDetailResetReadingTitle),
          content: Text(l10n.libraryDetailResetReadingBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const Key('unified-detail-work-reset-reading-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryDetailResetReadingConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _isResettingWorkReading = true;
    });
    try {
      await _controller.resetWorkReadingState();
    } catch (_) {
      if (mounted) {
        _showDetailSnackBar(
          AppLocalizations.of(context).libraryDetailResetReadingFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResettingWorkReading = false;
        });
      }
    }
  }

  Future<void> _handleMoreAction(String value) async {
    if (value == 'refresh') {
      await _refreshAndShowFeedback();
      return;
    }
    if (value == 'change-category') {
      await _showMoveCategorySheet();
      return;
    }
    if (value == 'edit-metadata') {
      await _showEditMetadataSheet();
      return;
    }
    if (value == 'configure-catalog') {
      await _showCatalogConfigurationSheet();
      return;
    }
    if (value == 'manage-chapters') {
      await _showChapterManagementSheet();
      return;
    }
    if (value == 'set-custom-cover') {
      await _handleSetCustomCover();
      return;
    }
    if (value == 'remove-custom-cover') {
      await _handleRemoveCustomCover();
      return;
    }
    if (value == 'edit-intro') {
      await _showEditIntroDialog();
    }
  }

  Future<void> _refreshAndShowFeedback({bool full = false}) {
    final active = _refreshInFlight;
    if (active != null) {
      return active;
    }
    late final Future<void> guardedRun;
    guardedRun = _performRefreshAndShowFeedback(full: full).whenComplete(() {
      if (identical(_refreshInFlight, guardedRun)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = guardedRun;
    return guardedRun;
  }

  Future<void> _performRefreshAndShowFeedback({required bool full}) async {
    try {
      final result = full
          ? await _controller.refreshFully()
          : await _controller.refresh();
      await widget.onRefreshCompleted?.call(result);
      if (!mounted) {
        return;
      }
      _showDetailSnackBar(_refreshFeedbackMessage(result));
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      _showDetailSnackBar(
        l10n.libraryDetailRefreshFailed(
          LibraryDetailTextResolver.safeError(l10n, error),
        ),
      );
      setState(() {});
    }
  }

  String _refreshFeedbackMessage(DetailRefreshResult result) {
    return LibraryDetailTextResolver.refreshOutcome(
      AppLocalizations.of(context),
      result,
    );
  }

  Future<void> _retryLoad() async {
    await _controller.reload();
    if (mounted) {
      setState(() {});
      _scheduleFirstContentPresented();
    }
  }

  void _showDetailSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEditMetadataSheet() async {
    final editor = widget.adapter is DetailMetadataEditor
        ? widget.adapter as DetailMetadataEditor
        : null;
    final header = _controller.state.header;
    if (editor == null || header == null) {
      return;
    }
    final config = editor.metadataEditorConfig;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return UnifiedDetailMetadataSheet(
          initialTitle: _metadataInitialValue(
            customValue: header.customTitle,
            displayValue: header.title,
            sourceValue: header.sourceTitle,
          ),
          initialAuthor: _metadataInitialValue(
            customValue: header.customAuthor,
            displayValue: header.author,
            sourceValue: header.sourceAuthor,
          ),
          initialTranslationGroup: _metadataInitialValue(
            customValue: header.customTranslationGroup,
            displayValue: header.translationGroup,
            sourceValue: header.sourceTranslationGroup,
          ),
          initialSearchTitle: header.customSearchTitle ?? '',
          titleSourceText: LibraryDetailTextResolver.sourceValue(
            AppLocalizations.of(sheetContext),
            LibraryDetailTextResolver.metadataSourceField(
              AppLocalizations.of(sheetContext),
              LibraryMetadataField.title,
            ),
            header.sourceTitle ?? header.title,
          ),
          authorSourceText: LibraryDetailTextResolver.sourceValue(
            AppLocalizations.of(sheetContext),
            LibraryDetailTextResolver.metadataSourceField(
              AppLocalizations.of(sheetContext),
              LibraryMetadataField.author,
            ),
            header.sourceAuthor ??
                (config.fallbackToDisplaySourceValues ? header.author : null),
          ),
          groupSourceText: LibraryDetailTextResolver.sourceValue(
            AppLocalizations.of(sheetContext),
            LibraryDetailTextResolver.metadataSourceField(
              AppLocalizations.of(sheetContext),
              LibraryMetadataField.translationGroup,
            ),
            header.sourceTranslationGroup ??
                (config.fallbackToDisplaySourceValues
                    ? header.translationGroup
                    : null),
          ),
          fields: config.fields,
          onSave:
              ({
                customTitle,
                customAuthor,
                customTranslationGroup,
                customSearchTitle,
              }) async {
                await editor.updateCustomMetadata(
                  workId: widget.workId,
                  customTitle: customTitle,
                  customAuthor: customAuthor,
                  customTranslationGroup: customTranslationGroup,
                  customSearchTitle: customSearchTitle,
                );
                await _controller.reload();
                if (!mounted) {
                  return;
                }
                setState(() {});
              },
        );
      },
    );
  }

  Future<void> _showCatalogConfigurationSheet() async {
    final editor = widget.adapter is DetailCatalogEditor
        ? widget.adapter as DetailCatalogEditor
        : null;
    if (editor == null) {
      return;
    }

    late final DetailCatalogConfiguration configuration;
    try {
      configuration = await editor.loadCatalogConfiguration(
        workId: widget.workId,
      );
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showDetailSnackBar(
          l10n.libraryDetailCatalogLoadFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return UnifiedDetailCatalogSheet(
          initialCatalogUrl: configuration.initialInputValue,
          sourceCatalogUrl: configuration.sourceCatalogUrl,
          onSave: (catalogUrl) async {
            final outcome = await editor.updateCatalogOverride(
              workId: widget.workId,
              catalogUrl: catalogUrl,
            );
            if (outcome.code == DetailCatalogUpdateOutcomeCode.saved) {
              await _controller.reload();
              if (mounted) {
                setState(() {});
              }
            }
            return outcome;
          },
        );
      },
    );
  }

  /// 是否支持自定义封面编辑：adapter 实现合同且外壳注入了图片选择器。
  bool get _supportsCoverEditing =>
      widget.adapter is DetailCoverEditor && widget.pickCoverImage != null;

  bool get _canRemoveCover {
    final editor = _coverEditor;
    final header = _controller.state.header;
    return editor != null && header != null && editor.canRemoveCover(header);
  }

  DetailCoverEditor? get _coverEditor => widget.adapter is DetailCoverEditor
      ? widget.adapter as DetailCoverEditor
      : null;

  /// 自定义封面：选图 → 焦点选区 → 落盘保存 → 刷新。
  Future<void> _handleSetCustomCover() async {
    final editor = _coverEditor;
    final pick = widget.pickCoverImage;
    if (editor == null || pick == null) {
      return;
    }
    final sourcePath = await pick();
    if (sourcePath == null || sourcePath.trim().isEmpty || !mounted) {
      return;
    }
    final focus = await CoverFocalPointPicker.show(
      context,
      image: FileImage(io.File(sourcePath)),
    );
    if (focus == null || !mounted) {
      return;
    }
    try {
      await editor.setCustomCoverFromLocalFile(
        workId: widget.workId,
        sourceLocalPath: sourcePath,
        focusX: focus.x,
        focusY: focus.y,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      _showDetailSnackBar(
        l10n.libraryDetailCoverUpdateFailed(
          LibraryDetailTextResolver.safeError(l10n, error),
        ),
      );
      return;
    }
    await _controller.reload();
    if (!mounted) {
      return;
    }
    _showDetailSnackBar(AppLocalizations.of(context).libraryDetailCoverUpdated);
    setState(() {});
  }

  Future<void> _handleRemoveCustomCover() async {
    final editor = _coverEditor;
    if (editor == null || !_canRemoveCover) {
      return;
    }
    try {
      await editor.removeCustomCover(workId: widget.workId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      _showDetailSnackBar(
        l10n.libraryDetailCoverRemoveFailed(
          LibraryDetailTextResolver.safeError(l10n, error),
        ),
      );
      return;
    }
    await _controller.reload();
    if (!mounted) {
      return;
    }
    _showDetailSnackBar(AppLocalizations.of(context).libraryDetailCoverRemoved);
    setState(() {});
  }

  Future<void> _showMoveCategorySheet() async {
    final categories = await widget.adapter.loadCategories();
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: categories
                .map(
                  (item) => ListTile(
                    title: Text(
                      LibraryShelfTextResolver.categoryName(
                        AppLocalizations.of(sheetContext),
                        item,
                      ),
                    ),
                    onTap: () async {
                      await widget.adapter.moveWorkToCategory(
                        workId: widget.workId,
                        toCategoryId: item.categoryId,
                      );
                      if (!mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }

  Future<void> _showEditIntroDialog() async {
    final current = _controller.state.header?.intro ?? '';
    final inputController = TextEditingController(text: current);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.libraryDetailEditIntro),
          content: TextField(
            controller: inputController,
            maxLines: 6,
            decoration: InputDecoration(hintText: l10n.libraryDetailIntroHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () async {
                await widget.adapter.updateIntro(
                  workId: widget.workId,
                  intro: inputController.text.trim(),
                );
                await _controller.reload();
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                setState(() {});
              },
              child: Text(l10n.commonSave),
            ),
          ],
        );
      },
    );
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _metadataInitialValue({
  required String? customValue,
  required String? displayValue,
  String? sourceValue,
}) {
  // 编辑框优先展示已保存的自定义值；未自定义时回填当前展示信息，
  // 让用户只改需要调整的字段，仍可清空输入框来恢复来源值。
  return _emptyToNull(customValue ?? '') ??
      _emptyToNull(displayValue ?? '') ??
      _emptyToNull(sourceValue ?? '') ??
      '';
}
