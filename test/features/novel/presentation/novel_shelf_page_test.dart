import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_view_preferences_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/presentation/novel_shelf_page.dart';

void main() {
  testWidgets('NovelShelfPage builds unified shelf shell with module title', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryViewPreferencesRepositoryProvider.overrideWithValue(
            VolatileLibraryViewPreferencesRepository(),
          ),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
        ],
        child: const MaterialApp(home: NovelShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('小说'), findsOneWidget);
    expect(
      find.byKey(const Key('unified-shelf-category-indicator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('unified-shelf-category-tab-default')),
      findsOneWidget,
    );
  });

  testWidgets('NovelShelfPage long press omits read-state selection actions', (
    tester,
  ) async {
    final selectionHost = ShelfSelectionHostController();
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryViewPreferencesRepositoryProvider.overrideWithValue(
            VolatileLibraryViewPreferencesRepository(),
          ),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
        ],
        child: const MaterialApp(home: NovelShelfPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-list-item-novel-1')),
    );
    await tester.pumpAndSettle();

    expect(selectionHost.state?.selectionActions.length, 2);
  });

  testWidgets('NovelShelfPage exposes bookmark filter without read status', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryViewPreferencesRepositoryProvider.overrideWithValue(
            VolatileLibraryViewPreferencesRepository(),
          ),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
        ],
        child: const MaterialApp(home: NovelShelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();

    expect(find.text('已下载'), findsNothing);
    expect(find.text('未读'), findsNothing);
    expect(find.text('阅读过'), findsNothing);
    expect(find.text('有书签'), findsOneWidget);
    expect(find.text('已添加标签'), findsNothing);

    await tester.tap(find.byType(TextButton).at(1));
    await tester.pumpAndSettle();
    expect(find.text('未读章节数'), findsNothing);
    expect(find.text('章节数'), findsOneWidget);
    expect(find.text('收藏日期'), findsOneWidget);
  });
}

class _FakeNovelRepository implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return [
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return const [];
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async => null;

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return [
      NovelItem(
        novelId: 'novel-1',
        sourceTid: '100',
        sourceFid: '49',
        title: '小说A',
        author: '作者A',
        coverImageUrl: null,
        updatedAt: DateTime(2026, 1, 1),
        episodeCount: 2,
        categoryId: categoryId,
      ),
    ];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {}

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return const <NovelReaderBookmark>[];
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {}

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

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
    return 1;
  }

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

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
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getTags() async => const [];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const [];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {}

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}
}
