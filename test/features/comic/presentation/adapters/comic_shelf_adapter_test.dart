import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('ComicShelfAdapter defaults to newest favorite first', () {
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
    );

    expect(
      adapter.capabilities.defaultSortOption.field,
      LibraryShelfSortField.favoriteAddedAt,
    );
    expect(
      adapter.capabilities.defaultSortOption.direction,
      LibrarySortDirection.desc,
    );
  });

  test('ComicShelfAdapter maps a stable source cover asset', () async {
    final repository = _FakeComicRepository(
      shelfItems: <ComicShelfItem>[
        ComicShelfItem(
          comicId: 'comic-1',
          title: 'Comic A',
          author: 'Author A',
          coverImageUrl: 'https://img.test/comic-1.jpg',
          categoryId: 'default',
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, isNull);
    expect(items.single.coverAsset?.assetId, 'comic/comic-1/source');
    expect(items.single.coverAsset?.kind, LibraryCoverAssetKind.source);
    expect(items.single.coverAsset?.sourceUrl, 'https://img.test/comic-1.jpg');
    expect(repository.lastCoverLocalPath, isNull);
  });

  test(
    'ComicShelfAdapter does not expose old ordinary local cover while custom cover is pending',
    () async {
      final adapter = ComicShelfAdapter(
        _FakeComicRepository(
          shelfItems: <ComicShelfItem>[
            ComicShelfItem(
              comicId: 'comic-2',
              title: 'Comic B',
              author: 'Author B',
              coverImageUrl: 'https://img.test/ordinary.jpg',
              customCoverImageUrl: 'https://img.test/custom.jpg',
              coverLocalPath: '/cache/old-ordinary.jpg',
              categoryId: 'default',
              addedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
        stateRepository: _FakeLibraryStateRepository(),
      );

      final items = await adapter.loadCategoryItems(categoryId: 'default');

      expect(items.single.coverLocalPath, isNull);
      expect(items.single.customCoverLocalPath, isNull);
      expect(items.single.coverAsset?.assetId, 'comic/comic-2/custom');
      expect(items.single.coverAsset?.kind, LibraryCoverAssetKind.custom);
    },
  );

  test(
    'custom metadata flag hides custom cover from shelf item mapping',
    () async {
      final adapter = ComicShelfAdapter(
        _FakeComicRepository(
          shelfItems: <ComicShelfItem>[
            ComicShelfItem(
              comicId: 'comic-2',
              title: 'Custom Title',
              sourceTitle: 'Source Title',
              author: 'Custom Author',
              sourceAuthor: 'Source Author',
              translationGroup: 'Custom Group',
              sourceTranslationGroup: 'Source Group',
              coverImageUrl: 'https://img.test/ordinary.jpg',
              customCoverImageUrl: 'https://img.test/custom.jpg',
              coverLocalPath: '/cache/old-ordinary.jpg',
              customCoverLocalPath: '/cache/custom.jpg',
              categoryId: 'default',
              addedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
        stateRepository: _FakeLibraryStateRepository(),
        featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
          readerCustomMetadataEnabled: false,
        ),
      );

      final items = await adapter.loadCategoryItems(categoryId: 'default');

      expect(items.single.coverLocalPath, '/cache/old-ordinary.jpg');
      expect(items.single.title, 'Source Title');
      expect(items.single.secondaryName, 'Source Author / Source Group');
      expect(items.single.customCoverImageUrl, isNull);
      expect(items.single.customCoverLocalPath, isNull);
    },
  );

  test('custom metadata flag bypasses composed snapshot fields', () async {
    final repository = _FakeSnapshotComicRepository(
      shelfItems: <ComicShelfItem>[
        ComicShelfItem(
          comicId: 'comic-4',
          title: 'Custom Title',
          sourceTitle: 'Source Title',
          author: 'Custom Author',
          sourceAuthor: 'Source Author',
          translationGroup: 'Custom Group',
          sourceTranslationGroup: 'Source Group',
          coverImageUrl: 'https://img.test/custom.jpg',
          customCoverImageUrl: 'https://img.test/custom.jpg',
          coverLocalPath: '/cache/custom.jpg',
          customCoverLocalPath: '/cache/custom.jpg',
          categoryId: 'default',
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
        readerCustomMetadataEnabled: false,
      ),
    );

    final snapshot = await adapter.querySnapshot(
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: '',
    );
    final item = snapshot.itemsByCategory['default']!.single;

    expect(repository.snapshotQueryCount, 0);
    expect(snapshot.visibleMatchCountByCategory['default'], 1);
    expect(item.title, 'Source Title');
    expect(item.secondaryName, 'Source Author / Source Group');
    expect(item.coverImageUrl, isNull);
    expect(item.coverLocalPath, isNull);
    expect(item.customCoverImageUrl, isNull);
    expect(item.customCoverLocalPath, isNull);
  });

  test(
    'ComicShelfAdapter fallback uses repository stats for missing state rows',
    () async {
      final adapter = ComicShelfAdapter(
        _FakeComicRepository(
          shelfItems: <ComicShelfItem>[
            ComicShelfItem(
              comicId: 'comic-3',
              title: 'Comic C',
              author: 'Author C',
              coverImageUrl: null,
              categoryId: 'default',
              addedAt: DateTime(2026, 1, 1),
            ),
          ],
          statsByComicId: const <String, ComicShelfWorkStats>{
            'comic-3': ComicShelfWorkStats(
              totalCount: 3,
              unreadCount: 2,
              readCount: 1,
              downloadedCount: 1,
            ),
          },
        ),
        stateRepository: _FakeLibraryStateRepository(),
      );

      final items = await adapter.loadCategoryItems(categoryId: 'default');

      expect(items.single.totalChapterCount, 3);
      expect(items.single.unreadCount, 2);
      expect(items.single.readChapterCount, 1);
      expect(items.single.isDownloaded, isTrue);
    },
  );

  test('ComicShelfAdapter exposes merge duplicates module action', () async {
    final repository = _FakeDuplicateComicRepository(
      mergeResult: const ComicDuplicateMergeResult(
        targetComicId: 'comic-a',
        targetTitle: 'Short Title',
        mergedComicIds: <String>{'comic-b'},
        replacements: <String, String>{'comic-b': 'comic-a'},
        movedEpisodeCount: 2,
      ),
    );
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      duplicateMergeService: ComicDuplicateMergeService(repository: repository),
      shelfRefreshBus: bus,
    );

    final result = await adapter.runMenuAction(
      LibraryShelfMenuAction.mergeDuplicates,
    );

    expect(adapter.menuActions.single, LibraryShelfMenuAction.mergeDuplicates);
    expect(result.code, ShelfModuleActionOutcomeCode.success);
    expect(result.changed, isTrue);
    expect(result.affectedCount, 1);
    expect(repository.mergeAllCallCount, 1);
    expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
    expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
    expect(bus.signal.value?.source, LibraryMutationSource.duplicateMerge);
    expect(bus.signal.value?.payload['removedComicCount'], 1);
  });

  test('ComicShelfAdapter exposes comic progress from task progress hub', () {
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        code: LibraryShelfTaskProgressCode.comicSearchWaiting,
        subject: 'Comic queue active',
        source: LibraryMutationSource.comicSearchQueue,
      ),
    );
    final registration = hub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
      progress: progress,
    );
    addTearDown(progress.dispose);
    addTearDown(registration.dispose);
    addTearDown(hub.dispose);
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      taskProgressHub: hub,
    );

    expect(adapter.taskProgress?.value?.subject, 'Comic queue active');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.comicSearchQueue,
    );
  });

  test('ComicShelfAdapter exposes selection actions in fixed order', () {
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: _FakeShelfCategoryAssignUseCase(),
      readingStateBatchWriter: _FakeReadingStateBatchWriter(),
      bulkDownloadUseCase: _FakeBulkDownloadUseCase(),
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

  test(
    'ComicShelfAdapter forwards assign-category source and target',
    () async {
      final useCase = _FakeShelfCategoryAssignUseCase();
      final adapter = ComicShelfAdapter(
        _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
        stateRepository: _FakeLibraryStateRepository(),
        categoryAssignUseCase: useCase,
      );

      final result = await adapter.runSelectionAction(
        const SelectionActionExecutionRequest(
          actionId: SelectionActionIds.assignCategory,
          workIds: <String>{'comic-a', 'comic-b'},
          activeCategoryId: 'default',
          targetCategoryId: 'romance',
        ),
      );

      expect(useCase.lastWorkIds, <String>{'comic-a', 'comic-b'});
      expect(useCase.lastSourceCategoryId, 'default');
      expect(useCase.lastTargetCategoryId, 'romance');
      expect(result.changed, isTrue);
      expect(result.code, SelectionActionOutcomeCode.success);
      expect(result.succeededCount, 2);
      expect(result.failedCount, 0);
    },
  );

  test(
    'ComicShelfAdapter delegates mark-all-read and mark-all-unread',
    () async {
      final writer = _FakeReadingStateBatchWriter();
      final adapter = ComicShelfAdapter(
        _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
        stateRepository: _FakeLibraryStateRepository(),
        readingStateBatchWriter: writer,
      );

      final readResult = await adapter.runSelectionAction(
        const SelectionActionExecutionRequest(
          actionId: SelectionActionIds.markAllRead,
          workIds: <String>{'comic-a'},
          activeCategoryId: 'default',
        ),
      );
      final unreadResult = await adapter.runSelectionAction(
        const SelectionActionExecutionRequest(
          actionId: SelectionActionIds.markAllUnread,
          workIds: <String>{'comic-b'},
          activeCategoryId: 'default',
        ),
      );

      expect(writer.calls.length, 2);
      expect(writer.calls.first.module, LibraryModuleKey.comic);
      expect(writer.calls.first.workIds, <String>{'comic-a'});
      expect(writer.calls.first.isRead, isTrue);
      expect(writer.calls.last.workIds, <String>{'comic-b'});
      expect(writer.calls.last.isRead, isFalse);
      expect(readResult.code, SelectionActionOutcomeCode.success);
      expect(readResult.succeededCount, 1);
      expect(unreadResult.code, SelectionActionOutcomeCode.success);
      expect(unreadResult.succeededCount, 1);
    },
  );

  test('ComicShelfAdapter delegates download to bulk use case', () async {
    final useCase = _FakeBulkDownloadUseCase();
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      bulkDownloadUseCase: useCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.download,
        workIds: <String>{'comic-a', 'comic-b'},
        activeCategoryId: 'default',
      ),
    );

    expect(useCase.lastComicIds, <String>{'comic-a', 'comic-b'});
    expect(result.changed, isTrue);
    expect(result.code, SelectionActionOutcomeCode.success);
    expect(result.enqueuedCount, 3);
    expect(result.deduplicatedCount, 0);
  });

  test('ComicShelfAdapter delegates unfavorite with comic kind', () async {
    final useCase = _FakeUnfavoriteWorkUseCase();
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      unfavoriteWorkUseCase: useCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.unfavorite,
        workIds: <String>{'comic-a', 'comic-b'},
        activeCategoryId: 'default',
      ),
    );

    expect(useCase.lastWorkKinds, <String, ThreadContentKind>{
      'comic-a': ThreadContentKind.comic,
      'comic-b': ThreadContentKind.comic,
    });
    expect(result.changed, isTrue);
    expect(result.code, SelectionActionOutcomeCode.success);
    expect(result.succeededCount, 1);
  });
}

class _FakeSnapshotComicRepository extends _FakeComicRepository
    implements ComicShelfSnapshotRepository {
  _FakeSnapshotComicRepository({required super.shelfItems});

  int snapshotQueryCount = 0;

  @override
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    snapshotQueryCount++;
    return LibraryShelfSnapshot(
      categories: (await getCategories())
          .map((category) {
            return LibraryCategory(
              categoryId: category.categoryId,
              name: category.name,
              sortOrder: category.sortOrder,
              createdAt: category.createdAt,
            );
          })
          .toList(growable: false),
      itemsByCategory: <String, List<LibraryWorkItem>>{
        'default': <LibraryWorkItem>[
          LibraryWorkItem(
            workId: 'snapshot-work',
            categoryId: 'default',
            title: 'Snapshot Custom',
            customCoverImageUrl: 'https://img.test/snapshot-custom.jpg',
            customCoverLocalPath: '/cache/snapshot-custom.jpg',
            unreadCount: 0,
            totalChapterCount: 0,
            readChapterCount: 0,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      },
      visibleMatchCountByCategory: const <String, int>{'default': 1},
    );
  }
}

class _FakeComicRepository
    implements
        ComicRepository,
        ComicShelfStatsRepository,
        ComicCoverCacheWriter {
  _FakeComicRepository({
    required this.shelfItems,
    this.statsByComicId = const <String, ComicShelfWorkStats>{},
  });

  final List<ComicShelfItem> shelfItems;
  final Map<String, ComicShelfWorkStats> statsByComicId;
  String? lastCoverLocalPath;

  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: 'Default',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  }) async {
    return shelfItems;
  }

  @override
  Future<ComicShelfWorkStats> getShelfWorkStats({
    required String comicId,
  }) async {
    return statsByComicId[comicId] ??
        const ComicShelfWorkStats(
          totalCount: 0,
          unreadCount: 0,
          readCount: 0,
          downloadedCount: 0,
        );
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverLocalPath = coverLocalPath ?? customCoverLocalPath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDuplicateComicRepository extends _FakeComicRepository
    implements ComicDuplicateMergeRepository {
  _FakeDuplicateComicRepository({required this.mergeResult})
    : super(shelfItems: const <ComicShelfItem>[]);

  final ComicDuplicateMergeResult mergeResult;
  int mergeAllCallCount = 0;

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({
    String? comicId,
  }) async {
    if (mergeAllCallCount > 0) {
      return const <ComicDuplicateGroup>[];
    }
    return <ComicDuplicateGroup>[
      ComicDuplicateGroup(
        comicIds: <String>{
          mergeResult.targetComicId,
          ...mergeResult.mergedComicIds,
        },
        sharedTids: const <String>{'100'},
      ),
    ];
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    mergeAllCallCount++;
    return mergeResult;
  }
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
  Set<String>? lastWorkIds;
  String? lastSourceCategoryId;
  String? lastTargetCategoryId;

  @override
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    lastWorkIds = workIds;
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
    calls.add(_ReadStateCall(module: module, workIds: workIds, isRead: isRead));
  }
}

class _FakeBulkDownloadUseCase implements BulkDownloadUseCase {
  Set<String>? lastComicIds;

  @override
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds) async {
    lastComicIds = comicIds;
    return BulkDownloadResult(
      requestedCount: 3,
      enqueuedCount: 3,
      deduplicatedCount: 0,
      skippedDownloadedCount: 0,
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
      requestedTids: const <String>['100'],
      succeededTids: const <String>['100'],
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
      requestedTids: const <String>['100'],
      succeededTids: const <String>['100'],
      failedTids: const <String>[],
      purgedWorkIds: const <String>[],
    );
  }
}
