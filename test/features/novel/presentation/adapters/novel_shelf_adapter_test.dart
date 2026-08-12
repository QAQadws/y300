import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_shelf_adapter.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('NovelShelfAdapter maps a stable source cover asset', () async {
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
    final stateRepository = _FakeLibraryStateRepository(hasBookmarks: true);
    final adapter = NovelShelfAdapter(
      repository,
      stateRepository: stateRepository,
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, isNull);
    expect(items.single.unreadCount, 0);
    expect(items.single.readChapterCount, 0);
    expect(items.single.hasBookmarks, isTrue);
    expect(stateRepository.countUnreadCalls, 0);
    expect(stateRepository.countReadCalls, 0);
    expect(items.single.coverAsset?.assetId, 'novel/novel-1/source');
    expect(items.single.coverAsset?.kind, LibraryCoverAssetKind.source);
    expect(
      items.single.coverAsset?.sourceUrl,
      'https://img.test/novel-1.jpg',
    );
    expect(repository.lastCoverLocalPath, isNull);
  });

  test(
    'NovelShelfAdapter suppresses hidden source and custom covers',
    () async {
      final adapter = NovelShelfAdapter(
        _FakeNovelRepository(
          shelfItems: <NovelItem>[
            NovelItem(
              novelId: 'novel-hidden',
              sourceTid: '101',
              sourceFid: '49',
              title: 'Hidden cover novel',
              coverImageUrl: 'https://img.test/source.jpg',
              customCoverLocalPath: '/cache/custom.jpg',
              coverHidden: true,
              updatedAt: DateTime(2026, 1, 1),
              episodeCount: 1,
            ),
          ],
        ),
        stateRepository: _FakeLibraryStateRepository(),
      );

      final items = await adapter.loadCategoryItems(categoryId: 'default');

      expect(items.single.coverImageUrl, isNull);
      expect(items.single.coverLocalPath, isNull);
      expect(items.single.customCoverLocalPath, isNull);
    },
  );

  test('NovelShelfAdapter exposes novel progress from task progress hub', () {
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        code: LibraryShelfTaskProgressCode.coverWarmup,
        subject: 'Novel cover warmup',
        source: LibraryMutationSource.coverWarmup,
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

    expect(adapter.taskProgress?.value?.subject, 'Novel cover warmup');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.coverWarmup,
    );
  });

  test('NovelShelfAdapter exposes selection actions in fixed order', () {
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: _FakeShelfCategoryAssignUseCase(),
      unfavoriteWorkUseCase: _FakeUnfavoriteWorkUseCase(),
    );

    expect(
      adapter.selectionActions.map((action) => action.id).toList(),
      <String>[
        SelectionActionIds.assignCategory,
        SelectionActionIds.unfavorite,
      ],
    );
  });

  test(
    'NovelShelfAdapter disables read status and enables bookmark filter',
    () {
      final adapter = NovelShelfAdapter(
        _FakeNovelRepository(shelfItems: const <NovelItem>[]),
        stateRepository: _FakeLibraryStateRepository(),
      );

      expect(adapter.capabilities.supportsReadState, isFalse);
      expect(adapter.capabilities.supportsBookmarkFilter, isTrue);
      expect(
        adapter.capabilities.defaultSortOption.field,
        LibraryShelfSortField.favoriteAddedAt,
      );
      expect(
        adapter.capabilities.defaultSortOption.direction,
        LibrarySortDirection.desc,
      );
      expect(adapter.capabilities.availableSortFields, <LibraryShelfSortField>[
        LibraryShelfSortField.chapterCount,
        LibraryShelfSortField.favoriteAddedAt,
      ]);
    },
  );

  test('NovelShelfAdapter forwards category actions', () async {
    final assignUseCase = _FakeShelfCategoryAssignUseCase();
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: assignUseCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.assignCategory,
        workIds: <String>{'novel-a'},
        activeCategoryId: 'default',
        targetCategoryId: 'archive',
      ),
    );
    expect(assignUseCase.lastSourceCategoryId, 'default');
    expect(assignUseCase.lastTargetCategoryId, 'archive');
    expect(result.code, SelectionActionOutcomeCode.success);
    expect(result.succeededCount, 1);
    expect(result.failedCount, 0);
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

    expect(useCase.lastWorkKinds, <String, ThreadContentKind>{
      'novel-a': ThreadContentKind.novel,
      'novel-b': ThreadContentKind.novel,
    });
    expect(result.changed, isTrue);
    expect(result.code, SelectionActionOutcomeCode.success);
    expect(result.succeededCount, 1);
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

class _FakeLibraryStateRepository
    implements LibraryStateRepository, LibraryBookmarkStateQuery {
  _FakeLibraryStateRepository({this.hasBookmarks = false});

  final bool hasBookmarks;
  int countReadCalls = 0;
  int countUnreadCalls = 0;

  @override
  Future<bool> hasAnyBookmarkedEpisode({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => hasBookmarks;

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
    countReadCalls++;
    return 0;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    countUnreadCalls++;
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
