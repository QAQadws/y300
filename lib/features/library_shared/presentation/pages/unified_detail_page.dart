import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/media/cover_focal_point.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_tile.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_filter_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_header.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_metadata_sheet.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_misc_sections.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';
import 'package:y300/features/library_shared/presentation/widgets/cover_focal_point_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = UnifiedDetailController(
      adapter: widget.adapter,
      workId: widget.workId,
    );
    _scrollController = ScrollController()..addListener(_handleScroll);
    widget.shelfRefreshBus?.signal.addListener(_handleShelfRefreshSignal);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    widget.shelfRefreshBus?.signal.removeListener(_handleShelfRefreshSignal);
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

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final header = state.header;
    final topInset = MediaQuery.of(context).padding.top;
    final detailPalette = const UnifiedDetailPaletteResolver().resolve(
      Theme.of(context),
    );
    final appBarForeground = _showCollapsedTitle
        ? detailPalette.collapsedAppBarForeground
        : detailPalette.onHeader;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: detailPalette.pageBackground,
      appBar: AppBar(
        backgroundColor: _showCollapsedTitle
            ? detailPalette.collapsedAppBarBackground
            : Colors.transparent,
        forceMaterialTransparency: !_showCollapsedTitle,
        elevation: _showCollapsedTitle ? 1 : 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: appBarForeground,
        iconTheme: IconThemeData(color: appBarForeground),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: appBarForeground,
          fontWeight: FontWeight.w600,
        ),
        title: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _showCollapsedTitle ? 1 : 0,
          child: Text(
            header?.title ?? '',
            key: const Key('unified-detail-collapsed-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '下载',
            icon: const Icon(Icons.file_download),
            onSelected: _handleDownloadMenuAction,
            itemBuilder: _downloadMenuItems,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showChapterFilterSheet,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
              const PopupMenuItem(
                value: 'change-category',
                child: Text('修改分类'),
              ),
              if (widget.adapter is DetailMetadataEditor)
                const PopupMenuItem(
                  key: Key('unified-detail-edit-metadata'),
                  value: 'edit-metadata',
                  child: Text('编辑作品信息'),
                ),
              if (_supportsCoverEditing) ...[
                const PopupMenuItem(
                  key: Key('unified-detail-set-cover'),
                  value: 'set-custom-cover',
                  child: Text('自定义封面'),
                ),
                if (_hasCustomCover)
                  const PopupMenuItem(
                    key: Key('unified-detail-adjust-cover-focus'),
                    value: 'adjust-cover-focus',
                    child: Text('调整封面焦点'),
                  ),
              ],
              const PopupMenuItem(value: 'edit-intro', child: Text('编辑简介')),
              const PopupMenuItem(value: 'add-tag', child: Text('添加标签')),
              const PopupMenuItem(value: 'remove-tag', child: Text('移除标签')),
            ],
            onSelected: (value) async {
              await _handleMoreAction(value);
            },
          ),
        ],
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
                            : '暂无简介',
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
                        customTags: header.customTags,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: UnifiedDetailChapterToolbar(
                      chapterCount: state.chapters.length,
                      filterSummary: _chapterFilterSummary(state.filters),
                      sortSummary: _chapterSortSummary(state.chapterSortOption),
                      sortAscending:
                          state.chapterSortOption.direction ==
                          LibrarySortDirection.asc,
                      onFilterTap: _showChapterFilterSheet,
                      onSortTap: _toggleChapterSortDirection,
                      onDownloadSelected: _handleDownloadMenuAction,
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
                        isDownloading: _downloadingEpisodeIds.contains(
                          chapter.episodeId,
                        ),
                        downloadIconSize: _chapterDownloadIconSize,
                        onTap: () => _openChapter(chapter),
                        onLongPress: () => _showChapterActions(chapter),
                        onToggleBookmark: () => _toggleChapterBookmark(chapter),
                        onToggleDownload: () => _toggleChapterDownload(chapter),
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
          await widget.onOpenReader(context, target);
          if (!context.mounted) {
            return;
          }
          await _controller.reload();
          if (mounted) {
            setState(() {});
          }
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('继续'),
      ),
    );
  }

  Future<void> _openChapter(LibraryChapterItem chapter) async {
    final target = ReaderRouteTarget(
      workId: widget.workId,
      episodeId: chapter.episodeId,
    );
    await widget.onOpenReader(context, target);
    if (!mounted) {
      return;
    }
    await _controller.reload();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleChapterBookmark(LibraryChapterItem chapter) async {
    await _controller.markChapterBookmarked(
      episodeId: chapter.episodeId,
      isBookmarked: !chapter.isBookmarked,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleChapterDownload(LibraryChapterItem chapter) async {
    if (_downloadingEpisodeIds.contains(chapter.episodeId)) {
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
          _showDetailSnackBar('删除下载失败：$error');
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
        _showDetailSnackBar('下载失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingEpisodeIds.remove(chapter.episodeId);
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

  List<PopupMenuEntry<String>> _downloadMenuItems(BuildContext _) {
    return const [
      PopupMenuItem(value: 'download-unread', child: Text('未读')),
      PopupMenuItem(value: 'download-all', child: Text('全部')),
    ];
  }

  Future<void> _handleDownloadMenuAction(String value) async {
    try {
      if (value == 'download-unread') {
        await widget.adapter.downloadUnread(workId: widget.workId);
        _showDetailSnackBar('已开始下载未读章节');
        return;
      }
      if (value == 'download-all') {
        await widget.adapter.downloadAll(workId: widget.workId);
        _showDetailSnackBar('已开始下载全部章节');
      }
    } catch (error) {
      if (mounted) {
        _showDetailSnackBar('下载失败：$error');
      }
    }
  }

  Future<void> _toggleChapterSortDirection() async {
    await _controller.toggleSortDirection();
    if (mounted) {
      setState(() {});
    }
  }

  String _chapterFilterSummary(LibraryFilterSet filters) {
    if (filters.isDefault) {
      return '全部章节';
    }
    final labels = <String>[
      ?_filterSummaryPart('已下载', filters.downloaded),
      ?_filterSummaryPart('未读', filters.unread),
      ?_filterSummaryPart('已加书签', filters.bookmarked),
    ];
    return labels.isEmpty ? '全部章节' : labels.join(' / ');
  }

  String? _filterSummaryPart(String label, TriStateFilterValue value) {
    return switch (value) {
      TriStateFilterValue.ignore => null,
      TriStateFilterValue.include => label,
      TriStateFilterValue.exclude => '排除$label',
    };
  }

  String _chapterSortSummary(LibraryChapterSortOption option) {
    final field = switch (option.field) {
      LibraryChapterSortField.chapterIndex => '章节',
      LibraryChapterSortField.date => '日期',
      LibraryChapterSortField.name => '名称',
      LibraryChapterSortField.tid => '来源',
    };
    final direction = option.direction == LibrarySortDirection.asc
        ? '升序'
        : '降序';
    return '$field$direction';
  }

  Future<void> _showChapterFilterSheet() async {
    var selectedFilters = _controller.state.filters;
    var selectedSortField = _controller.state.chapterSortOption.field;
    var selectedDirection = _controller.state.chapterSortOption.direction;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                        const UnifiedDetailSheetSectionHeader(title: '筛选'),
                        UnifiedDetailTriStateLine(
                          lineKey: const Key(
                            'unified-detail-filter-downloaded',
                          ),
                          label: '已下载',
                          value: selectedFilters.downloaded,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(
                              downloaded: v,
                            ),
                          ),
                        ),
                        UnifiedDetailTriStateLine(
                          lineKey: const Key('unified-detail-filter-unread'),
                          label: '未读',
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
                          label: '已加书签',
                          value: selectedFilters.bookmarked,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(
                              bookmarked: v,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const UnifiedDetailSheetSectionHeader(title: '排序'),
                        DropdownButtonFormField<LibraryChapterSortField>(
                          key: const Key('unified-detail-sort-field'),
                          initialValue: selectedSortField,
                          items: const [
                            DropdownMenuItem(
                              value: LibraryChapterSortField.chapterIndex,
                              child: Text('按章节编号'),
                            ),
                            DropdownMenuItem(
                              value: LibraryChapterSortField.date,
                              child: Text('按日期'),
                            ),
                            DropdownMenuItem(
                              value: LibraryChapterSortField.name,
                              child: Text('按名称'),
                            ),
                            DropdownMenuItem(
                              value: LibraryChapterSortField.tid,
                              child: Text('按来源'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setSheetState(() => selectedSortField = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          key: const Key('unified-detail-sort-direction'),
                          children: [
                            const Text('排序方向'),
                            const Spacer(),
                            SegmentedButton<LibrarySortDirection>(
                              segments: const [
                                ButtonSegment(
                                  value: LibrarySortDirection.asc,
                                  label: Text('升序'),
                                ),
                                ButtonSegment(
                                  value: LibrarySortDirection.desc,
                                  label: Text('降序'),
                                ),
                              ],
                              selected: <LibrarySortDirection>{
                                selectedDirection,
                              },
                              onSelectionChanged: (values) {
                                setSheetState(
                                  () => selectedDirection = values.first,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: const Key(
                                  'unified-detail-apply-filter-sort',
                                ),
                                onPressed: () async {
                                  await _controller.updateFilters(
                                    selectedFilters,
                                  );
                                  await _controller.updateChapterSortField(
                                    selectedSortField,
                                  );
                                  final now = _controller
                                      .state
                                      .chapterSortOption
                                      .direction;
                                  if (now != selectedDirection) {
                                    await _controller.toggleSortDirection();
                                  }
                                  if (!mounted || !sheetContext.mounted) {
                                    return;
                                  }
                                  Navigator.of(sheetContext).pop();
                                  setState(() {});
                                },
                                child: const Text('应用'),
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(chapter.isBookmarked ? '移除书签' : '添加书签'),
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
                ListTile(
                  leading: const Icon(Icons.remove_done),
                  title: const Text('取消全部已读'),
                  onTap: () async {
                    await _controller.clearAllReadState();
                    if (!mounted || !sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除该章节下载'),
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
              ],
            ),
          ),
        );
      },
    );
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
    if (value == 'set-custom-cover') {
      await _handleSetCustomCover();
      return;
    }
    if (value == 'adjust-cover-focus') {
      await _handleAdjustCoverFocus();
      return;
    }
    if (value == 'edit-intro') {
      await _showEditIntroDialog();
      return;
    }
    if (value == 'add-tag') {
      await _showAddTagSheet();
      return;
    }
    if (value == 'remove-tag') {
      await _showRemoveTagSheet();
    }
  }

  Future<void> _refreshAndShowFeedback() async {
    try {
      final result = await _controller.refresh();
      if (!mounted) {
        return;
      }
      _showDetailSnackBar(_refreshFeedbackMessage(result));
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showDetailSnackBar('更新失败：$error');
      setState(() {});
    }
  }

  String _refreshFeedbackMessage(DetailRefreshResult result) {
    final message = result.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return switch (result.status) {
      DetailRefreshStatus.immediate => '已更新',
      DetailRefreshStatus.skipped => '暂无可更新内容',
      DetailRefreshStatus.queued => '已加入更新队列',
    };
  }

  Future<void> _retryLoad() async {
    await _controller.reload();
    if (mounted) {
      setState(() {});
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
          titleSourceText: _sourceText(
            '来源标题',
            header.sourceTitle ?? header.title,
          ),
          authorSourceText: _sourceText(
            '来源作者',
            header.sourceAuthor ?? header.author,
          ),
          groupSourceText: _sourceText(
            '来源汉化组',
            header.sourceTranslationGroup ?? header.translationGroup,
          ),
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

  /// 是否支持自定义封面编辑：adapter 实现合同且外壳注入了图片选择器。
  bool get _supportsCoverEditing =>
      widget.adapter is DetailCoverEditor && widget.pickCoverImage != null;

  bool get _hasCustomCover {
    final custom = _controller.state.header?.customCoverLocalPath?.trim();
    return custom != null && custom.isNotEmpty;
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
      title: '调整封面焦点',
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
      _showDetailSnackBar('封面更新失败：$error');
      return;
    }
    await _controller.reload();
    if (!mounted) {
      return;
    }
    _showDetailSnackBar('封面已更新');
    setState(() {});
  }

  /// 调整已有自定义封面的焦点（不更换图片）。
  Future<void> _handleAdjustCoverFocus() async {
    final editor = _coverEditor;
    final header = _controller.state.header;
    final localPath = header?.customCoverLocalPath?.trim();
    if (editor == null || localPath == null || localPath.isEmpty) {
      return;
    }
    final focus = await CoverFocalPointPicker.show(
      context,
      image: FileImage(io.File(localPath)),
      initialFocus: CoverFocalPoint.fromNullable(
        header?.customCoverFocusX,
        header?.customCoverFocusY,
      ),
      title: '调整封面焦点',
    );
    if (focus == null || !mounted) {
      return;
    }
    try {
      await editor.updateCustomCoverFocus(
        workId: widget.workId,
        focusX: focus.x,
        focusY: focus.y,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showDetailSnackBar('焦点更新失败：$error');
      return;
    }
    await _controller.reload();
    if (!mounted) {
      return;
    }
    _showDetailSnackBar('封面焦点已更新');
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
                    title: Text(item.name),
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
        return AlertDialog(
          title: const Text('编辑简介'),
          content: TextField(
            controller: inputController,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '请输入简介'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
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
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddTagSheet() async {
    final tags = await widget.adapter.getAllTags();
    if (!mounted) {
      return;
    }
    final inputController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: inputController,
                  decoration: const InputDecoration(hintText: '新建标签名'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final name = inputController.text.trim();
                          if (name.isEmpty) {
                            return;
                          }
                          await widget.adapter.addNewTagToWork(
                            workId: widget.workId,
                            tagName: name,
                          );
                          await _controller.reload();
                          if (!mounted || !sheetContext.mounted) {
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                          setState(() {});
                        },
                        child: const Text('新建并添加'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...tags.map(
                  (tag) => ListTile(
                    title: Text(tag.name),
                    onTap: () async {
                      await widget.adapter.addExistingTagToWork(
                        workId: widget.workId,
                        tagId: tag.tagId,
                      );
                      await _controller.reload();
                      if (!mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRemoveTagSheet() async {
    final tags = await widget.adapter.getWorkTags(workId: widget.workId);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        if (tags.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('当前作品暂无标签'),
            ),
          );
        }
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: tags
                .map(
                  (tag) => ListTile(
                    title: Text(tag.name),
                    trailing: const Icon(Icons.remove_circle_outline),
                    onTap: () async {
                      await widget.adapter.removeTagFromWork(
                        workId: widget.workId,
                        tagId: tag.tagId,
                      );
                      await _controller.reload();
                      if (!mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      setState(() {});
                    },
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

String _sourceText(String label, String? value) {
  final normalized = value?.trim();
  return '$label：${normalized == null || normalized.isEmpty ? '无' : normalized}';
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
