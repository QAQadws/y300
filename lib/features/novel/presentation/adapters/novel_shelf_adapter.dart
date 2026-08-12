import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef ShelfCategoryAssignUseCaseResolver =
    ShelfCategoryAssignUseCase? Function();
typedef UnfavoriteWorkUseCaseResolver = UnfavoriteWorkUseCase? Function();

class NovelShelfAdapter
    implements
        ShelfModuleAdapter,
        ShelfModuleCapabilitiesAdapter,
        ShelfSnapshotAdapter,
        ShelfSelectionActionAdapter {
  NovelShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
    LibraryShelfRefreshBus? shelfRefreshBus,
    LibraryTaskProgressHub? taskProgressHub,
    ShelfCategoryAssignUseCase? categoryAssignUseCase,
    ShelfCategoryAssignUseCaseResolver? categoryAssignUseCaseResolver,
    UnfavoriteWorkUseCase? unfavoriteWorkUseCase,
    UnfavoriteWorkUseCaseResolver? unfavoriteWorkUseCaseResolver,
  }) : _stateRepository = stateRepository,
       _shelfRefreshBus = shelfRefreshBus,
       _taskProgress = taskProgressHub?.progressFor(LibraryModuleKey.novel),
       _categoryAssignUseCaseResolver =
           categoryAssignUseCaseResolver ?? (() => categoryAssignUseCase),
       _unfavoriteWorkUseCaseResolver =
           unfavoriteWorkUseCaseResolver ?? (() => unfavoriteWorkUseCase),
       _supportsCategoryAssign =
           categoryAssignUseCase != null ||
           categoryAssignUseCaseResolver != null,
       _supportsUnfavorite =
           unfavoriteWorkUseCase != null ||
           unfavoriteWorkUseCaseResolver != null;

  final NovelRepository _repository;
  final LibraryStateRepository _stateRepository;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgress;
  final ShelfCategoryAssignUseCaseResolver _categoryAssignUseCaseResolver;
  final UnfavoriteWorkUseCaseResolver _unfavoriteWorkUseCaseResolver;
  final bool _supportsCategoryAssign;
  final bool _supportsUnfavorite;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  ShelfModuleCapabilities get capabilities => const ShelfModuleCapabilities(
    supportsReadState: false,
    supportsBookmarkFilter: true,
  );

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
  Future<List<LibraryCategory>> loadCategories() async {
    final categories = await _repository.getCategories();
    return categories.map(_mapCategory).toList(growable: false);
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    final items = await _repository.getShelfItems(categoryId: categoryId);
    return Future.wait(items.map(_mapWork));
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    final normalized = keyword.trim().toLowerCase();
    final categories = await _repository.getCategories();
    final result = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      final mappedSource = await Future.wait(items.map(_mapWork));
      result[category.categoryId] = mappedSource
          .where((item) {
            if (normalized.isEmpty) {
              return true;
            }
            final title = item.title.toLowerCase();
            final secondary = (item.secondaryName ?? '').toLowerCase();
            return title.contains(normalized) || secondary.contains(normalized);
          })
          .toList(growable: false);
    }
    return result;
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final source = await searchItemsByKeyword(keyword: keyword);
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = source[category.categoryId] ?? const <LibraryWorkItem>[];
      output[category.categoryId] = LibraryShelfQueryUtils.filterAndSort(
        source: items,
        filters: capabilities.normalizeFilters(filters),
        sortOption: capabilities.normalizeSortOption(sortOption),
        keyword: '',
      );
    }
    return output;
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final effectiveFilters = capabilities.normalizeFilters(
      filters.copyWith(downloaded: TriStateFilterValue.ignore),
    );
    final effectiveSortOption = capabilities.normalizeSortOption(sortOption);
    final snapshotRepository = _repository is NovelShelfSnapshotRepository
        ? _repository as NovelShelfSnapshotRepository
        : null;
    if (snapshotRepository != null) {
      return snapshotRepository.queryShelfSnapshot(
        filters: effectiveFilters,
        sortOption: effectiveSortOption,
        keyword: keyword,
      );
    }

    final categories = await loadCategories();
    final itemsByCategory = await queryItems(
      categories: categories,
      filters: effectiveFilters,
      sortOption: effectiveSortOption,
      keyword: keyword,
    );
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: itemsByCategory,
      visibleMatchCountByCategory: <String, int>{
        for (final category in categories)
          category.categoryId:
              (itemsByCategory[category.categoryId] ??
                      const <LibraryWorkItem>[])
                  .length,
      },
    );
  }

  @override
  Future<void> refreshShelf() async {}

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
    return workId;
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
  }) {
    return _repository.moveNovelToCategory(
      novelId: workId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async {
    final items = await loadCategoryItems(categoryId: categoryId);
    if (items.isEmpty) {
      return null;
    }
    final random = Random();
    return items[random.nextInt(items.length)].workId;
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
    final useCase = _unfavoriteWorkUseCaseResolver();
    if (useCase == null) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.unsupported,
      );
    }
    final workKinds = <String, ThreadContentKind>{};
    var invalidCount = 0;
    for (final rawWorkId in request.workIds) {
      final workId = rawWorkId.trim();
      if (workId.isEmpty) {
        invalidCount += 1;
        continue;
      }
      workKinds[workId] = ThreadContentKind.novel;
    }
    if (workKinds.isEmpty) {
      return SelectionActionOutcome(
        code: SelectionActionOutcomeCode.noValidItems,
        failedCount: invalidCount,
      );
    }
    final result = await useCase.callMany(workKinds: workKinds);
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

  LibraryCategory _mapCategory(NovelShelfCategory source) {
    return LibraryCategory(
      categoryId: source.categoryId,
      name: source.name,
      sortOrder: source.sortOrder,
      createdAt: source.createdAt,
    );
  }

  Future<LibraryWorkItem> _mapWork(NovelItem source) async {
    final hasTags = await _stateRepository.hasAnyTag(
      moduleKey: LibraryModuleKey.novel,
      workId: source.novelId,
    );
    final bookmarkQuery = _stateRepository is LibraryBookmarkStateQuery
        ? _stateRepository as LibraryBookmarkStateQuery
        : null;
    final hasBookmarks =
        await bookmarkQuery?.hasAnyBookmarkedEpisode(
          moduleKey: LibraryModuleKey.novel,
          workId: source.novelId,
        ) ??
        false;
    return LibraryWorkItem(
      workId: source.novelId,
      categoryId: source.categoryId,
      title: source.displayTitle,
      secondaryName: source.publisherName,
      coverImageUrl: source.coverHidden ? null : source.coverImageUrl,
      coverLocalPath: source.coverHidden ? null : source.coverLocalPath,
      customCoverLocalPath: source.coverHidden
          ? null
          : source.customCoverLocalPath,
      customCoverFocusX: source.coverHidden ? null : source.customCoverFocusX,
      customCoverFocusY: source.coverHidden ? null : source.customCoverFocusY,
      coverAsset: source.coverHidden
          ? null
          : LibraryCoverAssetFactory.preferred(
              ownerType: 'novel',
              ownerId: source.novelId,
              sourceUrl: source.coverImageUrl,
              sourceLegacyPath: source.coverLocalPath,
              sourceRevision: source.coverRevision,
              customLegacyPath: source.customCoverLocalPath,
              customRevision: source.customCoverRevision,
            ),
      unreadCount: 0,
      totalChapterCount: source.episodeCount,
      readChapterCount: 0,
      addedAt: source.updatedAt,
      workUpdatedAt: source.updatedAt,
      hasTags: hasTags,
      hasBookmarks: hasBookmarks,
    );
  }

}
