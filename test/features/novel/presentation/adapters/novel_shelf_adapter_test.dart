import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_shelf_adapter.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('NovelShelfAdapter returns metadata before cover warmup', () async {
    final repository = _FakeNovelRepository(
      shelfItems: <NovelItem>[
        NovelItem(
          novelId: 'novel-1',
          sourceTid: '100',
          sourceFid: '49',
          title: 'Novel A',
          author: 'Author A',
          coverImageUrl: 'https://img.test/novel-1.jpg',
          updatedAt: DateTime(2026, 1, 1),
          episodeCount: 2,
        ),
      ],
    );
    final cache = _FakeImageCacheService(localPath: '/cache/novel-1.jpg');
    final adapter = NovelShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: cache,
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, isNull);
    expect(cache.lastRequest, isNull);

    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: 'default',
      itemsByCategory: <String, List<LibraryWorkItem>>{'default': items},
    );
    final result = await adapter.warmCover(requests.single);

    expect(result?.coverLocalPath, '/cache/novel-1.jpg');
    expect(cache.lastRequest?.cacheKey, 'cover/novel/novel-1');
    expect(repository.lastCoverLocalPath, '/cache/novel-1.jpg');
  });

  test('NovelShelfAdapter exposes novel progress from task progress hub', () {
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: 'Novel refresh active',
        source: LibraryMutationSource.novelRefresh,
      ),
    );
    final registration = hub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.novel},
      progress: progress,
    );
    addTearDown(progress.dispose);
    addTearDown(registration.dispose);
    addTearDown(hub.dispose);
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      taskProgressHub: hub,
    );

    expect(adapter.taskProgress?.value?.message, 'Novel refresh active');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.novelRefresh,
    );
  });

  test('NovelShelfAdapter exposes selection actions in fixed order', () {
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: _FakeShelfCategoryAssignUseCase(),
      readingStateBatchWriter: _FakeReadingStateBatchWriter(),
      unfavoriteWorkUseCase: _FakeUnfavoriteWorkUseCase(),
    );

    expect(
      adapter.selectionActions.map((action) => action.id).toList(),
      <String>[
        SelectionActionIds.assignCategory,
        SelectionActionIds.markAllRead,
        SelectionActionIds.markAllUnread,
        SelectionActionIds.unfavorite,
      ],
    );
  });

  test('NovelShelfAdapter forwards category and reading-state actions', () async {
    final assignUseCase = _FakeShelfCategoryAssignUseCase();
    final writer = _FakeReadingStateBatchWriter();
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: assignUseCase,
      readingStateBatchWriter: writer,
    );

    await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.assignCategory,
        workIds: <String>{'novel-a'},
        activeCategoryId: 'default',
        targetCategoryId: 'archive',
      ),
    );
    await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.markAllUnread,
        workIds: <String>{'novel-a'},
        activeCategoryId: 'default',
      ),
    );

    expect(assignUseCase.lastSourceCategoryId, 'default');
    expect(assignUseCase.lastTargetCategoryId, 'archive');
    expect(writer.calls.single.module, LibraryModuleKey.novel);
    expect(writer.calls.single.isRead, isFalse);
  });

  test('NovelShelfAdapter delegates unfavorite with novel kind', () async {
    final useCase = _FakeUnfavoriteWorkUseCase();
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      unfavoriteWorkUseCase: useCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.unfavorite,
        workIds: <String>{'novel-a', 'novel-b'},
        activeCategoryId: 'default',
      ),
    );

    expect(
      useCase.lastWorkKinds,
      <String, ThreadContentKind>{
        'novel-a': ThreadContentKind.novel,
        'novel-b': ThreadContentKind.novel,
      },
    );
    expect(result.changed, isTrue);
  });
}

class _FakeNovelRepository implements NovelRepository, NovelCoverCacheWriter {
  _FakeNovelRepository({required this.shelfItems});

  final List<NovelItem> shelfItems;
  String? lastCoverLocalPath;

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: 'Default',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return shelfItems;
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> updateCoverCache({
    required String novelId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverLocalPath = coverLocalPath ?? customCoverLocalPath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    lastRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShelfCategoryAssignUseCase implements ShelfCategoryAssignUseCase {
  String? lastSourceCategoryId;
  String? lastTargetCategoryId;

  @override
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    lastSourceCategoryId = sourceCategoryId;
    lastTargetCategoryId = targetCategoryId;
    return ShelfCategoryAssignResult(
      assignedWorkIds: workIds.toList(growable: false),
      failedWorkIds: const <String>[],
      targetCategoryId: targetCategoryId,
    );
  }
}

class _ReadStateCall {
  const _ReadStateCall({
    required this.module,
    required this.workIds,
    required this.isRead,
  });

  final LibraryModuleKey module;
  final Set<String> workIds;
  final bool isRead;
}

class _FakeReadingStateBatchWriter implements ReadingStateBatchWriter {
  final List<_ReadStateCall> calls = <_ReadStateCall>[];

  @override
  Future<void> setWorkRead({
    required LibraryModuleKey module,
    required String workId,
    required bool isRead,
  }) async {}

  @override
  Future<void> setWorksRead({
    required LibraryModuleKey module,
    required Set<String> workIds,
    required bool isRead,
  }) async {
    calls.add(
      _ReadStateCall(module: module, workIds: workIds, isRead: isRead),
    );
  }
}

class _FakeUnfavoriteWorkUseCase implements UnfavoriteWorkUseCase {
  Map<String, ThreadContentKind>? lastWorkKinds;

  @override
  Future<UnfavoriteResult> call({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    return UnfavoriteResult(
      requestedTids: const <String>['200'],
      succeededTids: const <String>['200'],
      failedTids: const <String>[],
      purgedWorkIds: const <String>[],
    );
  }

  @override
  Future<UnfavoriteResult> callMany({
    required Map<String, ThreadContentKind> workKinds,
  }) async {
    lastWorkKinds = workKinds;
    return UnfavoriteResult(
      requestedTids: const <String>['200'],
      succeededTids: const <String>['200'],
      failedTids: const <String>[],
      purgedWorkIds: const <String>[],
    );
  }
}
