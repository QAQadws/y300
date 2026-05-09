import 'package:flutter/foundation.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

class FavoriteShelfAdapter implements ShelfModuleAdapter {
  FavoriteShelfAdapter(
    this._repository, {
    required FavoriteSyncService syncService,
    required LibraryStateRepository stateRepository,
  })  : _syncService = syncService,
        _stateRepository = stateRepository,
        _taskProgress = _FavoriteShelfTaskProgressListenable(syncService.progress);

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  final LibraryStateRepository _stateRepository;
  final ValueListenable<LibraryShelfTaskProgress?> _taskProgress;
  var _initialSyncAttempted = false;

  @override
  ValueListenable<LibraryShelfTaskProgress?> get taskProgress => _taskProgress;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.favorite;

  @override
  String get moduleTitle => '收藏';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    await _ensureInitialSync();
    return _repository.loadVisibleCategories();
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) {
    return _repository.loadCategoryItems(categoryId);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    final categories = await _repository.loadVisibleCategories();
    return _repository.queryItems(
      categories: categories,
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: keyword,
    );
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) {
    return _repository.queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
  }

  @override
  Future<void> refreshShelf() async {
    await _syncService.sync();
  }

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
    final target = await _repository.getRouteTargetByShelfWorkId(workId);
    if (target == null) {
      throw StateError('收藏记录不存在');
    }
    return target;
  }

  @override
  Future<String> createCategory({required String name}) {
    return _repository.createCategory(name: name);
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) {
    return _repository.renameCategory(categoryId: categoryId, newName: newName);
  }

  @override
  Future<void> deleteCategory({required String categoryId}) {
    return _repository.deleteCategory(categoryId: categoryId);
  }

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    final tid = FavoriteShelfWorkId.parseTid(workId);
    if (tid == null) {
      return;
    }
    await _repository.moveThreadToCategory(
      tid: tid,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  }) {
    return _stateRepository.upsertDisplaySettings(
      moduleKey: LibraryModuleKey.favorite,
      displayMode: displayMode,
      gridColumns: gridColumnCount,
    );
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    final settings = await _stateRepository.getDisplaySettings(
      moduleKey: LibraryModuleKey.favorite,
      defaultDisplayMode: LibraryDisplayMode.list,
    );
    return LibraryDisplayPreference(
      displayMode: settings.displayMode,
      gridColumnCount: settings.gridColumns,
    );
  }

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) {
    return _repository.pickRandomWorkId(categoryId: categoryId);
  }

  Future<void> _ensureInitialSync() async {
    if (_initialSyncAttempted) {
      return;
    }
    _initialSyncAttempted = true;
    final snapshot = await _repository.getSyncSnapshot();
    if (snapshot != null) {
      return;
    }
    // 首次进入收藏页时建立本地缓存；失败交给统一书架错误区展示。
    await _syncService.sync();
  }
}

class _FavoriteShelfTaskProgressListenable implements ValueListenable<LibraryShelfTaskProgress?> {
  const _FavoriteShelfTaskProgressListenable(this._source);

  final ValueListenable<FavoriteSyncProgress> _source;

  @override
  LibraryShelfTaskProgress? get value {
    // 把收藏同步内部阶段翻译成 shared 层通用进度，避免 UnifiedShelfPage 依赖 favorites 包。
    final progress = _source.value;
    if (!progress.isActive) {
      return null;
    }
    return LibraryShelfTaskProgress(
      message: progress.message,
      current: progress.current,
      total: progress.total,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _source.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _source.removeListener(listener);
  }
}
