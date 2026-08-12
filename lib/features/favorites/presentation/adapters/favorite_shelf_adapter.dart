import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
typedef ShelfCategoryAssignUseCaseResolver =
    ShelfCategoryAssignUseCase? Function();
typedef UnfavoriteThreadUseCaseResolver = UnfavoriteThreadUseCase? Function();

class FavoriteShelfAdapter
    implements
        ShelfModuleAdapter,
        ShelfDownloadStatusAdapter,
        ShelfSnapshotAdapter,
        ShelfSelectionActionAdapter {
  FavoriteShelfAdapter(
    this._repository, {
    required FavoriteSyncService syncService,
    LibraryTaskProgressHub? taskProgressHub,
    LibraryShelfRefreshBus? shelfRefreshBus,
    ShelfCategoryAssignUseCase? categoryAssignUseCase,
    ShelfCategoryAssignUseCaseResolver? categoryAssignUseCaseResolver,
    UnfavoriteThreadUseCase? unfavoriteThreadUseCase,
    UnfavoriteThreadUseCaseResolver? unfavoriteThreadUseCaseResolver,
  }) : _syncService = syncService,
       _shelfRefreshBus = shelfRefreshBus,
       _categoryAssignUseCaseResolver =
           categoryAssignUseCaseResolver ?? (() => categoryAssignUseCase),
       _unfavoriteThreadUseCaseResolver =
           unfavoriteThreadUseCaseResolver ?? (() => unfavoriteThreadUseCase),
       _supportsCategoryAssign =
           categoryAssignUseCase != null ||
           categoryAssignUseCaseResolver != null,
       _supportsUnfavorite =
           unfavoriteThreadUseCase != null ||
           unfavoriteThreadUseCaseResolver != null,
       _taskProgress = taskProgressHub?.progressFor(LibraryModuleKey.favorite);

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final ShelfCategoryAssignUseCaseResolver _categoryAssignUseCaseResolver;
  final UnfavoriteThreadUseCaseResolver _unfavoriteThreadUseCaseResolver;
  final bool _supportsCategoryAssign;
  final bool _supportsUnfavorite;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgress;

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => _taskProgress;

  @override
  List<SelectionAction> get selectionActions {
    final actions = <SelectionAction>[];
    if (_supportsCategoryAssign) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.assignCategory,
          icon: Icons.label_outline,
        ),
      );
    }
    if (_supportsUnfavorite) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.unfavorite,
          icon: Icons.favorite_border,
          destructive: true,
          needsConfirm: true,
        ),
      );
    }
    return actions;
  }

  @override
  ValueListenable<LibraryShelfRefreshSignal?>? get shelfRefreshSignals {
    return _shelfRefreshBus?.signal;
  }

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.favorite;

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return _repository.loadVisibleCategories();
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    final items = await _repository.loadCategoryItems(categoryId);
    return items
        .map(_withoutOrdinaryCoverWhenCustomIsPending)
        .toList(growable: false);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    final categories = await _repository.loadVisibleCategories();
    final queried = await _repository.queryItems(
      categories: categories,
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: keyword,
    );
    return _withoutOrdinaryCoversWhenCustomIsPending(queried);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final queried = await _repository.queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
    return _withoutOrdinaryCoversWhenCustomIsPending(queried);
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final snapshotRepository = _repository is FavoriteShelfSnapshotRepository
        ? _repository as FavoriteShelfSnapshotRepository
        : null;
    if (snapshotRepository != null) {
      final snapshot = await snapshotRepository.queryShelfSnapshot(
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      return LibraryShelfSnapshot(
        categories: snapshot.categories,
        itemsByCategory: _withoutOrdinaryCoversWhenCustomIsPending(
          snapshot.itemsByCategory,
        ),
        visibleMatchCountByCategory: snapshot.visibleMatchCountByCategory,
      );
    }

    final categories = await loadCategories();
    final queried = await queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
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

  @override
  Future<void> refreshShelf() async {
    await _syncService.sync();
  }

  Map<String, List<LibraryWorkItem>> _withoutOrdinaryCoversWhenCustomIsPending(
    Map<String, List<LibraryWorkItem>> source,
  ) {
    return <String, List<LibraryWorkItem>>{
      for (final entry in source.entries)
        entry.key: entry.value
            .map(_withoutOrdinaryCoverWhenCustomIsPending)
            .toList(growable: false),
    };
  }

  LibraryWorkItem _withoutOrdinaryCoverWhenCustomIsPending(
    LibraryWorkItem item,
  ) {
    final customSource = item.customCoverImageUrl?.trim();
    final customLocal = item.customCoverLocalPath?.trim();
    if (customSource == null ||
        customSource.isEmpty ||
        (customLocal != null && customLocal.isNotEmpty)) {
      return item;
    }
    return item.copyWith(clearCoverLocalPath: true);
  }

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
    final target = await _repository.getRouteTargetByShelfWorkId(workId);
    if (target == null) {
      throw StateError('Favorite route target is missing');
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
  Future<String?> pickRandomWorkId({required String categoryId}) {
    return _repository.pickRandomWorkId(categoryId: categoryId);
  }

  @override
  Future<SelectionActionOutcome> runSelectionAction(
    SelectionActionExecutionRequest request,
  ) async {
    switch (request.actionId) {
      case SelectionActionIds.assignCategory:
        return _runAssignCategory(request);
      case SelectionActionIds.unfavorite:
        return _runUnfavorite(request);
      case SelectionActionIds.markAllRead:
      case SelectionActionIds.markAllUnread:
      case SelectionActionIds.download:
        return const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.unsupported,
        );
    }
    return const SelectionActionOutcome(
      code: SelectionActionOutcomeCode.unsupported,
    );
  }

  Future<SelectionActionOutcome> _runAssignCategory(
    SelectionActionExecutionRequest request,
  ) async {
    final useCase = _categoryAssignUseCaseResolver();
    final targetCategoryId = request.targetCategoryId?.trim();
    if (useCase == null) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.unsupported,
      );
    }
    if (targetCategoryId == null || targetCategoryId.isEmpty) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.missingTargetCategory,
      );
    }
    final result = await useCase.assign(
      workIds: request.workIds,
      sourceCategoryId: request.activeCategoryId,
      targetCategoryId: targetCategoryId,
    );
    final failedCount = result.failedWorkIds.length;
    return SelectionActionOutcome(
      code: failedCount > 0
          ? SelectionActionOutcomeCode.partialFailure
          : SelectionActionOutcomeCode.success,
      changed: result.assignedWorkIds.isNotEmpty,
      succeededCount: result.assignedWorkIds.length,
      failedCount: failedCount,
    );
  }

  Future<SelectionActionOutcome> _runUnfavorite(
    SelectionActionExecutionRequest request,
  ) async {
    final useCase = _unfavoriteThreadUseCaseResolver();
    if (useCase == null) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.unsupported,
      );
    }
    final tids = <String>{};
    var invalidCount = 0;
    for (final rawWorkId in request.workIds) {
      final tid = FavoriteShelfWorkId.parseTid(rawWorkId.trim());
      if (tid == null) {
        invalidCount += 1;
        continue;
      }
      tids.add(tid);
    }
    if (tids.isEmpty) {
      return SelectionActionOutcome(
        code: SelectionActionOutcomeCode.noValidItems,
        failedCount: invalidCount,
      );
    }
    final result = await useCase.callMany(tids);
    final failedCount = result.failedTids.length + invalidCount;
    return SelectionActionOutcome(
      code: failedCount > 0
          ? SelectionActionOutcomeCode.partialFailure
          : SelectionActionOutcomeCode.success,
      changed: result.succeededTids.isNotEmpty,
      succeededCount: result.succeededTids.length,
      failedCount: failedCount,
    );
  }

}
