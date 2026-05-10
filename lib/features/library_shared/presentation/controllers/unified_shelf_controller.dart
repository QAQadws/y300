import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_perf_trace.dart';

/// 统一书架页面状态。
///
/// 该状态对象用于驱动 Phase 3 的统一 UI。
class UnifiedShelfState {
  const UnifiedShelfState({
    required this.moduleKey,
    required this.moduleTitle,
    required this.isLoading,
    required this.isSearchMode,
    required this.keyword,
    required this.filters,
    required this.sortOption,
    required this.displayMode,
    required this.gridColumnCount,
    required this.categories,
    required this.selectedCategoryId,
    required this.itemsByCategory,
    required this.visibleMatchCountByCategory,
    required this.errorMessage,
  });

  final LibraryModuleKey moduleKey;
  final String moduleTitle;
  final bool isLoading;
  final bool isSearchMode;
  final String keyword;
  final LibraryFilterSet filters;
  final LibraryShelfSortOption sortOption;
  final LibraryDisplayMode displayMode;
  final int gridColumnCount;
  final List<LibraryCategory> categories;
  final String selectedCategoryId;
  final Map<String, List<LibraryWorkItem>> itemsByCategory;
  final Map<String, int> visibleMatchCountByCategory;
  final String? errorMessage;

  static UnifiedShelfState initial({
    required LibraryModuleKey moduleKey,
    required String moduleTitle,
    required LibraryDisplayMode defaultDisplayMode,
  }) {
    return UnifiedShelfState(
      moduleKey: moduleKey,
      moduleTitle: moduleTitle,
      isLoading: true,
      isSearchMode: false,
      keyword: '',
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      displayMode: defaultDisplayMode,
      gridColumnCount: 3,
      categories: const <LibraryCategory>[],
      selectedCategoryId: 'default',
      itemsByCategory: const <String, List<LibraryWorkItem>>{},
      visibleMatchCountByCategory: const <String, int>{},
      errorMessage: null,
    );
  }

  UnifiedShelfState copyWith({
    bool? isLoading,
    bool? isSearchMode,
    String? keyword,
    LibraryFilterSet? filters,
    LibraryShelfSortOption? sortOption,
    LibraryDisplayMode? displayMode,
    int? gridColumnCount,
    List<LibraryCategory>? categories,
    String? selectedCategoryId,
    Map<String, List<LibraryWorkItem>>? itemsByCategory,
    Map<String, int>? visibleMatchCountByCategory,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UnifiedShelfState(
      moduleKey: moduleKey,
      moduleTitle: moduleTitle,
      isLoading: isLoading ?? this.isLoading,
      isSearchMode: isSearchMode ?? this.isSearchMode,
      keyword: keyword ?? this.keyword,
      filters: filters ?? this.filters,
      sortOption: sortOption ?? this.sortOption,
      displayMode: displayMode ?? this.displayMode,
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      itemsByCategory: itemsByCategory ?? this.itemsByCategory,
      visibleMatchCountByCategory: visibleMatchCountByCategory ?? this.visibleMatchCountByCategory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 统一书架控制器（Phase 2）。
///
/// 控制器负责状态机编排，不感知具体模块的数据细节。
class UnifiedShelfController {
  UnifiedShelfController({
    required ShelfModuleAdapter adapter,
    ShelfCoverWarmupService? coverWarmupService,
    void Function()? onStateChanged,
  })  : _adapter = adapter,
        _coverWarmupService = coverWarmupService ?? ShelfCoverWarmupService(),
        _onStateChanged = onStateChanged,
        _taskProgressListenable = adapter.taskProgress,
        _state = UnifiedShelfState.initial(
          moduleKey: adapter.moduleKey,
          moduleTitle: adapter.moduleTitle,
          defaultDisplayMode: adapter.defaultDisplayMode,
        ) {
    final taskProgressListenable = _taskProgressListenable;
    _taskProgressWasActive = taskProgressListenable?.value?.active ?? false;
    taskProgressListenable?.addListener(_handleTaskProgressChanged);
  }

  final ShelfModuleAdapter _adapter;
  final ShelfCoverWarmupService _coverWarmupService;
  final void Function()? _onStateChanged;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgressListenable;
  UnifiedShelfState _state;
  static const Duration _keywordDebounceDuration = Duration(milliseconds: 250);
  Timer? _keywordDebounceTimer;
  Completer<void>? _pendingKeywordCompleter;
  bool _taskProgressWasActive = false;
  bool _adapterRefreshInProgress = false;
  var _disposed = false;
  var _reloadGeneration = 0;

  UnifiedShelfState get state => _state;

  /// 释放控制器内部的异步资源，避免页面销毁后残留定时器。
  void dispose() {
    _disposed = true;
    _reloadGeneration++;
    _taskProgressListenable?.removeListener(_handleTaskProgressChanged);
    _keywordDebounceTimer?.cancel();
    _keywordDebounceTimer = null;
    if (_pendingKeywordCompleter != null && !_pendingKeywordCompleter!.isCompleted) {
      _pendingKeywordCompleter!.complete();
    }
    _pendingKeywordCompleter = null;
  }

  Future<void> initialize() async {
    await _reload();
  }

  Future<void> refresh() async {
    await _reload();
  }

  Future<void> enterSearchMode() async {
    _state = _state.copyWith(
      isSearchMode: true,
      clearError: true,
    );
  }

  Future<void> exitSearchMode() async {
    _state = _state.copyWith(
      isSearchMode: false,
      keyword: '',
      clearError: true,
    );
    await _reload();
  }

  Future<void> updateKeyword(String value) async {
    _state = _state.copyWith(keyword: value);
    _keywordDebounceTimer?.cancel();
    if (_pendingKeywordCompleter != null && !_pendingKeywordCompleter!.isCompleted) {
      // 被新输入打断的旧查询直接完成，避免调用方悬挂等待。
      _pendingKeywordCompleter!.complete();
    }
    final completer = Completer<void>();
    _pendingKeywordCompleter = completer;
    _keywordDebounceTimer = Timer(_keywordDebounceDuration, () async {
      try {
        await _reload();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    await completer.future;
  }

  Future<void> selectCategory(String categoryId) async {
    if (_state.selectedCategoryId == categoryId) {
      return;
    }
    _state = _state.copyWith(selectedCategoryId: categoryId);
  }

  Future<void> updateFilters(LibraryFilterSet filters) async {
    _state = _state.copyWith(filters: filters);
    await _reload();
  }

  Future<void> updateSortOption(LibraryShelfSortOption option) async {
    _state = _state.copyWith(sortOption: option);
    await _reload();
  }

  Future<void> updateDisplayMode(LibraryDisplayMode mode) async {
    _state = _state.copyWith(displayMode: mode);
    await _adapter.updateDisplayPreference(
      displayMode: mode,
      gridColumnCount: _state.gridColumnCount,
    );
  }

  Future<void> updateGridColumnCount(int count) async {
    final normalized = _normalizeGridColumnCount(count);
    _state = _state.copyWith(gridColumnCount: normalized);
    await _adapter.updateDisplayPreference(
      displayMode: _state.displayMode,
      gridColumnCount: normalized,
    );
  }

  Future<void> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _adapter.createCategory(name: trimmed);
    await _reload();
  }

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _adapter.renameCategory(categoryId: categoryId, newName: trimmed);
    await _reload();
  }

  Future<void> deleteCategory(String categoryId) async {
    await _adapter.deleteCategory(categoryId: categoryId);
    await _reload();
  }

  Future<void> refreshFromSource() async {
    _adapterRefreshInProgress = true;
    try {
      await _adapter.refreshShelf();
      await _reload();
    } finally {
      _adapterRefreshInProgress = false;
    }
  }

  Future<String?> pickRandomWorkId() async {
    return _adapter.pickRandomWorkId(categoryId: _state.selectedCategoryId);
  }

  LibraryCategory? get selectedCategory {
    if (_state.categories.isEmpty) {
      return null;
    }
    final index = _state.categories.indexWhere((e) => e.categoryId == _state.selectedCategoryId);
    if (index < 0) {
      return _state.categories.first;
    }
    return _state.categories[index];
  }

  List<LibraryWorkItem> get selectedCategoryItems {
    return _state.itemsByCategory[_state.selectedCategoryId] ?? const <LibraryWorkItem>[];
  }

  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final trace = ShelfPerfTrace(name: '${_adapter.moduleKey.name}.reload');
    final shouldBlock = !_hasAnyContent(_state);
    _state = _state.copyWith(isLoading: shouldBlock, clearError: true);
    try {
      final displaySettings = await trace.measure(
        'display',
        _adapter.loadDisplayPreference,
      );
      final categories = await trace.measure(
        'categories',
        _adapter.loadCategories,
      );
      final queried = await trace.measure(
        'queryItems',
        () => _adapter.queryItems(
          categories: categories,
          filters: _state.filters,
          sortOption: _state.sortOption,
          keyword: _state.keyword,
        ),
      );
      trace
        ..metric('categories', categories.length)
        ..metric('items', queried.values.fold<int>(0, (total, items) => total + items.length))
        ..metric('blocking', shouldBlock);
      if (_disposed || generation != _reloadGeneration) {
        return;
      }

      final resolved = _resolveCategoryVisibility(
        sourceCategories: categories,
        itemsByCategory: queried,
      );

      final selectedCategoryId = _resolveSelectedCategoryId(
        categories: resolved.visibleCategories,
        preferred: _state.selectedCategoryId,
      );

      _state = _state.copyWith(
        isLoading: false,
        displayMode: displaySettings.displayMode,
        gridColumnCount: _normalizeGridColumnCount(displaySettings.gridColumnCount),
        categories: resolved.visibleCategories,
        selectedCategoryId: selectedCategoryId,
        itemsByCategory: queried,
        visibleMatchCountByCategory: resolved.visibleMatchCountByCategory,
        clearError: true,
      );
      _startCoverWarmup(generation: generation);
    } catch (error) {
      if (_disposed || generation != _reloadGeneration) {
        return;
      }
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '$error',
      );
    } finally {
      trace.finish();
    }
  }

  void _handleTaskProgressChanged() {
    final active = _taskProgressListenable?.value?.active ?? false;
    final completedBackgroundTask = _taskProgressWasActive && !active;
    _taskProgressWasActive = active;
    if (!completedBackgroundTask || _disposed || _adapterRefreshInProgress) {
      return;
    }
    // Background tasks such as the first favorite sync can populate a local
    // snapshot after the page has already rendered. Reload metadata once the
    // task settles so the visible shelf catches up without user intervention.
    unawaited(() async {
      await _reload();
      if (!_disposed) {
        _onStateChanged?.call();
      }
    }());
  }

  void _startCoverWarmup({required int generation}) {
    final warmupAdapter = _adapter is ShelfCoverWarmupAdapter
        ? _adapter as ShelfCoverWarmupAdapter
        : null;
    if (warmupAdapter == null) {
      return;
    }
    final snapshot = _state;
    unawaited(() async {
      try {
        final requests = await warmupAdapter.buildCoverWarmupRequests(
          itemsByCategory: snapshot.itemsByCategory,
          selectedCategoryId: snapshot.selectedCategoryId,
        );
        await _coverWarmupService.warmCovers(
          requests: requests,
          warmCover: warmupAdapter.warmCover,
          onResult: (result) {
            if (_disposed || generation != _reloadGeneration) {
              return;
            }
            _applyCoverWarmupResult(result);
          },
        );
      } catch (_) {
        // Cover warmup is an opportunistic background path. Request building
        // failures must not escape into Flutter's unawaited future handler.
      }
    }());
  }

  void _applyCoverWarmupResult(ShelfCoverWarmupResult result) {
    final nextItemsByCategory = <String, List<LibraryWorkItem>>{};
    var changed = false;
    for (final entry in _state.itemsByCategory.entries) {
      final nextItems = <LibraryWorkItem>[];
      var categoryChanged = false;
      for (final item in entry.value) {
        if (item.workId != result.workId) {
          nextItems.add(item);
          continue;
        }
        final nextCoverLocalPath = result.coverLocalPath ?? item.coverLocalPath;
        final nextCustomCoverLocalPath = result.customCoverLocalPath ?? item.customCoverLocalPath;
        final itemChanged = nextCoverLocalPath != item.coverLocalPath ||
            nextCustomCoverLocalPath != item.customCoverLocalPath;
        if (!itemChanged) {
          nextItems.add(item);
          continue;
        }
        final next = item.copyWith(
          coverLocalPath: nextCoverLocalPath,
          customCoverLocalPath: nextCustomCoverLocalPath,
        );
        nextItems.add(next);
        categoryChanged = true;
      }
      nextItemsByCategory[entry.key] = categoryChanged
          ? List<LibraryWorkItem>.unmodifiable(nextItems)
          : entry.value;
      changed = changed || categoryChanged;
    }
    if (!changed) {
      return;
    }
    _state = _state.copyWith(itemsByCategory: Map<String, List<LibraryWorkItem>>.unmodifiable(nextItemsByCategory));
    _onStateChanged?.call();
  }

  _ResolvedCategoryState _resolveCategoryVisibility({
    required List<LibraryCategory> sourceCategories,
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
  }) {
    final visibleMatchCountByCategory = <String, int>{
      for (final category in sourceCategories)
        category.categoryId: (itemsByCategory[category.categoryId] ?? const <LibraryWorkItem>[]).length,
    };

    final defaultCategory = sourceCategories.where((e) => e.isDefault).cast<LibraryCategory?>().firstWhere(
          (e) => e != null,
          orElse: () => null,
        );

    final defaultCount = defaultCategory == null
        ? (itemsByCategory['default'] ?? const <LibraryWorkItem>[]).length
        : (visibleMatchCountByCategory[defaultCategory.categoryId] ?? 0);

    final hasAnyNonDefaultItem = sourceCategories.any((category) {
      if (category.isDefault) {
        return false;
      }
      final count = visibleMatchCountByCategory[category.categoryId] ?? 0;
      return count > 0;
    });

    var visibleCategories = List<LibraryCategory>.from(sourceCategories);

    // 规则1：default 空且其它分类有内容时，隐藏 default。
    if (defaultCategory != null && defaultCount <= 0 && hasAnyNonDefaultItem) {
      visibleCategories = visibleCategories.where((category) => !category.isDefault).toList(growable: false);
    }

    // 规则2：若没有 default 但出现未分类作品，自动在最左补一个 default。
    if (defaultCategory == null && defaultCount > 0) {
      final synthetic = LibraryCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: -1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        visibleMatchCount: defaultCount,
      );
      visibleCategories = <LibraryCategory>[synthetic, ...visibleCategories];
      visibleMatchCountByCategory['default'] = defaultCount;
    }

    return _ResolvedCategoryState(
      visibleCategories: visibleCategories,
      visibleMatchCountByCategory: visibleMatchCountByCategory,
    );
  }

  String _resolveSelectedCategoryId({
    required List<LibraryCategory> categories,
    required String preferred,
  }) {
    if (categories.isEmpty) {
      return 'default';
    }
    final hit = categories.any((category) => category.categoryId == preferred);
    if (hit) {
      return preferred;
    }
    return categories.first.categoryId;
  }

  int _normalizeGridColumnCount(int value) {
    if (value < 1) {
      return 1;
    }
    if (value > 10) {
      return 10;
    }
    return value;
  }

  bool _hasAnyContent(UnifiedShelfState state) {
    if (state.categories.isNotEmpty) {
      return true;
    }
    return state.itemsByCategory.values.any((items) => items.isNotEmpty);
  }
}

class _ResolvedCategoryState {
  const _ResolvedCategoryState({
    required this.visibleCategories,
    required this.visibleMatchCountByCategory,
  });

  final List<LibraryCategory> visibleCategories;
  final Map<String, int> visibleMatchCountByCategory;
}
