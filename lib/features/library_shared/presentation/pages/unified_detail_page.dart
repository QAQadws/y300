import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';

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
  });

  final DetailModuleAdapter adapter;
  final String workId;
  final Future<void> Function(BuildContext context, ReaderRouteTarget target) onOpenReader;
  final Future<void> Function(BuildContext context, ThreadRouteTarget target) onOpenThread;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

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
  final Set<String> _downloadingEpisodeIds = <String>{};

  @override
  void initState() {
    super.initState();
    _controller = UnifiedDetailController(
      adapter: widget.adapter,
      workId: widget.workId,
    );
    _scrollController = ScrollController()..addListener(_handleScroll);

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
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow = _scrollController.hasClients &&
        _scrollController.offset >= _collapsedTitleRevealOffset;
    if (shouldShow != _showCollapsedTitle && mounted) {
      setState(() => _showCollapsedTitle = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final header = state.header;
    final topInset = MediaQuery.of(context).padding.top;
    final detailPalette = const UnifiedDetailPaletteResolver().resolve(Theme.of(context));
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
        iconTheme: IconThemeData(
          color: appBarForeground,
        ),
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
              const PopupMenuItem(value: 'change-category', child: Text('修改分类')),
              if (widget.adapter is DetailMetadataEditor)
                const PopupMenuItem(
                  key: Key('unified-detail-edit-metadata'),
                  value: 'edit-metadata',
                  child: Text('编辑作品信息'),
                ),
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
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                slivers: [
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _DetailHeaderSection(
                        header: header,
                        moduleKey: widget.adapter.moduleKey,
                        topInset: topInset,
                        palette: detailPalette,
                        imageHeaderBuilder: widget.imageHeaderBuilder,
                        onToggleShelf: () => _showMoveCategorySheet(),
                        onRefresh: _refreshAndShowFeedback,
                        onOpenThread: () async {
                          final target = await widget.adapter.getThreadRouteTarget(workId: widget.workId);
                          if (!context.mounted || target == null) {
                            return;
                          }
                          await widget.onOpenThread(context, target);
                        },
                      ),
                    ),
                  if (state.errorMessage != null && state.errorMessage!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DetailErrorPanel(
                        message: state.errorMessage!,
                        topPadding: header == null ? topInset + kToolbarHeight : 10,
                        onRetry: _retryLoad,
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _IntroSection(
                        intro: header.intro?.trim().isNotEmpty == true ? header.intro! : '暂无简介',
                        expanded: _introExpanded,
                        onToggle: () => setState(() => _introExpanded = !_introExpanded),
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _TagStrip(
                        sourceTagName: header.sourceTagName,
                        sourceTypeId: header.sourceTypeId,
                        customTags: header.customTags,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _ChapterToolbar(
                      chapterCount: state.chapters.length,
                      filterSummary: _chapterFilterSummary(state.filters),
                      sortSummary: _chapterSortSummary(state.chapterSortOption),
                      sortAscending: state.chapterSortOption.direction == LibrarySortDirection.asc,
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
                      return _DetailChapterTile(
                        tileKey: ValueKey<String>('unified-detail-chapter-${chapter.episodeId}'),
                        chapter: chapter,
                        subtitle: _chapterSubtitle(chapter),
                        isDownloading: _downloadingEpisodeIds.contains(chapter.episodeId),
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
    final direction = option.direction == LibrarySortDirection.asc ? '升序' : '降序';
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
                        const _SheetSectionHeader(title: '筛选'),
                        _TriStateLine(
                          lineKey: const Key('unified-detail-filter-downloaded'),
                          label: '已下载',
                          value: selectedFilters.downloaded,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(downloaded: v),
                          ),
                        ),
                        _TriStateLine(
                          lineKey: const Key('unified-detail-filter-unread'),
                          label: '未读',
                          value: selectedFilters.unread,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(unread: v),
                          ),
                        ),
                        _TriStateLine(
                          lineKey: const Key('unified-detail-filter-bookmarked'),
                          label: '已加书签',
                          value: selectedFilters.bookmarked,
                          onChanged: (v) => setSheetState(
                            () => selectedFilters = selectedFilters.copyWith(bookmarked: v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _SheetSectionHeader(title: '排序'),
                        DropdownButtonFormField<LibraryChapterSortField>(
                          key: const Key('unified-detail-sort-field'),
                          initialValue: selectedSortField,
                          items: const [
                            DropdownMenuItem(value: LibraryChapterSortField.chapterIndex, child: Text('按章节编号')),
                            DropdownMenuItem(value: LibraryChapterSortField.date, child: Text('按日期')),
                            DropdownMenuItem(value: LibraryChapterSortField.name, child: Text('按名称')),
                            DropdownMenuItem(value: LibraryChapterSortField.tid, child: Text('按来源')),
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
                                ButtonSegment(value: LibrarySortDirection.asc, label: Text('升序')),
                                ButtonSegment(value: LibrarySortDirection.desc, label: Text('降序')),
                              ],
                              selected: <LibrarySortDirection>{selectedDirection},
                              onSelectionChanged: (values) {
                                setSheetState(() => selectedDirection = values.first);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(sheetContext).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: const Key('unified-detail-apply-filter-sort'),
                                onPressed: () async {
                                  await _controller.updateFilters(selectedFilters);
                                  await _controller.updateChapterSortField(selectedSortField);
                                  final now = _controller.state.chapterSortOption.direction;
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
                    await _controller.deleteChapterDownload(episodeId: chapter.episodeId);
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
        return _EditMetadataSheet(
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
          titleSourceText: _sourceText('来源标题', header.sourceTitle ?? header.title),
          authorSourceText: _sourceText('来源作者', header.sourceAuthor ?? header.author),
          groupSourceText: _sourceText(
            '来源汉化组',
            header.sourceTranslationGroup ?? header.translationGroup,
          ),
          onSave: ({
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

class _EditMetadataSheet extends StatefulWidget {
  const _EditMetadataSheet({
    required this.initialTitle,
    required this.initialAuthor,
    required this.initialTranslationGroup,
    required this.initialSearchTitle,
    required this.titleSourceText,
    required this.authorSourceText,
    required this.groupSourceText,
    required this.onSave,
  });

  final String initialTitle;
  final String initialAuthor;
  final String initialTranslationGroup;
  final String initialSearchTitle;
  final String titleSourceText;
  final String authorSourceText;
  final String groupSourceText;
  final Future<void> Function({
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) onSave;

  @override
  State<_EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<_EditMetadataSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _groupController;
  late final TextEditingController _searchController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _authorController = TextEditingController(text: widget.initialAuthor);
    _groupController = TextEditingController(text: widget.initialTranslationGroup);
    _searchController = TextEditingController(text: widget.initialSearchTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _groupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('unified-detail-metadata-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑作品信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _MetadataTextField(
                fieldKey: const Key('unified-detail-custom-title-input'),
                controller: _titleController,
                label: '标题',
                sourceText: widget.titleSourceText,
              ),
              const SizedBox(height: 10),
              _MetadataTextField(
                fieldKey: const Key('unified-detail-custom-author-input'),
                controller: _authorController,
                label: '作者',
                sourceText: widget.authorSourceText,
              ),
              const SizedBox(height: 10),
              _MetadataTextField(
                fieldKey: const Key('unified-detail-custom-group-input'),
                controller: _groupController,
                label: '汉化组',
                sourceText: widget.groupSourceText,
              ),
              const SizedBox(height: 10),
              _MetadataTextField(
                fieldKey: const Key('unified-detail-custom-search-title-input'),
                controller: _searchController,
                label: '更新搜索关键词',
                sourceText: '留空时依次使用自定义标题、展示标题和来源标题',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('unified-detail-save-metadata'),
                      onPressed: _saving ? null : _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      await widget.onSave(
        customTitle: _emptyToNull(_titleController.text),
        customAuthor: _emptyToNull(_authorController.text),
        customTranslationGroup: _emptyToNull(_groupController.text),
        customSearchTitle: _emptyToNull(_searchController.text),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _MetadataTextField extends StatelessWidget {
  const _MetadataTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.sourceText,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String sourceText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: sourceText,
        helperMaxLines: 2,
      ),
    );
  }
}

/// 顶部视觉区与动作区作为一个滚动单元，避免 RefreshIndicator 下拉拉伸时
/// 两个 Sliver 独立变形造成肉眼可见的缝隙。
class _DetailHeaderSection extends StatelessWidget {
  const _DetailHeaderSection({
    required this.header,
    required this.moduleKey,
    required this.topInset,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onToggleShelf,
    required this.onRefresh,
    required this.onOpenThread,
  });

  static const double _seamBridgeHeight = 6;

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final VoidCallback onToggleShelf;
  final VoidCallback onRefresh;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('unified-detail-header-section'),
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeroInfoSection(
              header: header,
              moduleKey: moduleKey,
              topInset: topInset,
              palette: palette,
              imageHeaderBuilder: imageHeaderBuilder,
            ),
            _HeaderActionsRow(
              header: header,
              onToggleShelf: onToggleShelf,
              onRefresh: onRefresh,
              onOpenThread: onOpenThread,
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _HeroInfoSection.heightFor(topInset) - _seamBridgeHeight / 2,
          height: _seamBridgeHeight,
          child: IgnorePointer(
            child: ColoredBox(
              key: const Key('unified-detail-header-seam-bridge'),
              color: palette.headerGradientEnd,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 可随列表滚动消失的封面+元信息区。
class _HeroInfoSection extends StatelessWidget {
  const _HeroInfoSection({
    required this.header,
    required this.moduleKey,
    required this.topInset,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  // Hero 区高度（含状态栏与 AppBar 覆盖区）
  // 需要容纳：封面(168) + 元信息区 + 操作区，过小会导致底部溢出。
  static const double _heroExtraHeight = 240;
  // 封面与文字块的内边距
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(30, 0, 12, 30);

  static double heightFor(double topInset) => topInset + kToolbarHeight + _heroExtraHeight;

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    final title = header.title;
    final author = header.author?.trim().isNotEmpty == true ? header.author! : '未知作者';
    final group =
        header.translationGroup?.trim().isNotEmpty == true ? header.translationGroup! : '未知汉化组';

    return SizedBox(
      height: heightFor(topInset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DetailHeaderBackground(
            title: title,
            coverImageUrl: header.coverImageUrl,
            customCoverImageUrl: header.customCoverImageUrl,
            coverLocalPath: header.coverLocalPath,
            customCoverLocalPath: header.customCoverLocalPath,
            hasCover: _hasCover(header),
            palette: palette,
            imageHeaderBuilder: imageHeaderBuilder,
          ),
          Padding(
            padding: _contentPadding.copyWith(top: topInset + kToolbarHeight + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _CoverImage(
                  url: _preferredRemoteUrl(header),
                  localPath: _preferredLocalPath(header),
                  moduleKey: moduleKey,
                  palette: palette,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    // 文字区底边距不要过大，否则会形成“被拉开”的视觉缝隙。
                    padding: const EdgeInsets.only(top: 6, left: 0, right: 0, bottom: 30),
                    child: _HeroMetaColumn(
                      moduleKey: moduleKey,
                      title: title,
                      author: author,
                      translationGroup: group,
                      foregroundColor: palette.onHeader,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 最终的边界覆盖由父级 seam bridge 完成；这里仅保证 hero
          // 底部最后一行像素已经落到页面背景色。
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 1,
              child: ColoredBox(
                color: palette.headerGradientEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasCover(LibraryDetailHeader header) {
    return _preferredLocalPath(header) != null ||
        header.customCoverImageUrl?.trim().isNotEmpty == true ||
        header.coverImageUrl?.trim().isNotEmpty == true;
  }

  String? _preferredLocalPath(LibraryDetailHeader header) {
    final custom = header.customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = header.coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _preferredRemoteUrl(LibraryDetailHeader header) {
    final custom = header.customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = header.coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}

class _HeroMetaColumn extends StatelessWidget {
  const _HeroMetaColumn({
    required this.moduleKey,
    required this.title,
    required this.author,
    required this.translationGroup,
    required this.foregroundColor,
  });

  final LibraryModuleKey moduleKey;
  final String title;
  final String author;
  final String translationGroup;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final groupLabel = moduleKey == LibraryModuleKey.comic ? translationGroup : '原作者作品';

    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: foregroundColor),
      child: Column(
        key: const Key('unified-detail-hero-meta'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            key: const Key('unified-detail-hero-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            key: const Key('unified-detail-author-row'),
            children: [
              Icon(Icons.person_outlined, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            key: const Key('unified-detail-group-row'),
            children: [
              Icon(Icons.group_outlined, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  groupLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailHeaderBackground extends StatelessWidget {
  const _DetailHeaderBackground({
    required this.title,
    required this.coverImageUrl,
    required this.customCoverImageUrl,
    required this.coverLocalPath,
    required this.customCoverLocalPath,
    required this.hasCover,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  // 可统一调节模糊强度；你觉得偏糊就继续往下调。
  static const double _blurSigma = 6;

  final String title;
  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final bool hasCover;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    if (!hasCover) {
      return Container(
        color: palette.headerFallbackBackground,
        alignment: Alignment.center,
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 仅对背景图本身做模糊，避免把滚动中的列表内容一起模糊。
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: LibraryCachedImage(
              localPath: _preferredLocalPath,
              imageUrl: _preferredRemoteUrl,
              fit: BoxFit.cover,
              placeholder: Container(color: palette.headerPlaceholderBackground),
              headerBuilder: imageHeaderBuilder,
            ),
          ),
        ),
        DecoratedBox(
          key: const Key('unified-detail-header-gradient'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.headerGradientStart,
                palette.headerGradientMiddle,
                palette.headerGradientEnd,
              ],
              // 最后一段必须落到页面背景，避免动态主题下出现固定白边。
              stops: const [0.0, 0.72, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  String? get _preferredLocalPath {
    final custom = customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? get _preferredRemoteUrl {
    final custom = customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}

class _HeaderActionsRow extends StatelessWidget {
  const _HeaderActionsRow({
    required this.header,
    required this.onToggleShelf,
    required this.onRefresh,
    required this.onOpenThread,
  });

  final LibraryDetailHeader header;
  final VoidCallback onToggleShelf;
  final VoidCallback onRefresh;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('unified-detail-header-actions-row'),
      // 顶部边界不留白，避免下拉时出现“被拉开”的缝隙感。
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _ActionChip(
              icon: header.inShelf ? Icons.favorite : Icons.favorite_border,
              label: header.inShelf ? '在书架中' : '添加到书架',
              onTap: onToggleShelf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(icon: Icons.refresh, label: '更新', onTap: onRefresh),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(icon: Icons.open_in_new, label: '原帖', onTap: onOpenThread),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.url,
    required this.localPath,
    required this.moduleKey,
    required this.palette,
    required this.imageHeaderBuilder,
  });
  final String? url;
  final String? localPath;
  final LibraryModuleKey moduleKey;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 120,
        height: 168,
        child: (url == null || url!.trim().isEmpty) &&
                (localPath == null || localPath!.trim().isEmpty)
            ? Container(
                color: palette.headerPlaceholderBackground,
                child: moduleKey == LibraryModuleKey.novel
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '小说无封面',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      )
                    : const Icon(Icons.image_not_supported_outlined),
              )
            : LibraryCachedImage(
                localPath: localPath,
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: Container(
                  color: palette.headerPlaceholderBackground,
                  child: const Icon(Icons.broken_image_outlined),
                ),
                headerBuilder: imageHeaderBuilder,
              ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailErrorPanel extends StatelessWidget {
  const _DetailErrorPanel({
    required this.message,
    required this.topPadding,
    required this.onRetry,
  });

  final String message;
  final double topPadding;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('unified-detail-error-panel'),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withAlpha(120),
          border: Border.all(color: scheme.error.withAlpha(90)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '加载失败：$message',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('unified-detail-error-retry'),
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterToolbar extends StatelessWidget {
  const _ChapterToolbar({
    required this.chapterCount,
    required this.filterSummary,
    required this.sortSummary,
    required this.sortAscending,
    required this.onFilterTap,
    required this.onSortTap,
    required this.onDownloadSelected,
  });

  final int chapterCount;
  final String filterSummary;
  final String sortSummary;
  final bool sortAscending;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;
  final ValueChanged<String> onDownloadSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('unified-detail-chapter-toolbar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '共 $chapterCount 章',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  filterSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              _ChapterToolbarButton(
                icon: Icons.filter_list,
                label: '筛选',
                onTap: onFilterTap,
              ),
              const SizedBox(width: 6),
              _ChapterToolbarButton(
                icon: sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                label: sortSummary,
                onTap: onSortTap,
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: '下载',
                onSelected: onDownloadSelected,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'download-unread', child: Text('未读')),
                  PopupMenuItem(value: 'download-all', child: Text('全部')),
                ],
                child: const _ChapterToolbarButtonContent(
                  icon: Icons.file_download,
                  label: '下载',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterToolbarButton extends StatelessWidget {
  const _ChapterToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: _ChapterToolbarButtonContent(icon: icon, label: label),
    );
  }
}

class _ChapterToolbarButtonContent extends StatelessWidget {
  const _ChapterToolbarButtonContent({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 34, maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChapterTile extends StatelessWidget {
  const _DetailChapterTile({
    required this.tileKey,
    required this.chapter,
    required this.subtitle,
    required this.isDownloading,
    required this.downloadIconSize,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleBookmark,
    required this.onToggleDownload,
  });

  final Key tileKey;
  final LibraryChapterItem chapter;
  final String subtitle;
  final bool isDownloading;
  final double downloadIconSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = chapter.isRead ? scheme.onSurfaceVariant : scheme.onSurface;
    final subtitleColor =
        chapter.isRead ? scheme.onSurfaceVariant.withAlpha(170) : scheme.onSurfaceVariant;
    final hasStatus = chapter.progressInfo != null ||
        chapter.isBookmarked ||
        chapter.isDownloaded ||
        chapter.isRead;

    return Material(
      key: tileKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: titleColor,
                        fontWeight: chapter.isRead ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
                    ),
                    if (hasStatus) ...[
                      const SizedBox(height: 7),
                      _ChapterStatusRow(chapter: chapter),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ChapterBookmarkButton(
                episodeId: chapter.episodeId,
                isBookmarked: chapter.isBookmarked,
                onPressed: onToggleBookmark,
              ),
              IconButton(
                tooltip: chapter.isDownloaded ? '已下载，点击删除下载' : '下载该章节',
                iconSize: downloadIconSize,
                onPressed: isDownloading ? null : onToggleDownload,
                icon: isDownloading
                    ? SizedBox(
                        width: downloadIconSize,
                        height: downloadIconSize,
                        child: const CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        chapter.isDownloaded
                            ? Icons.check_circle_outline
                            : Icons.arrow_circle_down,
                        size: downloadIconSize,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterStatusRow extends StatelessWidget {
  const _ChapterStatusRow({
    required this.chapter,
  });

  final LibraryChapterItem chapter;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (chapter.progressInfo != null)
        _ChapterProgressBadge(
          key: ValueKey<String>('unified-detail-chapter-progress-${chapter.episodeId}'),
          progress: chapter.progressInfo!,
        ),
      if (chapter.isBookmarked)
        _DetailStatusBadge(
          key: ValueKey<String>('unified-detail-chapter-bookmark-badge-${chapter.episodeId}'),
          icon: Icons.bookmark,
          label: '书签',
          tone: _DetailStatusBadgeTone.accent,
        ),
      if (chapter.isDownloaded)
        _DetailStatusBadge(
          key: ValueKey<String>('unified-detail-chapter-downloaded-badge-${chapter.episodeId}'),
          icon: Icons.check_circle_outline,
          label: '已下载',
          tone: _DetailStatusBadgeTone.success,
        ),
      if (chapter.isRead)
        _DetailStatusBadge(
          key: ValueKey<String>('unified-detail-chapter-read-badge-${chapter.episodeId}'),
          icon: Icons.done,
          label: '已读',
          tone: _DetailStatusBadgeTone.muted,
        ),
    ];

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: badges,
    );
  }
}

class _ChapterBookmarkButton extends StatelessWidget {
  const _ChapterBookmarkButton({
    required this.episodeId,
    required this.isBookmarked,
    required this.onPressed,
  });

  final String episodeId;
  final bool isBookmarked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey<String>('unified-detail-chapter-bookmark-button-$episodeId'),
      tooltip: isBookmarked ? '移除书签' : '添加书签',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(
        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
        color: isBookmarked ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _ChapterProgressBadge extends StatelessWidget {
  const _ChapterProgressBadge({
    super.key,
    required this.progress,
  });

  final LibraryChapterProgressInfo progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(
      progress.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
    );
    final badge = Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withAlpha(64)),
      ),
      child: text,
    );

    final semanticLabel = progress.semanticLabel;
    if (semanticLabel == null || semanticLabel.isEmpty) {
      return badge;
    }
    return Semantics(
      label: semanticLabel,
      child: badge,
    );
  }
}

enum _DetailStatusBadgeTone {
  accent,
  success,
  muted,
}

class _DetailStatusBadge extends StatelessWidget {
  const _DetailStatusBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _DetailStatusBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = switch (tone) {
      _DetailStatusBadgeTone.accent => scheme.primary,
      _DetailStatusBadgeTone.success => scheme.tertiary,
      _DetailStatusBadgeTone.muted => scheme.onSurfaceVariant,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: foreground.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withAlpha(48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroSection extends StatelessWidget {
  const _IntroSection({
    required this.intro,
    required this.expanded,
    required this.onToggle,
  });

  final String intro;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              intro,
              maxLines: expanded ? null : 3,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            expanded ? '收起' : '展开',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _TagStrip extends StatelessWidget {
  const _TagStrip({
    required this.sourceTagName,
    required this.sourceTypeId,
    required this.customTags,
  });

  final String? sourceTagName;
  final String? sourceTypeId;
  final List<LibraryTag> customTags;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = _sourceLabel();
    final labels = <String>[
      ?sourceLabel,
      ...customTags.map((tag) => tag.name.trim()).where((name) => name.isNotEmpty),
    ];
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      key: const Key('unified-detail-tag-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _TagChip(label: labels[i]),
            if (i != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String? _sourceLabel() {
    final tagName = sourceTagName?.trim();
    if (tagName != null && tagName.isNotEmpty) {
      return tagName;
    }
    final typeId = sourceTypeId?.trim();
    if (typeId != null && typeId.isNotEmpty) {
      return 'typeid=$typeId';
    }
    return null;
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _TriStateLine extends StatelessWidget {
  const _TriStateLine({
    required this.lineKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key lineKey;
  final String label;
  final TriStateFilterValue value;
  final ValueChanged<TriStateFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = switch (value) {
      TriStateFilterValue.ignore => Icons.check_box_outline_blank,
      TriStateFilterValue.include => Icons.check_box,
      TriStateFilterValue.exclude => Icons.indeterminate_check_box,
    };
    final stateLabel = switch (value) {
      TriStateFilterValue.ignore => '不限',
      TriStateFilterValue.include => '只看$label',
      TriStateFilterValue.exclude => '排除$label',
    };

    return ListTile(
      key: lineKey,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        stateLabel,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      onTap: () {
        final next = switch (value) {
          TriStateFilterValue.ignore => TriStateFilterValue.include,
          TriStateFilterValue.include => TriStateFilterValue.exclude,
          TriStateFilterValue.exclude => TriStateFilterValue.ignore,
        };
        onChanged(next);
      },
    );
  }
}

class _SheetSectionHeader extends StatelessWidget {
  const _SheetSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

