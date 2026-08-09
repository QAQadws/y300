import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/image_loading/domain/image_prefetcher.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_snapshot_diff.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';
import 'package:y300/features/library_shared/domain/services/shelf_perf_trace.dart';

/// 统一书架页面状态。
///
/// 该状态对象用于驱动 Phase 3 的统一 UI。
class UnifiedShelfState {
  const UnifiedShelfState({
    required this.moduleKey,
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
    required LibraryDisplayMode defaultDisplayMode,
    LibraryShelfSortOption defaultSortOption = LibraryShelfSortOption.defaults,
  }) {
    return UnifiedShelfState(
      moduleKey: moduleKey,
      isLoading: true,
      isSearchMode: false,
      keyword: '',
      filters: LibraryFilterSet.defaults,
      sortOption: defaultSortOption,
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
      visibleMatchCountByCategory:
          visibleMatchCountByCategory ?? this.visibleMatchCountByCategory,
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
    LibraryViewPreferencesRepository? viewPreferencesRepository,
    int coverPrefetchConcurrency = 3,
    ImagePrefetcher Function(
      ImagePrefetchRunner runner,
      ImagePrefetcherSnapshotHandler onSnapshot,
    )?
    coverPrefetcherFactory,
    ShelfFeatureFlags featureFlags = ShelfFeatureFlags.defaults,
    void Function()? onStateChanged,
    bool backgroundReloadEnabled = true,
    LibraryTaskProgressHub? taskProgressHub,
    ForumImagePrecacheService Function()? coverPrecacheServiceResolver,
  }) : _adapter = adapter,
       _viewPreferencesRepository =
           viewPreferencesRepository ??
           VolatileLibraryViewPreferencesRepository(),
       _coverPrefetchConcurrency = coverPrefetchConcurrency,
       _coverPrefetcherFactory = coverPrefetcherFactory,
       _featureFlags = featureFlags,
       _onStateChanged = onStateChanged,
       _backgroundReloadEnabled = backgroundReloadEnabled,
       _coverPrecacheServiceResolver = coverPrecacheServiceResolver,
       _taskProgressListenable = adapter.taskProgress,
       _shelfRefreshSignals = adapter.shelfRefreshSignals,
       _state = _initialState(adapter),
       _stateListenable = ValueNotifier<UnifiedShelfState>(
         _initialState(adapter),
       ) {
    final warmupAdapter = adapter is ShelfCoverWarmupAdapter
        ? adapter as ShelfCoverWarmupAdapter
        : null;
    if (taskProgressHub != null && warmupAdapter != null) {
      final progress = ValueNotifier<LibraryShelfTaskProgress?>(null);
      _coverWarmupProgress = progress;
      _coverWarmupProgressRegistration = taskProgressHub.registerSource(
        modules: <LibraryModuleKey>{adapter.moduleKey},
        progress: progress,
        priority: LibraryTaskProgressPriority.low,
      );
    }
    final taskProgressListenable = _taskProgressListenable;
    _lastTaskProgress = taskProgressListenable?.value;
    taskProgressListenable?.addListener(_handleTaskProgressChanged);
    _shelfRefreshSignals?.addListener(_handleShelfRefreshSignalChanged);
  }

  final ShelfModuleAdapter _adapter;
  final LibraryViewPreferencesRepository _viewPreferencesRepository;
  final int _coverPrefetchConcurrency;
  final ImagePrefetcher Function(
    ImagePrefetchRunner runner,
    ImagePrefetcherSnapshotHandler onSnapshot,
  )?
  _coverPrefetcherFactory;
  final ShelfFeatureFlags _featureFlags;
  final LibraryShelfSnapshotDiffer _snapshotDiffer =
      const LibraryShelfSnapshotDiffer();
  final void Function()? _onStateChanged;
  final ForumImagePrecacheService Function()? _coverPrecacheServiceResolver;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgressListenable;
  final ValueListenable<LibraryShelfRefreshSignal?>? _shelfRefreshSignals;
  UnifiedShelfState _state;
  final ValueNotifier<UnifiedShelfState> _stateListenable;
  static const Duration _keywordDebounceDuration = Duration(milliseconds: 250);
  static const Duration _backgroundReloadThrottleDuration = Duration(
    seconds: 1,
  );
  Timer? _keywordDebounceTimer;
  Timer? _backgroundReloadTimer;
  Completer<void>? _pendingKeywordCompleter;
  final Map<String, ShelfCoverVisibleRange> _visibleRangesByCategory =
      <String, ShelfCoverVisibleRange>{};

  /// 持久化封面预取器：跨可见区变化复用，只重排不取消可见项（替代旧的
  /// cancel-restart 令牌）。懒创建于首次预热。
  ImagePrefetcher? _coverPrefetcher;
  ValueNotifier<LibraryShelfTaskProgress?>? _coverWarmupProgress;
  LibraryTaskProgressRegistration? _coverWarmupProgressRegistration;
  LibraryShelfTaskProgress? _lastTaskProgress;
  bool _adapterRefreshInProgress = false;
  bool _backgroundReloadInProgress = false;
  bool _backgroundReloadRequested = false;
  bool _backgroundReloadEnabled;
  bool _viewPreferencesLoaded = false;
  String? _preferredCategoryId;
  var _disposed = false;
  var _reloadGeneration = 0;

  UnifiedShelfState get state => _state;

  ValueListenable<UnifiedShelfState> get stateListenable => _stateListenable;

  static UnifiedShelfState _initialState(ShelfModuleAdapter adapter) {
    final capabilities = resolveShelfModuleCapabilities(adapter);
    return UnifiedShelfState.initial(
      moduleKey: adapter.moduleKey,
      defaultDisplayMode: adapter.defaultDisplayMode,
      defaultSortOption: capabilities.defaultSortOption,
    );
  }

  /// 释放控制器内部的异步资源，避免页面销毁后残留定时器。
  void dispose() {
    _disposed = true;
    _reloadGeneration++;
    _coverPrefetcher?.dispose();
    _coverPrefetcher = null;
    _coverWarmupProgress?.value = null;
    _coverWarmupProgressRegistration?.dispose();
    _coverWarmupProgressRegistration = null;
    _coverWarmupProgress?.dispose();
    _coverWarmupProgress = null;
    _taskProgressListenable?.removeListener(_handleTaskProgressChanged);
    _shelfRefreshSignals?.removeListener(_handleShelfRefreshSignalChanged);
    _stateListenable.dispose();
    _cancelPendingKeywordReload();
    _backgroundReloadTimer?.cancel();
    _backgroundReloadTimer = null;
  }

  Future<void> initialize() async {
    await _reload();
  }

  Future<void> refresh() async {
    await _reload();
  }

  void setBackgroundReloadEnabled(bool enabled) {
    if (_backgroundReloadEnabled == enabled) {
      return;
    }
    _backgroundReloadEnabled = enabled;
    if (!enabled) {
      _backgroundReloadTimer?.cancel();
      _backgroundReloadTimer = null;
      return;
    }
    if (_backgroundReloadRequested) {
      _requestBackgroundReload();
    }
  }

  Future<void> enterSearchMode() async {
    _setState(_state.copyWith(isSearchMode: true, clearError: true));
  }

  Future<void> exitSearchMode() async {
    final shouldRestore = _state.isSearchMode || _state.keyword.isNotEmpty;
    _cancelPendingKeywordReload();
    if (!shouldRestore) {
      return;
    }
    _setState(
      _state.copyWith(isSearchMode: false, keyword: '', clearError: true),
    );
    await _reload();
  }

  Future<void> updateKeyword(String value) async {
    _setState(_state.copyWith(keyword: value));
    _cancelPendingKeywordReload();
    final completer = Completer<void>();
    _pendingKeywordCompleter = completer;
    _keywordDebounceTimer = Timer(_keywordDebounceDuration, () async {
      try {
        await _reload();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
        if (identical(_pendingKeywordCompleter, completer)) {
          _pendingKeywordCompleter = null;
          _keywordDebounceTimer = null;
        }
      }
    });
    await completer.future;
  }

  void _cancelPendingKeywordReload() {
    _keywordDebounceTimer?.cancel();
    _keywordDebounceTimer = null;
    final completer = _pendingKeywordCompleter;
    _pendingKeywordCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> selectCategory(String categoryId) async {
    if (_state.selectedCategoryId == categoryId &&
        _preferredCategoryId == categoryId) {
      return;
    }
    _preferredCategoryId = categoryId;
    if (_state.selectedCategoryId != categoryId) {
      _setState(_state.copyWith(selectedCategoryId: categoryId));
    }
    await _persistViewPreferences();
    _startCoverWarmup(generation: _reloadGeneration);
  }

  void reportVisibleRange({
    required String categoryId,
    required int firstIndex,
    required int lastIndex,
  }) {
    if (_disposed) {
      return;
    }
    final range = ShelfCoverVisibleRange(
      firstIndex: firstIndex,
      lastIndex: lastIndex,
    );
    if (_visibleRangesByCategory[categoryId] == range) {
      return;
    }
    _visibleRangesByCategory[categoryId] = range;
    if (categoryId == _state.selectedCategoryId) {
      _startCoverWarmup(generation: _reloadGeneration);
    }
  }

  Future<void> updateFilters(LibraryFilterSet filters) async {
    _setState(_state.copyWith(filters: _normalizeFilters(filters)));
    await _persistViewPreferences();
    await _reload();
  }

  Future<void> updateSortOption(LibraryShelfSortOption option) async {
    final capabilities = resolveShelfModuleCapabilities(_adapter);
    _setState(
      _state.copyWith(sortOption: capabilities.normalizeSortOption(option)),
    );
    await _persistViewPreferences();
    await _reload();
  }

  Future<void> updateDisplayMode(LibraryDisplayMode mode) async {
    _setState(_state.copyWith(displayMode: mode));
    await _persistViewPreferences();
  }

  Future<void> updateGridColumnCount(int count) async {
    final normalized = _normalizeGridColumnCount(count);
    _setState(_state.copyWith(gridColumnCount: normalized));
    await _persistViewPreferences();
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
    final index = _state.categories.indexWhere(
      (e) => e.categoryId == _state.selectedCategoryId,
    );
    if (index < 0) {
      return _state.categories.first;
    }
    return _state.categories[index];
  }

  List<LibraryWorkItem> get selectedCategoryItems {
    return _state.itemsByCategory[_state.selectedCategoryId] ??
        const <LibraryWorkItem>[];
  }

  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final trace = ShelfPerfTrace(name: '${_adapter.moduleKey.name}.reload');
    final shouldBlock = !_hasAnyContent(_state);
    final previousSnapshot = _snapshotFromState(_state);
    _setState(
      _state.copyWith(
        isLoading: shouldBlock || !_featureFlags.useStaleWhileRevalidate,
        clearError: true,
      ),
    );
    try {
      await trace.measure('preferences', _ensureViewPreferencesLoaded);
      if (_disposed || generation != _reloadGeneration) {
        return;
      }
      final snapshot = await trace.measure(
        _shouldUseSnapshotAdapter ? 'querySnapshot' : 'queryItems',
        _queryShelfSnapshot,
      );
      trace
        ..metric('categories', snapshot.categories.length)
        ..metric(
          'items',
          snapshot.itemsByCategory.values.fold<int>(
            0,
            (total, items) => total + items.length,
          ),
        )
        ..metric('blocking', shouldBlock);
      if (previousSnapshot != null) {
        final diff = _snapshotDiffer.diff(
          previous: previousSnapshot,
          next: snapshot,
        );
        trace
          ..metric('snapshotAdded', diff.addedWorkIds.length)
          ..metric('snapshotRemoved', diff.removedWorkIds.length)
          ..metric('snapshotChanged', diff.changedWorkIds.length)
          ..metric('snapshotOrderChanged', diff.orderChangedCategoryIds.length);
      }
      if (_disposed || generation != _reloadGeneration) {
        return;
      }

      final resolved = _resolveCategoryVisibility(
        sourceCategories: snapshot.categories,
        itemsByCategory: snapshot.itemsByCategory,
      );

      final preferredCategoryId =
          _preferredCategoryId ??
          (_state.categories.isEmpty ? '' : _state.selectedCategoryId);
      final selectedCategoryId = _resolveSelectedCategoryId(
        categories: resolved.visibleCategories,
        preferred: preferredCategoryId,
      );

      final preferredCategoryStillExists =
          _preferredCategoryId == null ||
          snapshot.categories.any(
            (category) => category.categoryId == _preferredCategoryId,
          );
      final shouldPersistResolvedCategory =
          resolved.visibleCategories.isNotEmpty &&
          (_preferredCategoryId == null || !preferredCategoryStillExists);
      if (shouldPersistResolvedCategory) {
        _preferredCategoryId = selectedCategoryId;
      }

      _setState(
        _state.copyWith(
          isLoading: false,
          categories: resolved.visibleCategories,
          selectedCategoryId: selectedCategoryId,
          itemsByCategory: snapshot.itemsByCategory,
          visibleMatchCountByCategory: resolved.visibleMatchCountByCategory,
          clearError: true,
        ),
      );
      if (shouldPersistResolvedCategory) {
        await _persistViewPreferences();
      }
      _startCoverWarmup(generation: generation);
    } catch (error) {
      if (_disposed || generation != _reloadGeneration) {
        return;
      }
      _setState(_state.copyWith(isLoading: false, errorMessage: '$error'));
    } finally {
      trace.finish();
    }
  }

  Future<LibraryShelfSnapshot> _queryShelfSnapshot() async {
    final snapshotAdapter = _shouldUseSnapshotAdapter
        ? _adapter as ShelfSnapshotAdapter
        : null;
    if (snapshotAdapter != null) {
      return snapshotAdapter.querySnapshot(
        filters: _state.filters,
        sortOption: _state.sortOption,
        keyword: _state.keyword,
      );
    }

    final categories = await _adapter.loadCategories();
    final queried = await _adapter.queryItems(
      categories: categories,
      filters: _state.filters,
      sortOption: _state.sortOption,
      keyword: _state.keyword,
    );
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: queried,
      visibleMatchCountByCategory: <String, int>{
        for (final category in categories)
          category.categoryId:
              (queried[category.categoryId] ?? const <LibraryWorkItem>[])
                  .length,
      },
    );
  }

  LibraryShelfSnapshot? _snapshotFromState(UnifiedShelfState state) {
    if (!_hasAnyContent(state)) {
      return null;
    }
    return LibraryShelfSnapshot(
      categories: state.categories,
      itemsByCategory: state.itemsByCategory,
      visibleMatchCountByCategory: state.visibleMatchCountByCategory,
    );
  }

  bool get _shouldUseSnapshotAdapter {
    return _featureFlags.useShelfSnapshotQuery &&
        _adapter is ShelfSnapshotAdapter;
  }

  void _handleTaskProgressChanged() {
    final nextProgress = _taskProgressListenable?.value;
    final previousProgress = _lastTaskProgress;
    final completedBackgroundTask =
        (previousProgress?.active ?? false) &&
        !(nextProgress?.active ?? false) &&
        (previousProgress?.reloadOnCompletion ?? false);
    _lastTaskProgress = nextProgress;
    if (!completedBackgroundTask || _disposed || _adapterRefreshInProgress) {
      return;
    }
    // Background tasks such as the first favorite sync can populate a local
    // snapshot after the page has already rendered. Reload metadata once the
    // task settles so the visible shelf catches up without user intervention.
    _requestBackgroundReload();
  }

  void _handleShelfRefreshSignalChanged() {
    final signal = _shelfRefreshSignals?.value;
    if (signal == null ||
        !signal.modules.contains(_adapter.moduleKey) ||
        _disposed ||
        _adapterRefreshInProgress) {
      return;
    }
    _requestBackgroundReload();
  }

  void _requestBackgroundReload() {
    if (_disposed || _adapterRefreshInProgress) {
      return;
    }
    _backgroundReloadRequested = true;
    if (!_backgroundReloadEnabled) {
      return;
    }
    if (_backgroundReloadInProgress || _backgroundReloadTimer != null) {
      return;
    }
    _backgroundReloadTimer = Timer(
      _backgroundReloadThrottleDuration,
      _runRequestedBackgroundReload,
    );
  }

  void _runRequestedBackgroundReload() {
    _backgroundReloadTimer = null;
    if (_disposed || _adapterRefreshInProgress || !_backgroundReloadRequested) {
      return;
    }
    _backgroundReloadRequested = false;
    _backgroundReloadInProgress = true;
    unawaited(() async {
      try {
        await _reload();
        if (!_disposed) {
          _onStateChanged?.call();
        }
      } finally {
        _backgroundReloadInProgress = false;
        if (!_disposed && _backgroundReloadRequested) {
          _requestBackgroundReload();
        }
      }
    }());
  }

  void _startCoverWarmup({required int generation}) {
    final warmupAdapter = _adapter is ShelfCoverWarmupAdapter
        ? _adapter as ShelfCoverWarmupAdapter
        : null;
    if (!_featureFlags.useShelfCoverQueue || warmupAdapter == null) {
      _setCoverWarmupProgress(null, generation: generation);
      return;
    }
    final prefetcher = _ensureCoverPrefetcher(warmupAdapter);
    final snapshot = _state;
    unawaited(() async {
      try {
        final requests = await warmupAdapter.buildCoverWarmupRequests(
          itemsByCategory: snapshot.itemsByCategory,
          selectedCategoryId: snapshot.selectedCategoryId,
        );
        if (_disposed || generation != _reloadGeneration) {
          return;
        }
        final prioritized = prioritizeShelfCoverWarmupRequests(
          requests: requests,
          itemsByCategory: snapshot.itemsByCategory,
          categories: snapshot.categories,
          selectedCategoryId: snapshot.selectedCategoryId,
          visibleRangesByCategory: Map<String, ShelfCoverVisibleRange>.from(
            _visibleRangesByCategory,
          ),
          displayMode: snapshot.displayMode,
          gridColumnCount: snapshot.gridColumnCount,
        );
        if (prioritized.isEmpty) {
          return;
        }
        // 只重排、不取消：把新窗口的优先级合并进持久队列。快速滚动时可见项
        // （priority=currentViewport）始终排在最前，且正在运行的下载不被打断。
        prefetcher.submit(<ImagePrefetchRequest>[
          for (final request in prioritized)
            ImagePrefetchRequest(
              dedupeKey: request.dedupeKey,
              priority: request.priority.index,
              payload: request,
            ),
        ]);
      } catch (_) {
        // Cover warmup is an opportunistic background path. Request building
        // failures must not escape into Flutter's unawaited future handler.
      }
    }());
  }

  /// 懒创建持久封面预取器。runner 执行实际预热与写回，snapshot 驱动进度提示。
  ImagePrefetcher _ensureCoverPrefetcher(
    ShelfCoverWarmupAdapter warmupAdapter,
  ) {
    final existing = _coverPrefetcher;
    if (existing != null) {
      return existing;
    }
    Future<bool> runner(ImagePrefetchRequest request) async {
      if (_disposed) {
        return false;
      }
      final coverRequest = request.payload as ShelfCoverWarmupRequest;
      final result = await _warmCover(
        warmupAdapter: warmupAdapter,
        coverRequest: coverRequest,
      );
      if (_disposed || result == null || !result.hasPath) {
        return false;
      }
      // workId 已不在当前书架时，_applyCoverWarmupResult 自然 no-op。
      _applyCoverWarmupResult(result);
      return true;
    }

    void onSnapshot(ImagePrefetcherSnapshot snapshot) {
      if (_disposed) {
        return;
      }
      final progress = snapshot.isIdle
          ? null
          : LibraryShelfTaskProgress(
              code: LibraryShelfTaskProgressCode.coverWarmup,
              current: snapshot.runningCount,
              total: snapshot.runningCount + snapshot.pendingCount,
              source: LibraryMutationSource.coverWarmup,
              visible: false,
              reloadOnCompletion: false,
            );
      _setCoverWarmupProgress(progress, generation: _reloadGeneration);
    }

    final factory = _coverPrefetcherFactory;
    final prefetcher = factory != null
        ? factory(runner, onSnapshot)
        : DefaultImagePrefetcher(
            runner: runner,
            onSnapshot: onSnapshot,
            maxConcurrent: _coverPrefetchConcurrency,
          );
    _coverPrefetcher = prefetcher;
    return prefetcher;
  }

  Future<ShelfCoverWarmupResult?> _warmCover({
    required ShelfCoverWarmupAdapter warmupAdapter,
    required ShelfCoverWarmupRequest coverRequest,
  }) async {
    final precacheService = _coverPrecacheServiceResolver?.call();
    if (precacheService == null) {
      return warmupAdapter.warmCover(coverRequest);
    }
    final result = await precacheService.ensureDiskCached(
      coverRequest.imageSpec,
    );
    final localPath = result.localPath?.trim();
    if (!result.success || localPath == null || localPath.isEmpty) {
      return null;
    }
    return warmupAdapter.applyWarmedCover(
      request: coverRequest,
      localPath: localPath,
    );
  }

  void _setCoverWarmupProgress(
    LibraryShelfTaskProgress? progress, {
    required int generation,
  }) {
    final notifier = _coverWarmupProgress;
    if (notifier == null || _disposed || generation != _reloadGeneration) {
      return;
    }
    notifier.value = progress;
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
        final nextCustomCoverLocalPath =
            result.customCoverLocalPath ?? item.customCoverLocalPath;
        final itemChanged =
            nextCoverLocalPath != item.coverLocalPath ||
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
    _setState(
      _state.copyWith(
        itemsByCategory: Map<String, List<LibraryWorkItem>>.unmodifiable(
          nextItemsByCategory,
        ),
      ),
    );
  }

  void _setState(UnifiedShelfState next) {
    if (identical(_state, next)) {
      return;
    }
    _state = next;
    if (!_disposed) {
      _stateListenable.value = next;
    }
  }

  _ResolvedCategoryState _resolveCategoryVisibility({
    required List<LibraryCategory> sourceCategories,
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
  }) {
    final visibleMatchCountByCategory = <String, int>{
      for (final category in sourceCategories)
        category.categoryId:
            (itemsByCategory[category.categoryId] ?? const <LibraryWorkItem>[])
                .length,
    };

    final defaultCategory = sourceCategories
        .where((e) => e.isDefault)
        .cast<LibraryCategory?>()
        .firstWhere((e) => e != null, orElse: () => null);

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
      visibleCategories = visibleCategories
          .where((category) => !category.isDefault)
          .toList(growable: false);
    }

    // 规则2：若没有 default 但出现未分类作品，自动在最左补一个 default。
    if (defaultCategory == null && defaultCount > 0) {
      final synthetic = LibraryCategory(
        categoryId: 'default',
        name: '',
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

  Future<void> _ensureViewPreferencesLoaded() async {
    if (_viewPreferencesLoaded) {
      return;
    }
    final capabilities = resolveShelfModuleCapabilities(_adapter);
    final defaults = LibraryShelfViewPreferences.defaults(
      moduleKey: _adapter.moduleKey,
      displayMode: _adapter.defaultDisplayMode,
      sortOption: capabilities.defaultSortOption,
    );
    final loaded = await _viewPreferencesRepository.load(defaults: defaults);
    final normalized = loaded.copyWith(
      gridColumnCount: _normalizeGridColumnCount(loaded.gridColumnCount),
      filters: _normalizeFilters(loaded.filters),
      sortOption: capabilities.normalizeSortOption(loaded.sortOption),
    );
    _preferredCategoryId = normalized.lastCategoryId;
    _setState(
      _state.copyWith(
        filters: normalized.filters,
        sortOption: normalized.sortOption,
        displayMode: normalized.displayMode,
        gridColumnCount: normalized.gridColumnCount,
        selectedCategoryId: normalized.lastCategoryId ?? 'default',
      ),
    );
    _viewPreferencesLoaded = true;
    if (normalized != loaded) {
      await _viewPreferencesRepository.save(normalized);
    }
  }

  Future<void> _persistViewPreferences() {
    final capabilities = resolveShelfModuleCapabilities(_adapter);
    return _viewPreferencesRepository.save(
      LibraryShelfViewPreferences(
        moduleKey: _adapter.moduleKey,
        displayMode: _state.displayMode,
        gridColumnCount: _normalizeGridColumnCount(_state.gridColumnCount),
        sortOption: capabilities.normalizeSortOption(_state.sortOption),
        filters: _normalizeFilters(_state.filters),
        lastCategoryId: _preferredCategoryId,
      ),
    );
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

  LibraryFilterSet _normalizeFilters(LibraryFilterSet filters) {
    final capabilities = resolveShelfModuleCapabilities(_adapter);
    final normalized = capabilities.normalizeFilters(filters);
    return _adapter is ShelfDownloadStatusAdapter
        ? normalized
        : normalized.copyWith(downloaded: TriStateFilterValue.ignore);
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
