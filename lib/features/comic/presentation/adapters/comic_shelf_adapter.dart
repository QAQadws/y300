import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_image_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef ShelfCategoryAssignUseCaseResolver =
    ShelfCategoryAssignUseCase? Function();
typedef ReadingStateBatchWriterResolver = ReadingStateBatchWriter? Function();
typedef BulkDownloadUseCaseResolver = BulkDownloadUseCase? Function();
typedef UnfavoriteWorkUseCaseResolver = UnfavoriteWorkUseCase? Function();

class ComicShelfAdapter
    implements
        ShelfModuleAdapter,
        ShelfModuleCapabilitiesAdapter,
        ShelfDownloadStatusAdapter,
        ShelfSnapshotAdapter,
        ShelfCoverWarmupAdapter,
        ShelfModuleActionAdapter,
        ShelfSelectionActionAdapter {
  ComicShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
    ImageCacheService? imageCacheService,
    ImageCacheServiceResolver? imageCacheServiceResolver,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
    LibraryShelfRefreshBus? shelfRefreshBus,
    LibraryTaskProgressHub? taskProgressHub,
    ComicDuplicateMergeService? duplicateMergeService,
    ShelfCategoryAssignUseCase? categoryAssignUseCase,
    ShelfCategoryAssignUseCaseResolver? categoryAssignUseCaseResolver,
    ReadingStateBatchWriter? readingStateBatchWriter,
    ReadingStateBatchWriterResolver? readingStateBatchWriterResolver,
    BulkDownloadUseCase? bulkDownloadUseCase,
    BulkDownloadUseCaseResolver? bulkDownloadUseCaseResolver,
    UnfavoriteWorkUseCase? unfavoriteWorkUseCase,
    UnfavoriteWorkUseCaseResolver? unfavoriteWorkUseCaseResolver,
  }) : _stateRepository = stateRepository,
       _featureFlags = featureFlags,
       _duplicateMergeService = duplicateMergeService,
       _shelfRefreshBus = shelfRefreshBus,
       _taskProgress = taskProgressHub?.progressFor(LibraryModuleKey.comic),
       _categoryAssignUseCaseResolver =
           categoryAssignUseCaseResolver ?? (() => categoryAssignUseCase),
       _readingStateBatchWriterResolver =
           readingStateBatchWriterResolver ?? (() => readingStateBatchWriter),
       _bulkDownloadUseCaseResolver =
           bulkDownloadUseCaseResolver ?? (() => bulkDownloadUseCase),
       _unfavoriteWorkUseCaseResolver =
           unfavoriteWorkUseCaseResolver ?? (() => unfavoriteWorkUseCase),
       _supportsCategoryAssign =
           categoryAssignUseCase != null ||
           categoryAssignUseCaseResolver != null,
       _supportsReadingStateBatch =
           readingStateBatchWriter != null ||
           readingStateBatchWriterResolver != null,
       _supportsBulkDownload =
           bulkDownloadUseCase != null || bulkDownloadUseCaseResolver != null,
       _supportsUnfavorite =
           unfavoriteWorkUseCase != null ||
           unfavoriteWorkUseCaseResolver != null,
       _coverCacheService = imageCacheServiceResolver == null
           ? LibraryCoverCacheService(imageCacheService)
           : LibraryCoverCacheService.lazy(imageCacheServiceResolver);

  final ComicRepository _repository;
  final LibraryStateRepository _stateRepository;
  final ComicReaderFeatureFlags _featureFlags;
  final ComicDuplicateMergeService? _duplicateMergeService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgress;
  final ShelfCategoryAssignUseCaseResolver _categoryAssignUseCaseResolver;
  final ReadingStateBatchWriterResolver _readingStateBatchWriterResolver;
  final BulkDownloadUseCaseResolver _bulkDownloadUseCaseResolver;
  final UnfavoriteWorkUseCaseResolver _unfavoriteWorkUseCaseResolver;
  final bool _supportsCategoryAssign;
  final bool _supportsReadingStateBatch;
  final bool _supportsBulkDownload;
  final bool _supportsUnfavorite;
  final LibraryCoverCacheService _coverCacheService;
  final LibraryCoverImageAdapter _coverImageAdapter =
      const LibraryCoverImageAdapter();

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  ShelfModuleCapabilities get capabilities =>
      const ShelfModuleCapabilities.defaults();

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.grid;

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => _taskProgress;

  @override
  List<LibraryShelfMenuAction> get menuActions {
    if (_duplicateMergeService == null) {
      return const <LibraryShelfMenuAction>[];
    }
    return const <LibraryShelfMenuAction>[
      LibraryShelfMenuAction.mergeDuplicates,
    ];
  }

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
    if (_supportsReadingStateBatch) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.markAllRead,
          icon: Icons.done_all,
        ),
      );
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.markAllUnread,
          icon: Icons.remove_done,
        ),
      );
    }
    if (_supportsBulkDownload) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.download,
          icon: Icons.download,
        ),
      );
    }
    if (_supportsUnfavorite) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.unfavorite,
          icon: Icons.star_border,
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
    final categories = await _repository.getCategories();
    final result = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      final mappedSource = await Future.wait(items.map(_mapWork));
      result[category.categoryId] = LibraryShelfQueryUtils.filterAndSort(
        source: mappedSource,
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: keyword,
      );
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
    final source = await _loadMappedItemsByCategory(categories);
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      var items = source[category.categoryId] ?? const <LibraryWorkItem>[];
      items = LibraryShelfQueryUtils.filterAndSort(
        source: items,
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      output[category.categoryId] = items;
    }
    return output;
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final snapshotRepository = _repository is ComicShelfSnapshotRepository
        ? _repository as ComicShelfSnapshotRepository
        : null;
    if (snapshotRepository != null &&
        _featureFlags.readerCustomMetadataEnabled) {
      return snapshotRepository.queryShelfSnapshot(
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
    }

    final categories = await loadCategories();
    final itemsByCategory = await queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
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
    return _repository.moveComicToCategory(
      comicId: workId,
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
  Future<ShelfModuleActionOutcome> runMenuAction(
    LibraryShelfMenuAction action,
  ) async {
    if (action != LibraryShelfMenuAction.mergeDuplicates) {
      return const ShelfModuleActionOutcome(
        code: ShelfModuleActionOutcomeCode.unsupported,
      );
    }
    final service = _duplicateMergeService;
    if (service == null) {
      return const ShelfModuleActionOutcome(
        code: ShelfModuleActionOutcomeCode.unsupported,
      );
    }
    final summary = await service.mergeAllDuplicates();
    if (!summary.changed) {
      return const ShelfModuleActionOutcome(
        code: ShelfModuleActionOutcomeCode.noChange,
      );
    }
    _shelfRefreshBus?.notify(
      modules: const <LibraryModuleKey>{
        LibraryModuleKey.comic,
        LibraryModuleKey.favorite,
      },
      reason: 'comic_duplicate_merge_completed',
      source: LibraryMutationSource.duplicateMerge,
      payload: <String, Object?>{
        'removedComicCount': summary.removedComicCount,
      },
    );
    return ShelfModuleActionOutcome(
      code: ShelfModuleActionOutcomeCode.success,
      changed: true,
      affectedCount: summary.removedComicCount,
    );
  }

  @override
  Future<SelectionActionOutcome> runSelectionAction(
    SelectionActionExecutionRequest request,
  ) async {
    switch (request.actionId) {
      case SelectionActionIds.assignCategory:
        return _runAssignCategory(request);
      case SelectionActionIds.markAllRead:
        return _runReadStateChange(request, isRead: true);
      case SelectionActionIds.markAllUnread:
        return _runReadStateChange(request, isRead: false);
      case SelectionActionIds.download:
        return _runDownload(request);
      case SelectionActionIds.unfavorite:
        return _runUnfavorite(request);
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

  Future<SelectionActionOutcome> _runReadStateChange(
    SelectionActionExecutionRequest request, {
    required bool isRead,
  }) async {
    final writer = _readingStateBatchWriterResolver();
    if (writer == null) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.unsupported,
      );
    }
    final normalizedWorkIds = _normalizedWorkIds(request.workIds);
    if (normalizedWorkIds.isEmpty) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.noValidItems,
      );
    }
    await writer.setWorksRead(
      module: LibraryModuleKey.comic,
      workIds: normalizedWorkIds,
      isRead: isRead,
    );
    final failedCount = request.workIds.length - normalizedWorkIds.length;
    return SelectionActionOutcome(
      code: failedCount > 0
          ? SelectionActionOutcomeCode.partialFailure
          : SelectionActionOutcomeCode.success,
      changed: true,
      succeededCount: normalizedWorkIds.length,
      failedCount: failedCount,
    );
  }

  Future<SelectionActionOutcome> _runDownload(
    SelectionActionExecutionRequest request,
  ) async {
    final useCase = _bulkDownloadUseCaseResolver();
    if (useCase == null) {
      return const SelectionActionOutcome(
        code: SelectionActionOutcomeCode.unsupported,
      );
    }
    final normalizedWorkIds = _normalizedWorkIds(request.workIds);
    final result = await useCase.downloadComics(normalizedWorkIds);
    final invalidCount = request.workIds.length - normalizedWorkIds.length;
    final changed = result.enqueuedCount > 0 || result.deduplicatedCount > 0;
    final failedCode = invalidCount > 0
        ? SelectionActionOutcomeCode.partialFailure
        : changed
        ? SelectionActionOutcomeCode.success
        : SelectionActionOutcomeCode.noChange;
    return SelectionActionOutcome(
      code: failedCode,
      changed: changed,
      failedCount: invalidCount,
      enqueuedCount: result.enqueuedCount,
      deduplicatedCount: result.deduplicatedCount,
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
      workKinds[workId] = ThreadContentKind.comic;
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

  Future<Map<String, List<LibraryWorkItem>>> _loadMappedItemsByCategory(
    List<LibraryCategory> categories,
  ) async {
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      output[category.categoryId] = await Future.wait(items.map(_mapWork));
    }
    return output;
  }

  LibraryCategory _mapCategory(ComicShelfCategory source) {
    return LibraryCategory(
      categoryId: source.categoryId,
      name: source.name,
      sortOrder: source.sortOrder,
      createdAt: source.createdAt,
    );
  }

  Future<LibraryWorkItem> _mapWork(ComicShelfItem source) async {
    final statsRepository = _repository is ComicShelfStatsRepository
        ? _repository as ComicShelfStatsRepository
        : null;
    final stats = statsRepository == null
        ? null
        : await statsRepository.getShelfWorkStats(comicId: source.comicId);
    final unread =
        stats?.unreadCount ??
        await _stateRepository.countUnreadEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final read =
        stats?.readCount ??
        await _stateRepository.countReadEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final downloaded =
        stats?.downloadedCount ??
        await _stateRepository.countDownloadedEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final hasTags = await _stateRepository.hasAnyTag(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final useCustomMetadata = _featureFlags.readerCustomMetadataEnabled;
    final customSource = useCustomMetadata
        ? source.customCoverImageUrl?.trim()
        : null;
    final customLocal = useCustomMetadata
        ? source.customCoverLocalPath?.trim()
        : null;
    final hasPendingCustomCover =
        customSource != null &&
        customSource.isNotEmpty &&
        (customLocal == null || customLocal.isEmpty);
    return LibraryWorkItem(
      workId: source.comicId,
      categoryId: source.categoryId,
      title: useCustomMetadata
          ? source.title
          : (source.sourceTitle ?? source.title),
      secondaryName: _shelfSecondaryName(
        author: useCustomMetadata
            ? source.author
            : (source.sourceAuthor ?? source.author),
        translationGroup: useCustomMetadata
            ? source.translationGroup
            : (source.sourceTranslationGroup ?? source.translationGroup),
      ),
      coverImageUrl: useCustomMetadata
          ? source.coverImageUrl
          : _sourceCoverImageUrl(
              coverImageUrl: source.coverImageUrl,
              customCoverImageUrl: source.customCoverImageUrl,
            ),
      customCoverImageUrl: useCustomMetadata
          ? source.customCoverImageUrl
          : null,
      coverLocalPath: hasPendingCustomCover
          ? null
          : useCustomMetadata
          ? source.coverLocalPath
          : _sourceCoverLocalPath(
              coverLocalPath: source.coverLocalPath,
              customCoverLocalPath: source.customCoverLocalPath,
            ),
      customCoverLocalPath: useCustomMetadata
          ? source.customCoverLocalPath
          : null,
      customCoverFocusX: useCustomMetadata ? source.customCoverFocusX : null,
      customCoverFocusY: useCustomMetadata ? source.customCoverFocusY : null,
      unreadCount: unread,
      totalChapterCount: stats?.totalCount ?? unread + read,
      readChapterCount: read,
      addedAt: source.addedAt,
      hasTags: hasTags,
      isDownloaded: downloaded > 0,
    );
  }

  @override
  Future<List<ShelfCoverWarmupRequest>> buildCoverWarmupRequests({
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
    String? selectedCategoryId,
  }) async {
    final requests = <ShelfCoverWarmupRequest>[];
    final items = orderedShelfItemsForCoverWarmup(
      itemsByCategory: itemsByCategory,
      selectedCategoryId: selectedCategoryId,
    );
    for (final item in items) {
      final specRequest = _coverImageAdapter.buildCoverSpec(
        moduleKey: LibraryModuleKey.comic,
        item: item,
      );
      if (specRequest == null) {
        continue;
      }
      requests.add(
        ShelfCoverWarmupRequest(
          moduleKey: LibraryModuleKey.comic,
          workId: item.workId,
          cacheKey: specRequest.imageSpec.cacheKey!,
          sourceUrl: specRequest.imageSpec.sourceUrl,
          ownerType: specRequest.imageSpec.ownerType!,
          ownerId: specRequest.imageSpec.ownerId!,
          role: specRequest.useCustomCover
              ? ImageCacheRole.customCover
              : ImageCacheRole.cover,
          useCustomCover: specRequest.useCustomCover,
          imageSpec: specRequest.imageSpec,
        ),
      );
    }
    return requests;
  }

  @override
  Future<ShelfCoverWarmupResult?> warmCover(
    ShelfCoverWarmupRequest request,
  ) async {
    final cached = await _coverCacheService.ensureProtectedCover(
      cacheKey: request.cacheKey,
      sourceUrl: request.sourceUrl,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: request.ownerId,
      role: request.role,
    );
    final localPath = cached?.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    return applyWarmedCover(request: request, localPath: localPath);
  }

  @override
  Future<ShelfCoverWarmupResult?> applyWarmedCover({
    required ShelfCoverWarmupRequest request,
    required String localPath,
  }) async {
    if (_repository is ComicCoverCacheWriter) {
      await (_repository as ComicCoverCacheWriter).updateCoverCache(
        comicId: request.ownerId,
        coverImageUrl: request.useCustomCover ? null : request.sourceUrl,
        coverLocalPath: request.useCustomCover ? null : localPath,
        customCoverLocalPath: request.useCustomCover ? localPath : null,
      );
    }
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: request.useCustomCover ? null : localPath,
      customCoverLocalPath: request.useCustomCover ? localPath : null,
    );
  }

  Set<String> _normalizedWorkIds(Set<String> workIds) {
    return workIds
        .map((workId) => workId.trim())
        .where((workId) => workId.isNotEmpty)
        .toSet();
  }

  String? _sourceCoverImageUrl({
    required String? coverImageUrl,
    required String? customCoverImageUrl,
  }) {
    final custom = customCoverImageUrl?.trim();
    final cover = coverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _sourceCoverLocalPath({
    required String? coverLocalPath,
    required String? customCoverLocalPath,
  }) {
    final custom = customCoverLocalPath?.trim();
    final cover = coverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _shelfSecondaryName({
    required String? author,
    required String? translationGroup,
  }) {
    final normalizedAuthor = author?.trim();
    final normalizedGroup = translationGroup?.trim();
    final hasAuthor = normalizedAuthor != null && normalizedAuthor.isNotEmpty;
    final hasGroup = normalizedGroup != null && normalizedGroup.isNotEmpty;
    if (hasAuthor && hasGroup) {
      return '$normalizedAuthor / $normalizedGroup';
    }
    if (hasGroup) {
      return normalizedGroup;
    }
    return hasAuthor ? normalizedAuthor : null;
  }
}
