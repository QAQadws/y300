import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';

void main() {
  test('initialize loads header and chapters', () async {
    final controller = UnifiedDetailController(
      adapter: _FakeDetailAdapter(),
      workId: 'work-1',
    );

    await controller.initialize();

    expect(controller.state.header?.title, '测试作品');
    expect(controller.state.chapters.length, 2);
    expect(controller.state.isLoading, isFalse);
  });

  test('toggleSortDirection switches chapter order direction', () async {
    final adapter = _FakeDetailAdapter();
    final controller = UnifiedDetailController(
      adapter: adapter,
      workId: 'work-1',
    );

    await controller.initialize();
    final before = controller.state.chapterSortOption.direction;
    await controller.toggleSortDirection();
    final after = controller.state.chapterSortOption.direction;

    expect(before == after, isFalse);
  });

  test('reload reads local state without refreshing source chapters', () async {
    final adapter = _FakeDetailAdapter();
    final controller = UnifiedDetailController(
      adapter: adapter,
      workId: 'work-1',
    );

    await controller.initialize();
    await controller.reload();

    expect(adapter.loadHeaderCount, 2);
    expect(adapter.refreshWorkCount, 0);
  });

  test(
    'refresh stores queued result without reloading local chapters',
    () async {
      final adapter = _FakeDetailAdapter()
        ..refreshResult = DetailRefreshResult.queued(
          estimatedDuration: const Duration(milliseconds: 10500),
          queuePosition: 1,
        );
      final controller = UnifiedDetailController(
        adapter: adapter,
        workId: 'work-1',
      );

      await controller.initialize();
      final beforeLoadCount = adapter.loadHeaderCount;
      final result = await controller.refresh();

      expect(result.status, DetailRefreshStatus.queued);
      expect(controller.state.lastRefreshResult?.message, '更新预计耗时10.5s');
      expect(adapter.refreshWorkCount, 1);
      expect(adapter.loadHeaderCount, beforeLoadCount);
      expect(controller.state.isRefreshing, isFalse);
    },
  );

  test('updateFilters and chapter actions update state', () async {
    final adapter = _FakeDetailAdapter();
    final controller = UnifiedDetailController(
      adapter: adapter,
      workId: 'work-1',
    );

    await controller.initialize();

    await controller.updateFilters(
      const LibraryFilterSet(unread: TriStateFilterValue.include),
    );
    expect(controller.state.chapters.length, 2);

    await controller.markChapterRead(episodeId: 'e1', isRead: true);
    await controller.updateFilters(
      const LibraryFilterSet(unread: TriStateFilterValue.include),
    );
    expect(controller.state.chapters.length, 1);

    await controller.markChapterBookmarked(episodeId: 'e2', isBookmarked: true);
    await controller.updateFilters(
      const LibraryFilterSet(bookmarked: TriStateFilterValue.include),
    );
    expect(controller.state.chapters.map((e) => e.episodeId), ['e2']);

    await controller.markChapterDownloaded(episodeId: 'e2', isDownloaded: true);
    await controller.updateFilters(
      const LibraryFilterSet(downloaded: TriStateFilterValue.include),
    );
    expect(controller.state.chapters.map((e) => e.episodeId), ['e2']);

    await controller.clearAllReadState();
    await controller.updateFilters(
      const LibraryFilterSet(unread: TriStateFilterValue.include),
    );
    expect(controller.state.chapters.length, 2);

    await controller.deleteChapterDownload(episodeId: 'e2');
    await controller.updateFilters(
      const LibraryFilterSet(downloaded: TriStateFilterValue.include),
    );
    expect(controller.state.chapters, isEmpty);
  });
}

class _FakeDetailAdapter implements DetailModuleAdapter {
  int loadHeaderCount = 0;
  int refreshWorkCount = 0;
  DetailRefreshResult refreshResult = DetailRefreshResult.immediate;

  final Map<String, bool> _read = <String, bool>{'e1': false, 'e2': false};
  final Map<String, bool> _downloaded = <String, bool>{
    'e1': false,
    'e2': false,
  };
  final Map<String, bool> _bookmarked = <String, bool>{
    'e1': false,
    'e2': false,
  };

  @override
  Future<void> clearAllReadState({required String workId}) async {
    _read.updateAll((key, value) => false);
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {
    _downloaded[episodeId] = false;
  }

  @override
  Future<void> downloadAll({required String workId}) async {
    _downloaded.updateAll((key, value) => true);
  }

  @override
  Future<void> downloadUnread({required String workId}) async {
    _downloaded.forEach((episodeId, value) {
      if (!(_read[episodeId] ?? false)) {
        _downloaded[episodeId] = true;
      }
    });
  }

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    return ReaderRouteTarget(workId: workId, episodeId: 'e1');
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  }) async {
    return const ThreadRouteTarget(tid: '100');
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    final base = [
      LibraryChapterItem(
        episodeId: 'e1',
        workId: workId,
        title: '第1章',
        orderIndex: 1,
        isRead: _read['e1'] ?? false,
        isDownloaded: _downloaded['e1'] ?? false,
        isBookmarked: _bookmarked['e1'] ?? false,
      ),
      LibraryChapterItem(
        episodeId: 'e2',
        workId: workId,
        title: '第2章',
        orderIndex: 2,
        isRead: _read['e2'] ?? false,
        isDownloaded: _downloaded['e2'] ?? false,
        isBookmarked: _bookmarked['e2'] ?? false,
      ),
    ];

    return base
        .where((chapter) {
          if (!_match(filters.downloaded, chapter.isDownloaded)) {
            return false;
          }
          if (!_match(filters.unread, !chapter.isRead)) {
            return false;
          }
          if (!_match(filters.bookmarked, chapter.isBookmarked)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool _match(TriStateFilterValue value, bool actual) {
    return switch (value) {
      TriStateFilterValue.ignore => true,
      TriStateFilterValue.include => actual,
      TriStateFilterValue.exclude => !actual,
    };
  }

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    loadHeaderCount++;
    return const LibraryDetailHeader(
      workId: 'work-1',
      title: '测试作品',
      inShelf: true,
    );
  }

  @override
  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    _bookmarked[episodeId] = isBookmarked;
  }

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {
    _downloaded[episodeId] = isDownloaded;
  }

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) async {
    _read[episodeId] = isRead;
  }

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    refreshWorkCount++;
    return refreshResult;
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return const [];
  }
}
