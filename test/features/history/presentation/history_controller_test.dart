import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

import '../test_support/history_test_support.dart';

void main() {
  test('loads first page and appends a stable keyset next page', () async {
    final repository = MemoryHistoryRepository(
      List<HistoryEntry>.generate(
        5,
        (index) => historyEntry(
          type: HistoryTargetType.thread,
          id: '${index + 1}',
          title: '帖子 ${index + 1}',
          visitedAt: DateTime.utc(2026, 7, 16, 12, index),
        ),
      ),
    );
    final controller = buildHistoryController(repository, pageSize: 2);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await controller.initialize();

    expect(controller.state.items.map((entry) => entry.target.id), ['5', '4']);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();

    expect(controller.state.items.map((entry) => entry.target.id), [
      '5',
      '4',
      '3',
      '2',
    ]);
    expect(controller.state.hasMore, isTrue);
  });

  test('debounces search and refreshes the active query on changes', () async {
    final repository = MemoryHistoryRepository(<HistoryEntry>[
      historyEntry(
        type: HistoryTargetType.comic,
        id: 'comic:1',
        title: 'Alpha 漫画',
        visitedAt: DateTime.utc(2026, 7, 16, 12),
      ),
      historyEntry(
        type: HistoryTargetType.novel,
        id: 'novel:1',
        title: 'Beta 小说',
        visitedAt: DateTime.utc(2026, 7, 16, 11),
      ),
    ]);
    final controller = buildHistoryController(
      repository,
      searchDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);
    await controller.initialize();
    final initialQueryCount = repository.queryCount;

    controller.updateSearchText('Al');
    controller.updateSearchText('Alpha');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repository.queryCount, initialQueryCount);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.queryCount, initialQueryCount + 1);
    expect(controller.state.items.single.title, 'Alpha 漫画');

    controller.updateSearchText('');
    await controller.clearSearch();
    expect(controller.state.items, hasLength(2));

    controller.updateSearchText('Alpha');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    await repository.recordVisit(
      historyEntry(
        type: HistoryTargetType.thread,
        id: '100',
        title: 'Alpha 帖子',
        visitedAt: DateTime.utc(2026, 7, 16, 13),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.items.map((entry) => entry.title), [
      'Alpha 帖子',
      'Alpha 漫画',
    ]);
  });

  test('keeps loaded items when the next page fails', () async {
    final repository = MemoryHistoryRepository(
      List<HistoryEntry>.generate(
        3,
        (index) => historyEntry(
          type: HistoryTargetType.thread,
          id: '${index + 1}',
          title: '帖子 ${index + 1}',
          visitedAt: DateTime.utc(2026, 7, 16, 12, index),
        ),
      ),
    )..failCursorQuery = true;
    final controller = buildHistoryController(repository, pageSize: 2);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);
    await controller.initialize();

    await controller.loadMore();

    expect(controller.state.items, hasLength(2));
    expect(controller.state.loadMoreError, contains('query failed'));
    expect(controller.state.isLoadingMore, isFalse);
  });

  test('rolls back optimistic delete and clear when mutations fail', () async {
    final entry = historyEntry(
      type: HistoryTargetType.novel,
      id: 'novel:1',
      title: '小说',
      visitedAt: DateTime.utc(2026, 7, 16, 12),
    );
    final repository = MemoryHistoryRepository(<HistoryEntry>[entry]);
    final controller = buildHistoryController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);
    await controller.initialize();

    repository.failDelete = true;
    await expectLater(controller.deleteEntry(entry), throwsStateError);
    expect(controller.state.items, <HistoryEntry>[entry]);

    repository.failClear = true;
    await expectLater(controller.clearAll(), throwsStateError);
    expect(controller.state.items, <HistoryEntry>[entry]);
  });
}
