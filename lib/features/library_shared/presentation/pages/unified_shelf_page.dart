import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_shelf_controller.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';

/// 统一书架页面（Phase 3）。
class UnifiedShelfPage extends StatefulWidget {
  const UnifiedShelfPage({
    super.key,
    required this.adapter,
    required this.onOpenWork,
  });

  final ShelfModuleAdapter adapter;
  final Future<void> Function(BuildContext context, String workId) onOpenWork;

  @override
  State<UnifiedShelfPage> createState() => _UnifiedShelfPageState();
}

class _UnifiedShelfPageState extends State<UnifiedShelfPage> {
  late final UnifiedShelfController _controller;
  late final PageController _pageController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = UnifiedShelfController(adapter: widget.adapter);
    _pageController = PageController();
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
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final categories = state.categories;
    final tabs = categories
        .map(
          (category) => FixedSlotHeaderTab(
            id: category.categoryId,
            label: _buildCategoryLabel(category),
          ),
        )
        .toList(growable: false);
    final selectedIndex = _resolveSelectedIndex(categories, state.selectedCategoryId);

    return Scaffold(
      appBar: _buildAppBar(state),
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.refreshFromSource();
          if (!mounted) {
            return;
          }
          setState(() {});
        },
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (state.errorMessage != null && state.errorMessage!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '加载失败：${state.errorMessage}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ),
                  if (categories.isNotEmpty)
                    FixedSlotPagerHeader(
                      pageController: _pageController,
                      tabs: tabs,
                      selectedIndex: selectedIndex,
                      onTap: (index) async {
                        await _controller.selectCategory(categories[index].categoryId);
                        if (!mounted) {
                          return;
                        }
                        setState(() {});
                        await _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      indicatorKey: const Key('unified-shelf-category-indicator'),
                      tabKeyBuilder: (id) => ValueKey<String>('unified-shelf-category-tab-$id'),
                    ),
                  if (categories.isNotEmpty) const Divider(height: 1),
                  Expanded(
                    child: categories.isEmpty
                        ? const Center(child: Text('书架为空'))
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: categories.length,
                            onPageChanged: (index) async {
                              await _controller.selectCategory(categories[index].categoryId);
                              if (!mounted) {
                                return;
                              }
                              setState(() {});
                            },
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              final items =
                                  state.itemsByCategory[category.categoryId] ?? const <LibraryWorkItem>[];
                              if (items.isEmpty) {
                                return const Center(child: Text('书架为空'));
                              }
                              if (state.displayMode == LibraryDisplayMode.list) {
                                return _WorkList(
                                  items: items,
                                  onTapItem: (workId) => widget.onOpenWork(context, workId),
                                );
                              }
                              return _WorkGrid(
                                items: items,
                                gridColumns: state.gridColumnCount,
                                onTapItem: (workId) => widget.onOpenWork(context, workId),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(UnifiedShelfState state) {
    if (!state.isSearchMode) {
      return AppBar(
        title: Text(state.moduleTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              await _controller.enterSearchMode();
              if (!mounted) {
                return;
              }
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem<String>(value: 'add-category', child: Text('新建分类')),
              PopupMenuItem<String>(value: 'rename-category', child: Text('重命名当前分类')),
              PopupMenuItem<String>(value: 'delete-category', child: Text('删除当前分类')),
              PopupMenuDivider(),
              PopupMenuItem<String>(value: 'refresh-shelf', child: Text('更新书架')),
              PopupMenuItem<String>(value: 'random-open', child: Text('随机打开作品')),
            ],
          ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () async {
          _searchController.clear();
          await _controller.exitSearchMode();
          if (!mounted) {
            return;
          }
          setState(() {});
        },
      ),
      titleSpacing: 0,
      title: TextField(
        key: const Key('unified-shelf-search-input'),
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '搜索···',
          border: InputBorder.none,
        ),
        onChanged: (value) async {
          await _controller.updateKeyword(value);
          if (!mounted) {
            return;
          }
          setState(() {});
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: _showFilterSheet,
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenuAction,
          itemBuilder: (context) => const [
            PopupMenuItem<String>(value: 'refresh-shelf', child: Text('更新书架')),
            PopupMenuItem<String>(value: 'random-open', child: Text('随机打开作品')),
          ],
        ),
      ],
    );
  }

  Future<void> _showFilterSheet() async {
    final state = _controller.state;
    var selectedFilter = state.filters;
    var selectedSort = state.sortOption;
    var selectedMode = state.displayMode;
    var selectedColumns = state.gridColumnCount.toDouble();
    var tabIndex = 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            const tabs = ['筛选', '排序', '显示'];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: List.generate(tabs.length, (index) {
                        final selected = tabIndex == index;
                        return Expanded(
                          child: TextButton(
                            onPressed: () => setSheetState(() => tabIndex = index),
                            child: Text(
                              tabs[index],
                              style: TextStyle(
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    if (tabIndex == 0)
                      _FilterTab(
                        filters: selectedFilter,
                        onChanged: (next) => setSheetState(() => selectedFilter = next),
                      ),
                    if (tabIndex == 1)
                      _SortTab(
                        sortOption: selectedSort,
                        onChanged: (next) => setSheetState(() => selectedSort = next),
                      ),
                    if (tabIndex == 2)
                      _DisplayTab(
                        displayMode: selectedMode,
                        gridColumns: selectedColumns,
                        onDisplayModeChanged: (mode) => setSheetState(() => selectedMode = mode),
                        onGridColumnsChanged: (columns) => setSheetState(() => selectedColumns = columns),
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
                            onPressed: () async {
                              await _controller.updateFilters(selectedFilter);
                              await _controller.updateSortOption(selectedSort);
                              await _controller.updateDisplayMode(selectedMode);
                              await _controller.updateGridColumnCount(selectedColumns.toInt());
                              if (!sheetContext.mounted || !mounted) {
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
            );
          },
        );
      },
    );
  }

  Future<void> _handleMenuAction(String value) async {
    final messenger = ScaffoldMessenger.of(context);

    if (value == 'refresh-shelf') {
      await _controller.refreshFromSource();
      if (!mounted) {
        return;
      }
      setState(() {});
      return;
    }

    if (value == 'random-open') {
      final workId = await _controller.pickRandomWorkId();
      if (!mounted) {
        return;
      }
      if (workId == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('当前分类没有可打开的作品')),
        );
        return;
      }
      await widget.onOpenWork(context, workId);
      return;
    }

    if (value == 'add-category') {
      final name = await _showCategoryNameDialog(title: '新建分类');
      if (name == null || name.trim().isEmpty) {
        return;
      }
      await _controller.createCategory(name.trim());
      if (!mounted) {
        return;
      }
      setState(() {});
      return;
    }

    final selectedCategory = _controller.selectedCategory;
    if (selectedCategory == null) {
      return;
    }

    if (value == 'rename-category') {
      if (selectedCategory.isDefault) {
        messenger.showSnackBar(
          const SnackBar(content: Text('默认分类不支持重命名')),
        );
        return;
      }
      final name = await _showCategoryNameDialog(
        title: '重命名当前分类',
        initialValue: selectedCategory.name,
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      await _controller.renameCategory(
        categoryId: selectedCategory.categoryId,
        newName: name.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      return;
    }

    if (value == 'delete-category') {
      if (selectedCategory.isDefault) {
        messenger.showSnackBar(
          const SnackBar(content: Text('默认分类不支持删除')),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('删除分类'),
            content: const Text('删除后该分类作品会移动到默认分类，是否继续？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
      await _controller.deleteCategory(selectedCategory.categoryId);
      if (!mounted) {
        return;
      }
      setState(() {});
    }
  }

  Future<String?> _showCategoryNameDialog({
    required String title,
    String initialValue = '',
  }) async {
    final textController = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '请输入分类名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(textController.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  int _resolveSelectedIndex(List<LibraryCategory> categories, String selectedId) {
    if (categories.isEmpty) {
      return 0;
    }
    final index = categories.indexWhere((e) => e.categoryId == selectedId);
    return index < 0 ? 0 : index;
  }

  String _buildCategoryLabel(LibraryCategory category) {
    final count = _controller.state.visibleMatchCountByCategory[category.categoryId] ?? 0;
    if (_controller.state.keyword.trim().isEmpty) {
      return category.name;
    }
    return '${category.name} $count';
  }
}

class _WorkGrid extends StatelessWidget {
  const _WorkGrid({
    required this.items,
    required this.gridColumns,
    required this.onTapItem,
  });

  final List<LibraryWorkItem> items;
  final int gridColumns;
  final ValueChanged<String> onTapItem;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('unified-shelf-grid-view'),
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ShelfCoverCard(
          title: item.title,
          coverImageUrl: item.coverImageUrl,
          onTap: () => onTapItem(item.workId),
          topLeftBadge: _UnreadBadge(count: item.unreadCount),
          showTwoLineCustomEllipsis: true,
        );
      },
    );
  }
}

class _WorkList extends StatelessWidget {
  const _WorkList({
    required this.items,
    required this.onTapItem,
  });

  final List<LibraryWorkItem> items;
  final ValueChanged<String> onTapItem;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('unified-shelf-list-view'),
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          onTap: () => onTapItem(item.workId),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(64),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: item.coverImageUrl == null || item.coverImageUrl!.trim().isEmpty
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    )
                  : Image.network(
                      item.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _UnreadBadge(count: item.unreadCount),
        );
      },
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.filters,
    required this.onChanged,
  });

  final LibraryFilterSet filters;
  final ValueChanged<LibraryFilterSet> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TriStateLine(
          label: '已下载',
          value: filters.downloaded,
          onChanged: (v) => onChanged(filters.copyWith(downloaded: v)),
        ),
        _TriStateLine(
          label: '未读',
          value: filters.unread,
          onChanged: (v) => onChanged(filters.copyWith(unread: v)),
        ),
        _TriStateLine(
          label: '阅读过',
          value: filters.read,
          onChanged: (v) => onChanged(filters.copyWith(read: v)),
        ),
        _TriStateLine(
          label: '已添加标签',
          value: filters.hasTags,
          onChanged: (v) => onChanged(filters.copyWith(hasTags: v)),
        ),
      ],
    );
  }
}

class _SortTab extends StatelessWidget {
  const _SortTab({
    required this.sortOption,
    required this.onChanged,
  });

  final LibraryShelfSortOption sortOption;
  final ValueChanged<LibraryShelfSortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <LibraryShelfSortField, String>{
      LibraryShelfSortField.name: '名称',
      LibraryShelfSortField.chapterCount: '章节数',
      LibraryShelfSortField.lastReadAt: '最近阅读',
      LibraryShelfSortField.lastCheckedAt: '检查更新时间',
      LibraryShelfSortField.unreadCount: '未读章节数',
      LibraryShelfSortField.workUpdatedAt: '作品更新时间',
      LibraryShelfSortField.fetchedAt: '章节获取时间',
      LibraryShelfSortField.favoriteAddedAt: '收藏日期',
    };
    return Column(
      children: options.entries.map((entry) {
        final selected = entry.key == sortOption.field;
        return ListTile(
          dense: true,
          leading: Icon(
            selected && sortOption.direction == LibrarySortDirection.asc
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            size: 18,
          ),
          title: Text(entry.value),
          trailing: selected ? const Icon(Icons.check, size: 18) : null,
          onTap: () {
            final nextDirection = selected && sortOption.direction == LibrarySortDirection.desc
                ? LibrarySortDirection.asc
                : LibrarySortDirection.desc;
            onChanged(
              LibraryShelfSortOption(
                field: entry.key,
                direction: nextDirection,
              ),
            );
          },
        );
      }).toList(growable: false),
    );
  }
}

class _DisplayTab extends StatelessWidget {
  const _DisplayTab({
    required this.displayMode,
    required this.gridColumns,
    required this.onDisplayModeChanged,
    required this.onGridColumnsChanged,
  });

  final LibraryDisplayMode displayMode;
  final double gridColumns;
  final ValueChanged<LibraryDisplayMode> onDisplayModeChanged;
  final ValueChanged<double> onGridColumnsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RadioGroup<LibraryDisplayMode>(
          groupValue: displayMode,
          onChanged: (value) {
            if (value != null) {
              onDisplayModeChanged(value);
            }
          },
          child: Column(
            children: [
              ListTile(
                title: const Text('网格'),
                leading: Radio<LibraryDisplayMode>(value: LibraryDisplayMode.grid),
              ),
              ListTile(
                title: const Text('列表'),
                leading: Radio<LibraryDisplayMode>(value: LibraryDisplayMode.list),
              ),
            ],
          ),
        ),
        if (displayMode == LibraryDisplayMode.grid) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('每行个数'),
                Expanded(
                  child: Slider(
                    value: gridColumns.clamp(1, 10),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${gridColumns.round()}',
                    onChanged: onGridColumnsChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TriStateLine extends StatelessWidget {
  const _TriStateLine({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TriStateFilterValue value;
  final ValueChanged<TriStateFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (value) {
      case TriStateFilterValue.ignore:
        icon = Icons.check_box_outline_blank;
        break;
      case TriStateFilterValue.include:
        icon = Icons.check_box;
        break;
      case TriStateFilterValue.exclude:
        icon = Icons.indeterminate_check_box;
        break;
    }
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
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
