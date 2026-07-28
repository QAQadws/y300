import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/core/media/cover_focal_point.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_shelf_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_app_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/widgets/library_sort_option_tile.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

/// 统一书架页面（Phase 3）。
class UnifiedShelfPage extends StatefulWidget {
  const UnifiedShelfPage({
    super.key,
    required this.adapter,
    this.viewPreferencesRepository,
    required this.onOpenWork,
    this.imageHeaderBuilder,
    this.featureFlags = ShelfFeatureFlags.defaults,
    this.isActive = true,
    this.taskProgressHub,
    this.selectionHost,
    this.coverPrecacheServiceResolver,
  });

  final ShelfModuleAdapter adapter;
  final LibraryViewPreferencesRepository? viewPreferencesRepository;
  final Future<void> Function(BuildContext context, String workId) onOpenWork;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ShelfFeatureFlags featureFlags;
  final bool isActive;
  final LibraryTaskProgressHub? taskProgressHub;
  final ShelfSelectionHostController? selectionHost;
  final ForumImagePrecacheService Function()? coverPrecacheServiceResolver;

  @override
  State<UnifiedShelfPage> createState() => _UnifiedShelfPageState();
}

class _UnifiedShelfPageState extends State<UnifiedShelfPage> {
  static const String _moduleActionPrefix = 'module-action:';

  late final UnifiedShelfController _controller;
  late final PageController _pageController;
  late final ShelfSelectionController _selectionController;
  final TextEditingController _searchController = TextEditingController();
  final Object _selectionOwnerToken = Object();

  @override
  void initState() {
    super.initState();
    _controller = UnifiedShelfController(
      adapter: widget.adapter,
      viewPreferencesRepository: widget.viewPreferencesRepository,
      featureFlags: widget.featureFlags,
      onStateChanged: _handleControllerStateChanged,
      backgroundReloadEnabled: widget.isActive,
      taskProgressHub: widget.taskProgressHub,
      coverPrecacheServiceResolver: widget.coverPrecacheServiceResolver,
    );
    _pageController = PageController();
    _selectionController = ShelfSelectionController()
      ..addListener(_handleSelectionStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.initialize();
      if (!mounted) {
        return;
      }
      _pruneSelectionForCurrentCategory();
      _syncSelectionHost();
      setState(() {});
    });
  }

  void _handleControllerStateChanged() {
    if (!mounted) {
      return;
    }
    _pruneSelectionForCurrentCategory();
    _syncSelectionHost();
    setState(() {});
  }

  void _handleSelectionStateChanged() {
    if (!mounted) {
      return;
    }
    if (_selectionController.isSelecting &&
        _selectionController.selectedCount == 0) {
      _exitSelection(notifyHost: true);
      return;
    }
    _syncSelectionHost();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant UnifiedShelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _controller.setBackgroundReloadEnabled(widget.isActive);
      if (widget.isActive) {
        _syncSelectionHost();
      } else {
        widget.selectionHost?.deactivate(_selectionOwnerToken);
      }
    }
    if (!identical(oldWidget.selectionHost, widget.selectionHost)) {
      oldWidget.selectionHost?.deactivate(_selectionOwnerToken);
      _syncSelectionHost();
    }
  }

  @override
  void dispose() {
    widget.selectionHost?.deactivate(_selectionOwnerToken);
    _selectionController
      ..removeListener(_handleSelectionStateChanged)
      ..dispose();
    _controller.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final imageHeaderBuilder = widget.imageHeaderBuilder;
    final categories = state.categories;
    final tabs = categories
        .map(
          (category) => FixedSlotHeaderTab(
            id: category.categoryId,
            label: _buildCategoryLabel(category),
          ),
        )
        .toList(growable: false);
    final selectedIndex = _resolveSelectedIndex(
      categories,
      state.selectedCategoryId,
    );
    final selecting = _selectionController.isSelecting;
    final shelfPalette = const ShelfThemePaletteResolver().resolve(
      Theme.of(context),
    );

    return PopScope<void>(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selecting) {
          _exitSelection();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(state),
        body: RefreshIndicator(
          // 书架内容位于 PageView 内部，垂直列表/网格滚动通知深度通常 > 0。
          // 显式放宽 predicate，确保网格/列表场景都能触发下拉刷新。
          notificationPredicate: (notification) {
            return notification.metrics.axis == Axis.vertical;
          },
          onRefresh: _handlePullToRefresh,
          child: state.isLoading
              ? Column(
                  children: [
                    _buildTaskProgressBanner(),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildTaskProgressBanner(),
                    if (state.errorMessage != null &&
                        state.errorMessage!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '加载失败：${state.errorMessage}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ),
                    if (categories.isNotEmpty)
                      IgnorePointer(
                        ignoring: selecting,
                        child: FixedSlotPagerHeader(
                          pageController: _pageController,
                          tabs: tabs,
                          selectedIndex: selectedIndex,
                          onTap: (index) async {
                            await _controller.selectCategory(
                              categories[index].categoryId,
                            );
                            if (!mounted) {
                              return;
                            }
                            _pruneSelectionForCurrentCategory();
                            _syncSelectionHost();
                            setState(() {});
                            await _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          indicatorKey: const Key(
                            'unified-shelf-category-indicator',
                          ),
                          tabKeyBuilder: (id) => ValueKey<String>(
                            'unified-shelf-category-tab-$id',
                          ),
                        ),
                      ),
                    if (categories.isNotEmpty)
                      Divider(height: 1, color: shelfPalette.categoryDivider),
                    Expanded(
                      child: categories.isEmpty
                          ? const _AlwaysScrollableEmptyState(message: '书架为空')
                          : ValueListenableBuilder<UnifiedShelfState>(
                              valueListenable: _controller.stateListenable,
                              builder: (context, liveState, _) {
                                return PageView.builder(
                                  controller: _pageController,
                                  physics: selecting
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                                  itemCount: categories.length,
                                  onPageChanged: (index) async {
                                    await _controller.selectCategory(
                                      categories[index].categoryId,
                                    );
                                    if (!mounted) {
                                      return;
                                    }
                                    _pruneSelectionForCurrentCategory();
                                    _syncSelectionHost();
                                    setState(() {});
                                  },
                                  itemBuilder: (context, index) {
                                    final category = categories[index];
                                    final items =
                                        liveState.itemsByCategory[category
                                            .categoryId] ??
                                        const <LibraryWorkItem>[];
                                    return _ShelfCategoryPage(
                                      key: PageStorageKey<String>(
                                        'unified-shelf-category-page-${category.categoryId}',
                                      ),
                                      categoryId: category.categoryId,
                                      items: items,
                                      displayMode: liveState.displayMode,
                                      gridColumns: liveState.gridColumnCount,
                                      imageHeaderBuilder: imageHeaderBuilder,
                                      useShelfCoverImage: widget
                                          .featureFlags
                                          .useShelfCoverImage,
                                      showUnreadBadge:
                                          resolveShelfModuleCapabilities(
                                            widget.adapter,
                                          ).supportsReadState,
                                      selectedWorkIds:
                                          _selectionController.selectedWorkIds,
                                      selectionEnabled: _selectionEnabled,
                                      onTapItem: _handleItemTap,
                                      onLongPressItem: _handleItemLongPress,
                                      onVisibleRangeChanged:
                                          ({
                                            required firstIndex,
                                            required lastIndex,
                                          }) {
                                            _controller.reportVisibleRange(
                                              categoryId: category.categoryId,
                                              firstIndex: firstIndex,
                                              lastIndex: lastIndex,
                                            );
                                          },
                                    );
                                  },
                                  findChildIndexCallback: (key) {
                                    final valueKey = key is ValueKey<String>
                                        ? key.value
                                        : null;
                                    if (valueKey == null ||
                                        !valueKey.startsWith(
                                          'unified-shelf-category-page-',
                                        )) {
                                      return null;
                                    }
                                    final categoryId = valueKey.substring(
                                      'unified-shelf-category-page-'.length,
                                    );
                                    final index = categories.indexWhere(
                                      (category) =>
                                          category.categoryId == categoryId,
                                    );
                                    return index < 0 ? null : index;
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _handlePullToRefresh() async {
    await _controller.refreshFromSource();
    if (!mounted) {
      return;
    }
    _pruneSelectionForCurrentCategory();
    _syncSelectionHost();
    setState(() {});
  }

  bool get _selectionEnabled {
    return widget.selectionHost != null &&
        widget.adapter is ShelfSelectionActionAdapter;
  }

  List<SelectionAction> get _selectionActions {
    if (!_selectionEnabled) {
      return const <SelectionAction>[];
    }
    final selectionAdapter = widget.adapter as ShelfSelectionActionAdapter;
    return selectionAdapter.selectionActions;
  }

  List<LibraryWorkItem> get _currentCategoryItems {
    return _controller.state.itemsByCategory[_controller
            .state
            .selectedCategoryId] ??
        const <LibraryWorkItem>[];
  }

  Set<String> get _currentVisibleWorkIds {
    return _currentCategoryItems.map((item) => item.workId).toSet();
  }

  Future<void> _handleItemTap(String workId) async {
    if (_selectionEnabled && _selectionController.isSelecting) {
      _selectionController.toggle(workId);
      return;
    }
    await _openWorkAndRefreshShelf(workId);
  }

  Future<void> _handleItemLongPress(String workId) async {
    if (!_selectionEnabled) {
      return;
    }
    if (_selectionController.isSelecting) {
      _selectionController.toggle(workId);
      return;
    }
    _selectionController.enter(workId);
  }

  Future<void> _exitSelection({bool notifyHost = true}) async {
    if (!_selectionController.isSelecting &&
        _selectionController.selectedCount == 0) {
      if (notifyHost) {
        widget.selectionHost?.deactivate(_selectionOwnerToken);
      }
      return;
    }
    _selectionController.exit();
    if (notifyHost) {
      widget.selectionHost?.deactivate(_selectionOwnerToken);
    }
  }

  void _pruneSelectionForCurrentCategory() {
    if (!_selectionController.isSelecting) {
      return;
    }
    _selectionController.prune(_currentVisibleWorkIds);
    if (_selectionController.selectedCount == 0) {
      _exitSelection();
    }
  }

  void _syncSelectionHost() {
    final host = widget.selectionHost;
    if (host == null) {
      return;
    }
    if (!_selectionEnabled ||
        !_selectionController.isSelecting ||
        _selectionController.selectedCount == 0 ||
        !widget.isActive) {
      host.deactivate(_selectionOwnerToken);
      return;
    }
    final delegate = ShelfSelectionHostDelegate(
      exitSelection: () => _exitSelection(),
      selectAllVisible: () async {
        _selectionController.selectAll(_currentVisibleWorkIds);
      },
      invertVisible: () async {
        _selectionController.invert(_currentVisibleWorkIds);
      },
      loadAvailableCategories: () => widget.adapter.loadCategories(),
      createCategory: (name) => widget.adapter.createCategory(name: name),
      runSelectionAction: (request) {
        final adapter = widget.adapter as ShelfSelectionActionAdapter;
        return adapter.runSelectionAction(request);
      },
      refreshAfterAction: () async {
        await _controller.refresh();
        if (!mounted) {
          return;
        }
        _pruneSelectionForCurrentCategory();
        setState(() {});
      },
    );
    final state = host.state;
    if (state != null && identical(state.ownerToken, _selectionOwnerToken)) {
      host.update(
        ownerToken: _selectionOwnerToken,
        activeCategoryId: _controller.state.selectedCategoryId,
        selectedCount: _selectionController.selectedCount,
        selectedWorkIds: _selectionController.selectedWorkIds,
        selectionActions: _selectionActions,
      );
      return;
    }
    host.activate(
      ownerToken: _selectionOwnerToken,
      moduleKey: _controller.state.moduleKey,
      moduleTitle: _controller.state.moduleTitle,
      activeCategoryId: _controller.state.selectedCategoryId,
      selectedCount: _selectionController.selectedCount,
      selectedWorkIds: _selectionController.selectedWorkIds,
      selectionActions: _selectionActions,
      delegate: delegate,
    );
  }

  Widget _buildTaskProgressBanner() {
    final progressListenable = widget.adapter.taskProgress;
    if (progressListenable == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<LibraryShelfTaskProgress?>(
      valueListenable: progressListenable,
      builder: (context, progress, _) {
        if (progress == null || !progress.active || !progress.visible) {
          return const SizedBox.shrink();
        }
        return _ShelfTaskProgressBanner(progress: progress);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(UnifiedShelfState state) {
    if (_selectionEnabled && _selectionController.isSelecting) {
      return SelectionAppBar(
        selectedCount: _selectionController.selectedCount,
        l10n: AppLocalizations.of(context),
        onClose: () {
          _exitSelection();
        },
        onSelectAll: () {
          _selectionController.selectAll(_currentVisibleWorkIds);
        },
        onInvertSelection: () {
          _selectionController.invert(_currentVisibleWorkIds);
        },
      );
    }
    final moduleActions = _moduleMenuActions();
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
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'add-category',
                child: Text('新建分类'),
              ),
              const PopupMenuItem<String>(
                value: 'rename-category',
                child: Text('重命名当前分类'),
              ),
              const PopupMenuItem<String>(
                value: 'delete-category',
                child: Text('删除当前分类'),
              ),
              if (moduleActions.isNotEmpty) ...[
                const PopupMenuDivider(),
                ..._moduleActionItems(moduleActions),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'refresh-shelf',
                child: Text('更新书架'),
              ),
              const PopupMenuItem<String>(
                value: 'random-open',
                child: Text('随机打开作品'),
              ),
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
          itemBuilder: (context) => [
            if (moduleActions.isNotEmpty) ...[
              ..._moduleActionItems(moduleActions),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem<String>(
              value: 'refresh-shelf',
              child: Text('更新书架'),
            ),
            const PopupMenuItem<String>(
              value: 'random-open',
              child: Text('随机打开作品'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showFilterSheet() async {
    final state = _controller.state;
    final capabilities = resolveShelfModuleCapabilities(widget.adapter);
    var selectedFilter = capabilities.normalizeFilters(state.filters);
    final supportsDownloadedFilter =
        widget.adapter is ShelfDownloadStatusAdapter;
    if (!supportsDownloadedFilter &&
        selectedFilter.downloaded != TriStateFilterValue.ignore) {
      selectedFilter = selectedFilter.copyWith(
        downloaded: TriStateFilterValue.ignore,
      );
    }
    var selectedSort = capabilities.normalizeSortOption(state.sortOption);
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
                            onPressed: () =>
                                setSheetState(() => tabIndex = index),
                            child: Text(
                              tabs[index],
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
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
                        showDownloaded: supportsDownloadedFilter,
                        showReadState: capabilities.supportsReadState,
                        showBookmarked: capabilities.supportsBookmarkFilter,
                        onChanged: (next) =>
                            setSheetState(() => selectedFilter = next),
                      ),
                    if (tabIndex == 1)
                      _SortTab(
                        sortOption: selectedSort,
                        availableFields: capabilities.availableSortFields,
                        onChanged: (next) =>
                            setSheetState(() => selectedSort = next),
                      ),
                    if (tabIndex == 2)
                      _DisplayTab(
                        displayMode: selectedMode,
                        gridColumns: selectedColumns,
                        onDisplayModeChanged: (mode) =>
                            setSheetState(() => selectedMode = mode),
                        onGridColumnsChanged: (columns) =>
                            setSheetState(() => selectedColumns = columns),
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
                              await _controller.updateGridColumnCount(
                                selectedColumns.toInt(),
                              );
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

  List<LibraryShelfMenuAction> _moduleMenuActions() {
    final Object adapter = widget.adapter;
    if (adapter is! ShelfModuleActionAdapter) {
      return const <LibraryShelfMenuAction>[];
    }
    return adapter.menuActions;
  }

  List<PopupMenuEntry<String>> _moduleActionItems(
    List<LibraryShelfMenuAction> actions,
  ) {
    return actions
        .map(
          (action) => PopupMenuItem<String>(
            value: _moduleActionMenuValue(action.id),
            child: Text(action.label),
          ),
        )
        .toList(growable: false);
  }

  String _moduleActionMenuValue(String id) {
    return '$_moduleActionPrefix$id';
  }

  Future<void> _handleMenuAction(String value) async {
    final messenger = ScaffoldMessenger.of(context);

    if (value.startsWith(_moduleActionPrefix)) {
      final Object adapter = widget.adapter;
      if (adapter is! ShelfModuleActionAdapter) {
        return;
      }
      final actionId = value.substring(_moduleActionPrefix.length);
      final result = await adapter.runMenuAction(actionId);
      if (!mounted) {
        return;
      }
      if (result.changed) {
        await _controller.refresh();
        if (!mounted) {
          return;
        }
        setState(() {});
      }
      if (result.message.trim().isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }

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
        messenger.showSnackBar(const SnackBar(content: Text('当前分类没有可打开的作品')));
        return;
      }
      await _openWorkAndRefreshShelf(workId);
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
        messenger.showSnackBar(const SnackBar(content: Text('默认分类不支持重命名')));
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
        messenger.showSnackBar(const SnackBar(content: Text('默认分类不支持删除')));
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
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openWorkAndRefreshShelf(String workId) async {
    await widget.onOpenWork(context, workId);
    if (!mounted) {
      return;
    }
    await _controller.refresh();
    if (mounted) {
      setState(() {});
    }
  }

  int _resolveSelectedIndex(
    List<LibraryCategory> categories,
    String selectedId,
  ) {
    if (categories.isEmpty) {
      return 0;
    }
    final index = categories.indexWhere((e) => e.categoryId == selectedId);
    return index < 0 ? 0 : index;
  }

  String _buildCategoryLabel(LibraryCategory category) {
    final count =
        _controller.state.visibleMatchCountByCategory[category.categoryId] ?? 0;
    if (_controller.state.keyword.trim().isEmpty) {
      return category.name;
    }
    return '${category.name} $count';
  }
}

class _ShelfCategoryPage extends StatefulWidget {
  const _ShelfCategoryPage({
    super.key,
    required this.categoryId,
    required this.items,
    required this.displayMode,
    required this.gridColumns,
    this.imageHeaderBuilder,
    required this.useShelfCoverImage,
    required this.showUnreadBadge,
    required this.onTapItem,
    required this.onLongPressItem,
    required this.selectionEnabled,
    required this.selectedWorkIds,
    required this.onVisibleRangeChanged,
  });

  final String categoryId;
  final List<LibraryWorkItem> items;
  final LibraryDisplayMode displayMode;
  final int gridColumns;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final bool useShelfCoverImage;
  final bool showUnreadBadge;
  final Future<void> Function(String workId) onTapItem;
  final Future<void> Function(String workId) onLongPressItem;
  final bool selectionEnabled;
  final Set<String> selectedWorkIds;
  final void Function({required int firstIndex, required int lastIndex})
  onVisibleRangeChanged;

  @override
  State<_ShelfCategoryPage> createState() => _ShelfCategoryPageState();
}

class _ShelfCategoryPageState extends State<_ShelfCategoryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportInitialRange());
  }

  @override
  void didUpdateWidget(covariant _ShelfCategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.displayMode != widget.displayMode ||
        oldWidget.gridColumns != widget.gridColumns) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportInitialRange(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.items.isEmpty) {
      return const _AlwaysScrollableEmptyState(message: '书架为空');
    }
    final child = widget.displayMode == LibraryDisplayMode.list
        ? _WorkList(
            categoryId: widget.categoryId,
            items: widget.items,
            imageHeaderBuilder: widget.imageHeaderBuilder,
            useShelfCoverImage: widget.useShelfCoverImage,
            showUnreadBadge: widget.showUnreadBadge,
            onTapItem: widget.onTapItem,
            onLongPressItem: widget.onLongPressItem,
            selectionEnabled: widget.selectionEnabled,
            selectedWorkIds: widget.selectedWorkIds,
          )
        : _WorkGrid(
            categoryId: widget.categoryId,
            items: widget.items,
            gridColumns: widget.gridColumns,
            imageHeaderBuilder: widget.imageHeaderBuilder,
            useShelfCoverImage: widget.useShelfCoverImage,
            showUnreadBadge: widget.showUnreadBadge,
            onTapItem: widget.onTapItem,
            onLongPressItem: widget.onLongPressItem,
            selectionEnabled: widget.selectionEnabled,
            selectedWorkIds: widget.selectedWorkIds,
          );
    return RepaintBoundary(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _reportRangeForMetrics(notification.metrics);
          }
          return false;
        },
        child: KeyedSubtree(
          key: ValueKey<String>(
            'unified-shelf-category-scroll-host-${widget.categoryId}',
          ),
          child: child,
        ),
      ),
    );
  }

  void _reportInitialRange() {
    if (!mounted || widget.items.isEmpty) {
      return;
    }
    widget.onVisibleRangeChanged(
      firstIndex: 0,
      lastIndex: _estimateVisibleCount() - 1,
    );
  }

  void _reportRangeForMetrics(ScrollMetrics metrics) {
    if (widget.items.isEmpty) {
      return;
    }
    final firstIndex = _estimateFirstIndex(metrics.pixels);
    final visibleCount = _estimateVisibleCount();
    widget.onVisibleRangeChanged(
      firstIndex: firstIndex,
      lastIndex: firstIndex + visibleCount - 1,
    );
  }

  int _estimateFirstIndex(double scrollOffset) {
    if (widget.displayMode == LibraryDisplayMode.list) {
      return (scrollOffset / 72)
          .floor()
          .clamp(0, widget.items.length - 1)
          .toInt();
    }
    final columns = widget.gridColumns < 1 ? 1 : widget.gridColumns;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final tileWidth = (viewportWidth - 24 - ((columns - 1) * 10)) / columns;
    final tileHeight = tileWidth * 3 / 2;
    final rowExtent = tileHeight + 10;
    return ((scrollOffset / rowExtent).floor() * columns)
        .clamp(0, widget.items.length - 1)
        .toInt();
  }

  int _estimateVisibleCount() {
    if (widget.displayMode == LibraryDisplayMode.list) {
      return 10;
    }
    final columns = widget.gridColumns < 1 ? 1 : widget.gridColumns;
    return columns * 4;
  }
}

class _WorkGrid extends StatelessWidget {
  const _WorkGrid({
    required this.categoryId,
    required this.items,
    required this.gridColumns,
    this.imageHeaderBuilder,
    required this.useShelfCoverImage,
    required this.showUnreadBadge,
    required this.onTapItem,
    required this.onLongPressItem,
    required this.selectionEnabled,
    required this.selectedWorkIds,
  });

  final String categoryId;
  final List<LibraryWorkItem> items;
  final int gridColumns;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final bool useShelfCoverImage;
  final bool showUnreadBadge;
  final Future<void> Function(String workId) onTapItem;
  final Future<void> Function(String workId) onLongPressItem;
  final bool selectionEnabled;
  final Set<String> selectedWorkIds;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: PageStorageKey<String>('unified-shelf-grid-storage-$categoryId'),
      child: GridView.builder(
        key: const Key('unified-shelf-grid-view'),
        // 保证短列表也能触发 RefreshIndicator 下拉手势。
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        // 大书架场景预渲染适度前后缓存，降低滑动抖动。
        scrollCacheExtent: const ScrollCacheExtent.pixels(900),
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
            key: ValueKey<String>('unified-shelf-grid-item-${item.workId}'),
            coverKey: item.workId,
            title: item.title,
            coverImageUrl: item.coverImageUrl,
            coverLocalPath: item.coverLocalPath,
            customCoverLocalPath: item.customCoverLocalPath,
            customCoverFocusX: item.customCoverFocusX,
            customCoverFocusY: item.customCoverFocusY,
            imageHeaderBuilder: imageHeaderBuilder,
            coverLayerBuilder: useShelfCoverImage
                ? null
                : _legacyCoverLayerBuilder,
            onTap: () async => onTapItem(item.workId),
            onLongPress: selectionEnabled
                ? () async => onLongPressItem(item.workId)
                : null,
            topLeftBadge: showUnreadBadge
                ? _UnreadBadge(count: item.unreadCount)
                : null,
            showTwoLineCustomEllipsis: true,
            selected: selectedWorkIds.contains(item.workId),
          );
        },
      ),
    );
  }

  Widget _legacyCoverLayerBuilder(
    BuildContext context,
    ShelfCoverLayerConfig config,
  ) {
    return LibraryCachedImage(
      localPath: config.localPath,
      imageUrl: config.remoteUrl,
      fit: config.fit,
      alignment: config.alignment,
      placeholder: config.placeholder,
      headerBuilder: config.imageHeaderBuilder,
    );
  }
}

class _ShelfTaskProgressBanner extends StatelessWidget {
  const _ShelfTaskProgressBanner({required this.progress});

  final LibraryShelfTaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final countText = _countText();
    final shelfPalette = const ShelfThemePaletteResolver().resolve(
      Theme.of(context),
    );
    return Material(
      color: shelfPalette.taskProgressBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.message,
                    key: const Key('unified-shelf-task-progress-message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (countText != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    countText,
                    key: const Key('unified-shelf-task-progress-count'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const Key('unified-shelf-task-progress-bar'),
              value: progress.fraction,
            ),
          ],
        ),
      ),
    );
  }

  String? _countText() {
    final total = progress.total;
    if (total == null || total <= 0) {
      return null;
    }
    return '${progress.current.clamp(0, total)}/$total';
  }
}

class _WorkList extends StatelessWidget {
  const _WorkList({
    required this.categoryId,
    required this.items,
    this.imageHeaderBuilder,
    required this.useShelfCoverImage,
    required this.showUnreadBadge,
    required this.onTapItem,
    required this.onLongPressItem,
    required this.selectionEnabled,
    required this.selectedWorkIds,
  });

  final String categoryId;
  final List<LibraryWorkItem> items;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final bool useShelfCoverImage;
  final bool showUnreadBadge;
  final Future<void> Function(String workId) onTapItem;
  final Future<void> Function(String workId) onLongPressItem;
  final bool selectionEnabled;
  final Set<String> selectedWorkIds;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: PageStorageKey<String>('unified-shelf-list-storage-$categoryId'),
      child: ListView.separated(
        key: const Key('unified-shelf-list-view'),
        // 保证短列表也能触发 RefreshIndicator 下拉手势。
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        // 大书架场景预渲染适度前后缓存，降低滑动抖动。
        scrollCacheExtent: const ScrollCacheExtent.pixels(900),
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = selectedWorkIds.contains(item.workId);
          final shelfPalette = const ShelfThemePaletteResolver().resolve(
            Theme.of(context),
          );
          final leading = _hasCoverSource(item)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: _buildLeadingCover(context, item),
                  ),
                )
              : null;
          return AnimatedContainer(
            key: ValueKey<String>('unified-shelf-list-item-${item.workId}'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? shelfPalette.selectedBorder
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Material(
                color: shelfPalette.listItemBackground,
                child: ListTile(
                  key: ValueKey<String>(
                    'unified-shelf-list-tile-${item.workId}',
                  ),
                  minTileHeight: 72,
                  selected: selected,
                  onTap: () async => onTapItem(item.workId),
                  onLongPress: selectionEnabled
                      ? () async => onLongPressItem(item.workId)
                      : null,
                  leading: leading,
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: showUnreadBadge
                      ? _UnreadBadge(count: item.unreadCount)
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeadingCover(BuildContext context, LibraryWorkItem item) {
    final shelfPalette = const ShelfThemePaletteResolver().resolve(
      Theme.of(context),
    );
    final placeholder = Container(
      color: shelfPalette.coverPlaceholderBackground,
      child: const Icon(Icons.image_not_supported_outlined),
    );
    // 焦点仅作用于自定义封面；展示来源封面时保持居中。
    final alignment = _isShowingCustomCover(item)
        ? coverAlignmentFromFocus(
            item.customCoverFocusX,
            item.customCoverFocusY,
          )
        : Alignment.center;
    if (!useShelfCoverImage) {
      return LibraryCachedImage(
        localPath: _preferredLocalPath(item),
        imageUrl: _preferredRemoteUrl(item),
        fit: BoxFit.cover,
        alignment: alignment,
        placeholder: placeholder,
        headerBuilder: imageHeaderBuilder,
      );
    }
    return ShelfCoverImage(
      coverKey: item.workId,
      localPath: _preferredLocalPath(item),
      remoteUrl: _preferredRemoteUrl(item),
      imageHeaderBuilder: imageHeaderBuilder,
      fit: BoxFit.cover,
      alignment: alignment,
      placeholder: placeholder,
    );
  }

  bool _isShowingCustomCover(LibraryWorkItem item) {
    final custom = item.customCoverLocalPath?.trim();
    return custom != null && custom.isNotEmpty;
  }

  bool _hasCoverSource(LibraryWorkItem item) {
    // 区分“作品没有配置封面”和“封面配置存在但加载失败”：
    // 前者在列表模式不占 leading，后者仍交给图片组件显示兜底。
    return _preferredLocalPath(item) != null ||
        _preferredRemoteUrl(item) != null;
  }

  String? _preferredLocalPath(LibraryWorkItem item) {
    final custom = item.customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = item.coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _preferredRemoteUrl(LibraryWorkItem item) {
    final custom = item.customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = item.coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

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

class _AlwaysScrollableEmptyState extends StatelessWidget {
  const _AlwaysScrollableEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      children: [SizedBox(height: 320, child: Center(child: Text(message)))],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.filters,
    required this.showDownloaded,
    required this.showReadState,
    required this.showBookmarked,
    required this.onChanged,
  });

  final LibraryFilterSet filters;
  final bool showDownloaded;
  final bool showReadState;
  final bool showBookmarked;
  final ValueChanged<LibraryFilterSet> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDownloaded)
          _TriStateLine(
            label: '已下载',
            value: filters.downloaded,
            onChanged: (v) => onChanged(filters.copyWith(downloaded: v)),
          ),
        if (showReadState) ...[
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
        ],
        if (showBookmarked)
          _TriStateLine(
            label: '有书签',
            value: filters.bookmarked,
            onChanged: (v) => onChanged(filters.copyWith(bookmarked: v)),
          ),
      ],
    );
  }
}

class _SortTab extends StatelessWidget {
  const _SortTab({
    required this.sortOption,
    required this.availableFields,
    required this.onChanged,
  });

  final LibraryShelfSortOption sortOption;
  final List<LibraryShelfSortField> availableFields;
  final ValueChanged<LibraryShelfSortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = <LibraryShelfSortField, String>{
      LibraryShelfSortField.chapterCount: '章节数',
      LibraryShelfSortField.unreadCount: '未读章节数',
      LibraryShelfSortField.favoriteAddedAt: '收藏日期',
    };
    return Column(
      children: availableFields
          .map((field) {
            final selected = field == sortOption.field;
            return LibrarySortOptionTile(
              label: labels[field]!,
              selected: selected,
              direction: sortOption.direction,
              onTap: () {
                final nextDirection =
                    selected &&
                        sortOption.direction == LibrarySortDirection.desc
                    ? LibrarySortDirection.asc
                    : LibrarySortDirection.desc;
                onChanged(
                  LibraryShelfSortOption(
                    field: field,
                    direction: nextDirection,
                  ),
                );
              },
            );
          })
          .toList(growable: false),
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
                leading: Radio<LibraryDisplayMode>(
                  value: LibraryDisplayMode.grid,
                ),
              ),
              ListTile(
                title: const Text('列表'),
                leading: Radio<LibraryDisplayMode>(
                  value: LibraryDisplayMode.list,
                ),
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
