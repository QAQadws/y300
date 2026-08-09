import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_shelf_controller.dart';

void main() {
  group('UnifiedShelfController', () {
    test('initialize should load categories and items', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'title',
              unreadCount: 1,
              totalChapterCount: 3,
              readChapterCount: 2,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.categories.length, 1);
      expect(controller.state.itemsByCategory['default']?.length, 1);
    });

    test(
      'public shelf uses shared default and normalizes unsupported sort',
      () async {
        final adapter = _FakeShelfAdapter(
          categories: const <LibraryCategory>[],
          queriedItems: const <String, List<LibraryWorkItem>>{},
        );
        final controller = UnifiedShelfController(adapter: adapter);
        addTearDown(controller.dispose);

        expect(
          controller.state.sortOption.field,
          LibraryShelfSortField.favoriteAddedAt,
        );
        expect(
          controller.state.sortOption.direction,
          LibrarySortDirection.desc,
        );

        await controller.updateSortOption(
          const LibraryShelfSortOption(
            field: LibraryShelfSortField.name,
            direction: LibrarySortDirection.desc,
          ),
        );

        expect(
          controller.state.sortOption.field,
          LibraryShelfSortField.favoriteAddedAt,
        );
        expect(
          controller.state.sortOption.direction,
          LibrarySortDirection.desc,
        );

        await controller.updateFilters(
          const LibraryFilterSet(hasTags: TriStateFilterValue.include),
        );

        expect(controller.state.filters.hasTags, TriStateFilterValue.ignore);
      },
    );

    test('module capabilities can override the default shelf sort', () async {
      final adapter = _CapabilityShelfAdapter(
        categories: const <LibraryCategory>[],
        queriedItems: const <String, List<LibraryWorkItem>>{},
        capabilities: const ShelfModuleCapabilities(
          defaultSortOption: LibraryShelfSortOption(
            field: LibraryShelfSortField.favoriteAddedAt,
            direction: LibrarySortDirection.asc,
          ),
        ),
      );
      final controller = UnifiedShelfController(adapter: adapter);
      addTearDown(controller.dispose);

      expect(
        controller.state.sortOption.field,
        LibraryShelfSortField.favoriteAddedAt,
      );
      expect(controller.state.sortOption.direction, LibrarySortDirection.asc);

      await controller.updateSortOption(
        const LibraryShelfSortOption(
          field: LibraryShelfSortField.name,
          direction: LibrarySortDirection.desc,
        ),
      );

      expect(controller.state.sortOption.direction, LibrarySortDirection.asc);
    });

    test(
      'initialize restores the full view snapshot and normalizes capabilities',
      () async {
        final adapter = _CapabilityShelfAdapter(
          categories: <LibraryCategory>[
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
            LibraryCategory(
              categoryId: 'saved',
              name: 'saved',
              sortOrder: 1,
              createdAt: DateTime(2026, 1, 2),
            ),
          ],
          queriedItems: const <String, List<LibraryWorkItem>>{
            'default': <LibraryWorkItem>[],
            'saved': <LibraryWorkItem>[],
          },
          capabilities: const ShelfModuleCapabilities(
            supportsReadState: false,
            defaultSortOption: LibraryShelfSortOption(
              field: LibraryShelfSortField.favoriteAddedAt,
              direction: LibrarySortDirection.asc,
            ),
          ),
        );
        final preferencesRepository =
            VolatileLibraryViewPreferencesRepository();
        await preferencesRepository.save(
          const LibraryShelfViewPreferences(
            moduleKey: LibraryModuleKey.comic,
            displayMode: LibraryDisplayMode.list,
            gridColumnCount: 5,
            sortOption: LibraryShelfSortOption(
              field: LibraryShelfSortField.unreadCount,
            ),
            filters: LibraryFilterSet(
              downloaded: TriStateFilterValue.include,
              unread: TriStateFilterValue.include,
              bookmarked: TriStateFilterValue.include,
            ),
            lastCategoryId: 'saved',
          ),
        );
        final controller = UnifiedShelfController(
          adapter: adapter,
          viewPreferencesRepository: preferencesRepository,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.state.displayMode, LibraryDisplayMode.list);
        expect(controller.state.gridColumnCount, 5);
        expect(controller.state.selectedCategoryId, 'saved');
        expect(
          controller.state.sortOption,
          isA<LibraryShelfSortOption>()
              .having(
                (option) => option.field,
                'field',
                LibraryShelfSortField.favoriteAddedAt,
              )
              .having(
                (option) => option.direction,
                'direction',
                LibrarySortDirection.asc,
              ),
        );
        expect(controller.state.filters.unread, TriStateFilterValue.ignore);
        expect(controller.state.filters.downloaded, TriStateFilterValue.ignore);
        expect(controller.state.filters.bookmarked, TriStateFilterValue.ignore);
      },
    );

    test('selecting a category persists it for the next controller', () async {
      final adapter = _FakeShelfAdapter(
        categories: <LibraryCategory>[
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          LibraryCategory(
            categoryId: 'later',
            name: 'later',
            sortOrder: 1,
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
        queriedItems: const <String, List<LibraryWorkItem>>{
          'default': <LibraryWorkItem>[],
          'later': <LibraryWorkItem>[],
        },
      );
      final preferencesRepository = VolatileLibraryViewPreferencesRepository();
      final first = UnifiedShelfController(
        adapter: adapter,
        viewPreferencesRepository: preferencesRepository,
      );
      addTearDown(first.dispose);
      await first.initialize();
      await first.selectCategory('later');

      final second = UnifiedShelfController(
        adapter: adapter,
        viewPreferencesRepository: preferencesRepository,
      );
      addTearDown(second.dispose);
      await second.initialize();

      expect(second.state.selectedCategoryId, 'later');
    });

    test(
      'initialize prefers snapshot adapter without loading categories separately',
      () async {
        final adapter = _SnapshotShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'default',
                title: 'snapshot title',
                unreadCount: 2,
                totalChapterCount: 3,
                readChapterCount: 1,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
        );
        final controller = UnifiedShelfController(adapter: adapter);

        await controller.initialize();

        expect(controller.state.isLoading, isFalse);
        expect(
          controller.state.itemsByCategory['default']?.single.title,
          'snapshot title',
        );
        expect(adapter.snapshotCallCount, 1);
        expect(adapter.loadCategoriesCallCount, 0);
        expect(adapter.queryCallCount, 0);
      },
    );

    test('feature flag can disable snapshot query fallback path', () async {
      final adapter = _SnapshotShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'fallback title',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 0,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(
        adapter: adapter,
        featureFlags: ShelfFeatureFlags.defaults.copyWith(
          useShelfSnapshotQuery: false,
        ),
      );

      await controller.initialize();

      expect(adapter.snapshotCallCount, 0);
      expect(adapter.loadCategoriesCallCount, 1);
      expect(adapter.queryCallCount, 1);
    });

    test(
      'hide default category when default is empty and others have items',
      () async {
        final adapter = _FakeShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
            LibraryCategory(
              categoryId: 'c1',
              name: 'follow',
              sortOrder: 1,
              createdAt: DateTime(2026, 1, 2),
            ),
          ],
          queriedItems: {
            'default': [],
            'c1': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'c1',
                title: 'title',
                unreadCount: 0,
                totalChapterCount: 1,
                readChapterCount: 1,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
        );
        final controller = UnifiedShelfController(adapter: adapter);
        await controller.initialize();

        expect(
          controller.state.categories.any((e) => e.categoryId == 'default'),
          isFalse,
        );
        expect(
          controller.state.categories.any((e) => e.categoryId == 'c1'),
          isTrue,
        );
      },
    );

    test('keep default visible when it has items', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          LibraryCategory(
            categoryId: 'c1',
            name: 'follow',
            sortOrder: 1,
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w0',
              categoryId: 'default',
              title: 'uncategorized',
              unreadCount: 1,
              totalChapterCount: 1,
              readChapterCount: 0,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          'c1': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'c1',
              title: 'title',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();

      expect(
        controller.state.categories.any((e) => e.categoryId == 'default'),
        isTrue,
      );
    });

    test('search keyword should reload and update match count map', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'abc',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      await controller.updateKeyword('ab');

      expect(controller.state.keyword, 'ab');
      expect(controller.state.visibleMatchCountByCategory['default'], 1);
      expect(adapter.lastQueryKeyword, 'ab');
    });

    test('keyword debounce should coalesce fast consecutive input', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'abc',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      adapter.queryCallCount = 0;

      final f1 = controller.updateKeyword('a');
      final f2 = controller.updateKeyword('ab');
      final f3 = controller.updateKeyword('abc');
      await Future.wait([f1, f2, f3]);

      expect(controller.state.keyword, 'abc');
      expect(adapter.lastQueryKeyword, 'abc');
      expect(adapter.queryCallCount, 1);
      controller.dispose();
    });

    test('exit search cancels pending debounce and reloads once', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: const <String, List<LibraryWorkItem>>{
          'default': <LibraryWorkItem>[],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      adapter.queryCallCount = 0;

      final pendingKeyword = controller.updateKeyword('pending');
      await controller.exitSearchMode();
      await controller.exitSearchMode();
      await pendingKeyword;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(controller.state.isSearchMode, isFalse);
      expect(controller.state.keyword, isEmpty);
      expect(adapter.lastQueryKeyword, isEmpty);
      expect(adapter.queryCallCount, 1);
      controller.dispose();
    });

    test(
      'update display and grid columns persists through shared repository',
      () async {
        final adapter = _FakeShelfAdapter(
          categories: const [],
          queriedItems: const {},
        );
        final preferencesRepository =
            VolatileLibraryViewPreferencesRepository();
        final controller = UnifiedShelfController(
          adapter: adapter,
          viewPreferencesRepository: preferencesRepository,
        );
        await controller.initialize();
        await controller.updateDisplayMode(LibraryDisplayMode.list);
        await controller.updateGridColumnCount(2);

        final saved = await preferencesRepository.load(
          defaults: LibraryShelfViewPreferences.defaults(
            moduleKey: LibraryModuleKey.comic,
            displayMode: LibraryDisplayMode.grid,
            sortOption: LibraryShelfSortOption.defaults,
          ),
        );
        expect(saved.displayMode, LibraryDisplayMode.list);
        expect(saved.gridColumnCount, 2);
      },
    );

    test(
      'initialize shows metadata before cover warmup finishes and applies warmed cover later',
      () async {
        final adapter = _WarmupShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'default',
                title: 'title',
                coverImageUrl: 'https://img.test/w1.jpg',
                unreadCount: 0,
                totalChapterCount: 1,
                readChapterCount: 0,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
        );
        final patched = Completer<void>();
        var stateChangeCount = 0;
        final controller = UnifiedShelfController(
          adapter: adapter,
          coverPrefetchConcurrency: 1,
          onStateChanged: () {
            stateChangeCount++;
          },
        );
        controller.stateListenable.addListener(() {
          final coverLocalPath = controller
              .stateListenable
              .value
              .itemsByCategory['default']
              ?.single
              .coverLocalPath;
          if (coverLocalPath == '/cache/w1.jpg' && !patched.isCompleted) {
            patched.complete();
          }
        });

        await controller.initialize();

        expect(controller.state.isLoading, isFalse);
        expect(
          controller.state.itemsByCategory['default']?.single.coverLocalPath,
          isNull,
        );
        await adapter.warmCoverStarted;
        expect(adapter.warmCoverCallCount, 1);

        adapter.completeWarmup('/cache/w1.jpg');
        await patched.future;

        expect(
          controller.state.itemsByCategory['default']?.single.coverLocalPath,
          '/cache/w1.jpg',
        );
        expect(stateChangeCount, 0);
        controller.dispose();
      },
    );

    test(
      'stateListenable emits incremental cover patch without metadata reload',
      () async {
        final adapter = _WarmupShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'default',
                title: 'title',
                coverImageUrl: 'https://img.test/w1.jpg',
                unreadCount: 0,
                totalChapterCount: 1,
                readChapterCount: 0,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
        );
        final controller = UnifiedShelfController(
          adapter: adapter,
          coverPrefetchConcurrency: 1,
        );
        final emitted = <UnifiedShelfState>[];
        final patched = Completer<void>();
        controller.stateListenable.addListener(() {
          final state = controller.stateListenable.value;
          emitted.add(state);
          final coverLocalPath =
              state.itemsByCategory['default']?.single.coverLocalPath;
          if (coverLocalPath == '/cache/w1.jpg' && !patched.isCompleted) {
            patched.complete();
          }
        });

        await controller.initialize();
        adapter.queryCallCount = 0;
        adapter.completeWarmup('/cache/w1.jpg');
        await patched.future;

        expect(
          emitted.last.itemsByCategory['default']?.single.coverLocalPath,
          '/cache/w1.jpg',
        );
        expect(adapter.queryCallCount, 0);
        controller.dispose();
      },
    );

    test(
      'cover warmup uses ForumImagePrecacheService before adapter write-back',
      () async {
        final adapter = _WarmupShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'default',
                title: 'title',
                coverImageUrl: 'https://img.test/w1.jpg',
                unreadCount: 0,
                totalChapterCount: 1,
                readChapterCount: 0,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
        );
        final precache = _RecordingForumImagePrecacheService(
          localPath: '/cache/w1.jpg',
        );
        final controller = UnifiedShelfController(
          adapter: adapter,
          coverPrefetchConcurrency: 1,
          coverPrecacheServiceResolver: () => precache,
        );
        final patched = Completer<void>();
        controller.stateListenable.addListener(() {
          final coverLocalPath = controller
              .stateListenable
              .value
              .itemsByCategory['default']
              ?.single
              .coverLocalPath;
          if (coverLocalPath == '/cache/w1.jpg' && !patched.isCompleted) {
            patched.complete();
          }
        });

        await controller.initialize();
        await patched.future;

        expect(precache.diskSpecs.single.kind, ForumImageKind.cover);
        expect(precache.diskSpecs.single.ownerId, 'w1');
        expect(adapter.warmCoverCallCount, 0);
        expect(adapter.applyWarmedCoverCallCount, 1);
        expect(
          controller.state.itemsByCategory['default']?.single.coverLocalPath,
          '/cache/w1.jpg',
        );
        controller.dispose();
      },
    );

    test(
      'reported visible range upgrades cover warmup priority before background items',
      () async {
        final adapter = _PriorityWarmupShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [_workItem('w0'), _workItem('w1'), _workItem('w2')],
          },
        );
        final controller = UnifiedShelfController(
          adapter: adapter,
          coverPrefetchConcurrency: 1,
        );

        controller.reportVisibleRange(
          categoryId: 'default',
          firstIndex: 1,
          lastIndex: 1,
        );
        await controller.initialize();
        await adapter.waitForWarmupCalls(3);

        expect(adapter.warmedWorkIds.first, 'w1');
        controller.dispose();
      },
    );

    test('feature flag can disable background cover warmup queue', () async {
      final adapter = _PriorityWarmupShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [_workItem('w0')],
        },
      );
      final controller = UnifiedShelfController(
        adapter: adapter,
        coverPrefetchConcurrency: 1,
        featureFlags: ShelfFeatureFlags.defaults.copyWith(
          useShelfCoverQueue: false,
        ),
      );

      await controller.initialize();

      expect(adapter.warmedWorkIds, isEmpty);
      controller.dispose();
    });

    test(
      'disabling stale-while-revalidate makes refresh enter loading state with old content',
      () async {
        final adapter = _BlockingReloadShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        );
        final controller = UnifiedShelfController(
          adapter: adapter,
          featureFlags: ShelfFeatureFlags.defaults.copyWith(
            useStaleWhileRevalidate: false,
          ),
        );

        await controller.initialize();
        final refreshFuture = controller.refresh();
        await adapter.secondQueryStarted.future;

        expect(controller.state.isLoading, isTrue);
        expect(
          controller.state.itemsByCategory['default']?.single.workId,
          'w1',
        );

        adapter.completeSecondQuery();
        await refreshFuture;
        controller.dispose();
      },
    );

    test(
      'default stale-while-revalidate keeps old content visible during refresh',
      () async {
        final adapter = _BlockingReloadShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        );
        final controller = UnifiedShelfController(adapter: adapter);

        await controller.initialize();
        final refreshFuture = controller.refresh();
        await adapter.secondQueryStarted.future;

        expect(controller.state.isLoading, isFalse);
        expect(
          controller.state.itemsByCategory['default']?.single.workId,
          'w1',
        );

        adapter.completeSecondQuery();
        await refreshFuture;
        controller.dispose();
      },
    );

    test(
      'completed background task reloads metadata and notifies listener',
      () async {
        final progress = ValueNotifier<LibraryShelfTaskProgress?>(null);
        final adapter = _FakeShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [
              LibraryWorkItem(
                workId: 'w1',
                categoryId: 'default',
                title: 'before sync',
                unreadCount: 0,
                totalChapterCount: 1,
                readChapterCount: 0,
                addedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          },
          taskProgress: progress,
        );
        final stateChanged = Completer<void>();
        final controller = UnifiedShelfController(
          adapter: adapter,
          onStateChanged: () {
            if (!stateChanged.isCompleted) {
              stateChanged.complete();
            }
          },
        );

        await controller.initialize();
        adapter.queriedItems = {
          'default': [
            LibraryWorkItem(
              workId: 'w2',
              categoryId: 'default',
              title: 'after sync',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 0,
              addedAt: DateTime.utc(2026, 1, 2),
            ),
          ],
        };

        progress.value = const LibraryShelfTaskProgress(
          code: LibraryShelfTaskProgressCode.favoriteSyncFetching,
          subject: 'syncing',
        );
        progress.value = null;
        await stateChanged.future;

        expect(
          controller.state.itemsByCategory['default']?.single.workId,
          'w2',
        );
        controller.dispose();
        progress.dispose();
      },
    );

    test('shelf refresh signal reloads matching module only', () async {
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [_workItem('w1')],
        },
        shelfRefreshSignals: bus.signal,
      );
      final stateChanged = Completer<void>();
      final controller = UnifiedShelfController(
        adapter: adapter,
        onStateChanged: () {
          if (!stateChanged.isCompleted) {
            stateChanged.complete();
          }
        },
      );

      await controller.initialize();
      adapter.queriedItems = {
        'default': [_workItem('w2')],
      };

      bus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        reason: 'other_module',
        source: LibraryMutationSource.favoriteSync,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.itemsByCategory['default']?.single.workId, 'w1');

      bus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        reason: 'comic_updated',
        source: LibraryMutationSource.comicRefresh,
      );
      await stateChanged.future;

      expect(controller.state.itemsByCategory['default']?.single.workId, 'w2');
      controller.dispose();
    });

    test(
      'background task with reloadOnCompletion false does not trigger reload',
      () async {
        final progress = ValueNotifier<LibraryShelfTaskProgress?>(null);
        final adapter = _FakeShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [_workItem('w1')],
          },
          taskProgress: progress,
        );
        final controller = UnifiedShelfController(adapter: adapter);

        await controller.initialize();
        adapter.queryCallCount = 0;
        progress.value = const LibraryShelfTaskProgress(
          code: LibraryShelfTaskProgressCode.coverWarmup,
          subject: 'warming',
          source: LibraryMutationSource.coverWarmup,
          reloadOnCompletion: false,
        );
        progress.value = null;
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(adapter.queryCallCount, 0);
        controller.dispose();
        progress.dispose();
      },
    );

    test(
      'hidden cover warmup progress is registered through task progress hub',
      () async {
        final adapter = _WarmupShelfAdapter(
          categories: [
            LibraryCategory(
              categoryId: 'default',
              name: 'default',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          queriedItems: {
            'default': [_workItem('w1')],
          },
        );
        final hub = DefaultLibraryTaskProgressHub();
        addTearDown(hub.dispose);
        final controller = UnifiedShelfController(
          adapter: adapter,
          coverPrefetchConcurrency: 1,
          taskProgressHub: hub,
        );

        await controller.initialize();
        await adapter.warmCoverStarted;

        final progress = hub.progressFor(LibraryModuleKey.comic).value;
        expect(progress?.source, LibraryMutationSource.coverWarmup);
        expect(progress?.visible, isFalse);
        expect(progress?.reloadOnCompletion, isFalse);

        adapter.completeWarmup('/cache/w1.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        controller.dispose();
      },
    );
  });
}

class _CapabilityShelfAdapter extends _FakeShelfAdapter
    implements ShelfModuleCapabilitiesAdapter {
  _CapabilityShelfAdapter({
    required super.categories,
    required super.queriedItems,
    required this.capabilities,
  });

  @override
  final ShelfModuleCapabilities capabilities;
}

class _FakeShelfAdapter implements ShelfModuleAdapter {
  _FakeShelfAdapter({
    required this.categories,
    required this.queriedItems,
    this.taskProgress,
    this.shelfRefreshSignals,
  });

  final List<LibraryCategory> categories;
  Map<String, List<LibraryWorkItem>> queriedItems;
  @override
  final ValueListenable<LibraryShelfTaskProgress?>? taskProgress;
  @override
  final ValueListenable<LibraryShelfRefreshSignal?>? shelfRefreshSignals;

  String? lastQueryKeyword;
  int queryCallCount = 0;

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.grid;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async =>
      workId;

  @override
  Future<String> createCategory({required String name}) async => 'new';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async => categories;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async => queriedItems[categoryId] ?? const <LibraryWorkItem>[];

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    queryCallCount += 1;
    lastQueryKeyword = keyword;
    return queriedItems;
  }

  @override
  Future<void> refreshShelf() async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async => queriedItems;
}

class _WarmupShelfAdapter extends _FakeShelfAdapter
    implements ShelfCoverWarmupAdapter {
  _WarmupShelfAdapter({required super.categories, required super.queriedItems});

  final Completer<String> _warmupCompleter = Completer<String>();
  final Completer<void> _warmCoverStarted = Completer<void>();
  int warmCoverCallCount = 0;
  int applyWarmedCoverCallCount = 0;

  Future<void> get warmCoverStarted => _warmCoverStarted.future;

  @override
  Future<List<ShelfCoverWarmupRequest>> buildCoverWarmupRequests({
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
    String? selectedCategoryId,
  }) async {
    final item = itemsByCategory['default']!.single;
    return <ShelfCoverWarmupRequest>[
      ShelfCoverWarmupRequest(
        moduleKey: LibraryModuleKey.comic,
        workId: item.workId,
        cacheKey: 'cover/comic/${item.workId}',
        sourceUrl: item.coverImageUrl!,
        ownerType: ImageCacheOwnerType.comic,
        ownerId: item.workId,
        role: ImageCacheRole.cover,
        useCustomCover: false,
        imageSpec: _coverSpec(item),
      ),
    ];
  }

  @override
  Future<ShelfCoverWarmupResult?> warmCover(
    ShelfCoverWarmupRequest request,
  ) async {
    warmCoverCallCount++;
    if (!_warmCoverStarted.isCompleted) {
      _warmCoverStarted.complete();
    }
    final localPath = await _warmupCompleter.future;
    return applyWarmedCover(request: request, localPath: localPath);
  }

  @override
  Future<ShelfCoverWarmupResult?> applyWarmedCover({
    required ShelfCoverWarmupRequest request,
    required String localPath,
  }) async {
    applyWarmedCoverCallCount++;
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: localPath,
    );
  }

  void completeWarmup(String localPath) {
    _warmupCompleter.complete(localPath);
  }
}

class _PriorityWarmupShelfAdapter extends _FakeShelfAdapter
    implements ShelfCoverWarmupAdapter {
  _PriorityWarmupShelfAdapter({
    required super.categories,
    required super.queriedItems,
  });

  final warmedWorkIds = <String>[];
  final Completer<void> _callsCompleter = Completer<void>();

  Future<void> waitForWarmupCalls(int count) async {
    if (warmedWorkIds.length >= count) {
      return;
    }
    await _callsCompleter.future;
  }

  @override
  Future<List<ShelfCoverWarmupRequest>> buildCoverWarmupRequests({
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
    String? selectedCategoryId,
  }) async {
    final items = itemsByCategory['default'] ?? const <LibraryWorkItem>[];
    return items
        .map((item) {
          return ShelfCoverWarmupRequest(
            moduleKey: LibraryModuleKey.comic,
            workId: item.workId,
            cacheKey: 'cover/comic/${item.workId}',
            sourceUrl: item.coverImageUrl!,
            ownerType: ImageCacheOwnerType.comic,
            ownerId: item.workId,
            role: ImageCacheRole.cover,
            useCustomCover: false,
            imageSpec: _coverSpec(item),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<ShelfCoverWarmupResult?> warmCover(
    ShelfCoverWarmupRequest request,
  ) async {
    warmedWorkIds.add(request.workId);
    if (warmedWorkIds.length >= 3 && !_callsCompleter.isCompleted) {
      _callsCompleter.complete();
    }
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: '/cache/${request.workId}.jpg',
    );
  }

  @override
  Future<ShelfCoverWarmupResult?> applyWarmedCover({
    required ShelfCoverWarmupRequest request,
    required String localPath,
  }) async {
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: localPath,
    );
  }
}

class _BlockingReloadShelfAdapter extends _FakeShelfAdapter {
  _BlockingReloadShelfAdapter({required super.categories})
    : super(
        queriedItems: {
          'default': [_workItem('w1')],
        },
      );

  final Completer<void> secondQueryStarted = Completer<void>();
  final Completer<void> _allowSecondQuery = Completer<void>();
  var _calls = 0;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    _calls += 1;
    if (_calls >= 2) {
      if (!secondQueryStarted.isCompleted) {
        secondQueryStarted.complete();
      }
      await _allowSecondQuery.future;
    }
    return super.queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
  }

  void completeSecondQuery() {
    if (!_allowSecondQuery.isCompleted) {
      _allowSecondQuery.complete();
    }
  }
}

ForumImageLoadSpec _coverSpec(LibraryWorkItem item) {
  return ForumImageLoadSpec(
    kind: ForumImageKind.cover,
    url: Uri.parse(item.coverImageUrl!),
    ownerType: ImageCacheOwnerType.comic,
    ownerId: item.workId,
    cacheKey: 'cover/comic/${item.workId}',
    allowReaderOpen: false,
  );
}

class _RecordingForumImagePrecacheService implements ForumImagePrecacheService {
  _RecordingForumImagePrecacheService({required this.localPath});

  final String localPath;
  final diskSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    diskSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      cacheKey: spec.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    return const ForumImagePrecacheResult(success: false);
  }
}

class _SnapshotShelfAdapter extends _FakeShelfAdapter
    implements ShelfSnapshotAdapter {
  _SnapshotShelfAdapter({
    required super.categories,
    required super.queriedItems,
  });

  int snapshotCallCount = 0;
  int loadCategoriesCallCount = 0;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    loadCategoriesCallCount++;
    return super.loadCategories();
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    snapshotCallCount++;
    lastQueryKeyword = keyword;
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: queriedItems,
      visibleMatchCountByCategory: <String, int>{
        for (final category in categories)
          category.categoryId:
              (queriedItems[category.categoryId] ?? const <LibraryWorkItem>[])
                  .length,
      },
    );
  }
}

LibraryWorkItem _workItem(String workId) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: 'default',
    title: workId,
    coverImageUrl: 'https://img.test/$workId.jpg',
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime.utc(2026, 1, 1),
  );
}
