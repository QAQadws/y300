import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';

void main() {
  test(
    'older query cannot overwrite the latest filter and sort result',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final older = controller.updateFilters(const LibraryFilterSet());
      final newer = controller.updateChapterQuery(
        filters: const LibraryFilterSet(unread: TriStateFilterValue.include),
        sortOption: const LibraryChapterSortOption(
          direction: LibrarySortDirection.desc,
        ),
      );

      adapter.chapters[1].complete([_chapter('newer')]);
      await newer;
      adapter.chapters[0].complete([_chapter('older')]);
      await older;

      expect(controller.state.chapters.single.episodeId, 'newer');
      expect(controller.state.filters.unread, TriStateFilterValue.include);
      expect(
        controller.state.chapterSortOption.direction,
        LibrarySortDirection.desc,
      );
    },
  );

  test('older query error cannot replace a newer successful result', () async {
    final adapter = _ControlledAdapter();
    final controller = _controller(adapter);
    final older = controller.updateFilters(const LibraryFilterSet());
    final newer = controller.updateFilters(const LibraryFilterSet());
    adapter.chapters[1].complete([_chapter('newer')]);
    await newer;
    adapter.chapters[0].completeError(StateError('obsolete-query'));
    await older;

    expect(controller.state.errorMessage, isNull);
    expect(controller.state.chapters.single.episodeId, 'newer');
  });

  test(
    'new query supersedes full-load chapters without losing its header',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final initial = controller.initialize();
      adapter.headers.single.complete(_header('current-header'));
      await pumpEventQueue();
      final query = controller.updateFilters(const LibraryFilterSet());
      adapter.chapters[1].complete([_chapter('current-query')]);
      await query;
      adapter.chapters[0].complete([_chapter('obsolete-initial-query')]);
      await initial;

      expect(controller.state.header?.title, 'current-header');
      expect(controller.state.chapters.single.episodeId, 'current-query');
      expect(controller.state.isLoading, isFalse);
    },
  );

  test(
    'refresh callers share one remote operation and one local reload',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final first = controller.refresh();
      final second = controller.refresh();
      expect(adapter.refreshes, hasLength(1));
      adapter.refreshes.single.complete(DetailRefreshResult.immediate);
      await pumpEventQueue();
      adapter.headers.single.complete(_header('refreshed'));
      await pumpEventQueue();
      adapter.chapters.single.complete([_chapter('refreshed')]);
      await Future.wait([first, second]);
      expect(controller.state.isRefreshing, isFalse);
    },
  );

  test(
    'work reset waits for accepted chapter writes and rejects new ones',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final reading = controller.toggleChapterReadingState(
        episodeId: 'first',
        isCurrentlyRead: false,
      );
      final reset = controller.resetWorkReadingState();
      final blocked = controller.toggleChapterReadingState(
        episodeId: 'second',
        isCurrentlyRead: false,
      );
      expect(adapter.writes, ['read:first']);
      adapter.readWrite.complete();
      await pumpEventQueue();
      for (final request in adapter.chapters.where((r) => !r.isCompleted)) {
        request.complete([_chapter('before-reset')]);
      }
      await reading;
      await pumpEventQueue();
      expect(adapter.writes, ['read:first', 'reset']);
      adapter.resetWrite.complete();
      await pumpEventQueue();
      for (final request in adapter.chapters.where((r) => !r.isCompleted)) {
        request.complete([_chapter('after-reset')]);
      }
      await Future.wait([reset, blocked]);
      expect(controller.state.chapters.single.episodeId, 'after-reset');
    },
  );
  test(
    'query during header read keeps its result and avoids a redundant read',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final initial = controller.initialize();
      final query = controller.updateFilters(const LibraryFilterSet());
      adapter.chapters.single.complete([_chapter('query')]);
      await query;
      expect(controller.state.isLoading, isTrue);
      adapter.headers.single.complete(_header('header'));
      await initial;
      expect(adapter.chapters, hasLength(1));
      expect(controller.state.chapters.single.episodeId, 'query');
      expect(controller.state.header?.title, 'header');
      expect(controller.state.isLoading, isFalse);
    },
  );

  test('chapter success cannot hide a current header failure', () async {
    final adapter = _ControlledAdapter();
    final controller = _controller(adapter);
    final initial = controller.initialize();
    final query = controller.updateFilters(const LibraryFilterSet());
    adapter.headers.single.completeError(StateError('header-failure'));
    await initial;
    adapter.chapters.single.complete([_chapter('query')]);
    await query;
    expect(controller.state.header, isNull);
    expect(controller.state.errorMessage, contains('header-failure'));
    expect(controller.state.isLoading, isFalse);
  });

  test('header success cannot hide a current chapter failure', () async {
    final adapter = _ControlledAdapter();
    final controller = _controller(adapter);
    final initial = controller.initialize();
    final query = controller.updateFilters(const LibraryFilterSet());
    adapter.chapters.single.completeError(StateError('chapter-failure'));
    await query;
    adapter.headers.single.complete(_header('header'));
    await initial;
    expect(controller.state.header?.title, 'header');
    expect(controller.state.errorMessage, contains('chapter-failure'));
    expect(controller.state.isLoading, isFalse);
  });

  for (final olderFails in [false, true]) {
    test('superseded header is ignored (fails: $olderFails)', () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final older = controller.initialize();
      final newer = controller.reload();
      if (olderFails) {
        adapter.headers[0].completeError(StateError('obsolete-header'));
      } else {
        adapter.headers[0].complete(_header('obsolete-header'));
      }
      await older;
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.header, isNull);
      expect(controller.state.errorMessage, isNull);
      expect(adapter.chapters, isEmpty);
      adapter.headers[1].complete(_header('newer'));
      await pumpEventQueue();
      adapter.chapters.single.complete([_chapter('newer')]);
      await newer;
      expect(controller.state.header?.title, 'newer');
      expect(controller.state.isLoading, isFalse);
    });
  }

  for (final fails in [false, true]) {
    test(
      'close rejects late header and chapter results (fails: $fails)',
      () async {
        final adapter = _ControlledAdapter();
        final controller = _controller(adapter);
        final initial = controller.initialize();
        final query = controller.updateFilters(const LibraryFilterSet());
        controller.close();
        final closedState = controller.state;
        if (fails) {
          adapter.headers.single.completeError(StateError('late-header'));
          adapter.chapters.single.completeError(StateError('late-query'));
        } else {
          adapter.headers.single.complete(_header('late'));
          adapter.chapters.single.complete([_chapter('late')]);
        }
        await Future.wait([initial, query]);
        expect(controller.state, same(closedState));
        expect(controller.state.isLoading, isFalse);
      },
    );
  }

  test(
    'close skips mutation reload and retires a waiting work reset',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final reading = controller.toggleChapterReadingState(
        episodeId: 'first',
        isCurrentlyRead: false,
      );
      final reset = controller.resetWorkReadingState();
      controller.close();
      await reset;
      adapter.readWrite.complete();
      await reading;
      expect(adapter.writes, ['read:first']);
      expect(adapter.chapters, isEmpty);
      expect(controller.isResettingWorkReading, isFalse);
      expect(controller.isChapterReadingStateLocked('first'), isFalse);
    },
  );

  test(
    'reading locks are per chapter and duplicate submissions are ignored',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final first = controller.toggleChapterReadingState(
        episodeId: 'first',
        isCurrentlyRead: false,
      );
      final duplicate = controller.toggleChapterReadingState(
        episodeId: 'first',
        isCurrentlyRead: false,
      );
      final second = controller.toggleChapterReadingState(
        episodeId: 'second',
        isCurrentlyRead: false,
      );
      expect(adapter.writes, ['read:first', 'read:second']);
      expect(controller.isChapterReadingStateLocked('first'), isTrue);
      adapter.readWrite.complete();
      await pumpEventQueue();
      for (final request in adapter.chapters) {
        request.complete([_chapter('updated')]);
      }
      await Future.wait([first, duplicate, second]);
      expect(controller.isChapterReadingStateLocked('first'), isFalse);
      expect(controller.isChapterReadingStateLocked('second'), isFalse);
    },
  );

  test(
    'failed chapter write releases a reset barrier without poisoning it',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final reading = controller.toggleChapterReadingState(
        episodeId: 'first',
        isCurrentlyRead: false,
      );
      final failure = expectLater(reading, throwsStateError);
      final reset = controller.resetWorkReadingState();
      final duplicateReset = controller.resetWorkReadingState();
      adapter.readWrite.completeError(StateError('write-failed'));
      await failure;
      await pumpEventQueue();
      expect(adapter.writes, ['read:first', 'reset']);
      expect(controller.isChapterReadingStateLocked('other'), isTrue);
      adapter.resetWrite.completeError(StateError('reset-failed'));
      await expectLater(reset, throwsStateError);
      await duplicateReset;
      expect(controller.isResettingWorkReading, isFalse);
      expect(controller.isChapterReadingStateLocked('other'), isFalse);
    },
  );

  test(
    'download and deletion share a chapter lock, unrelated chapters proceed',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final download = controller.markChapterDownloaded(
        episodeId: 'first',
        isDownloaded: true,
      );
      final duplicate = controller.deleteChapterDownload(episodeId: 'first');
      final other = controller.deleteChapterDownload(episodeId: 'second');
      expect(adapter.writes, ['download:first', 'delete:second']);
      expect(controller.isChapterDownloadPending('first'), isTrue);
      adapter.downloadWrite.complete();
      await pumpEventQueue();
      for (final request in adapter.chapters) {
        request.complete([_chapter('updated')]);
      }
      await Future.wait([download, duplicate, other]);
      expect(controller.isChapterDownloadPending('first'), isFalse);
    },
  );

  test(
    'failed shared refresh releases its slot for a later explicit retry',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final first = controller.refresh();
      final joined = controller.refreshFully();
      expect(joined, same(first));
      final failures = Future.wait([
        expectLater(first, throwsStateError),
        expectLater(joined, throwsStateError),
      ]);
      adapter.refreshes.single.completeError(StateError('refresh-failed'));
      await failures;
      expect(controller.state.isRefreshing, isFalse);
      final retry = controller.refreshFully();
      expect(adapter.fullRefreshCalls, 1);
      adapter.refreshes.last.complete(DetailRefreshResult.skipped);
      await retry;
      expect(controller.state.lastRefreshResult, DetailRefreshResult.skipped);
    },
  );

  test('closed owner cannot start reads, writes or refreshes', () async {
    final adapter = _ControlledAdapter();
    final controller = _controller(adapter)..close();
    await controller.initialize();
    await controller.reload();
    await controller.updateFilters(const LibraryFilterSet());
    await controller.toggleChapterReadingState(
      episodeId: 'a',
      isCurrentlyRead: false,
    );
    await controller.markChapterBookmarked(episodeId: 'a', isBookmarked: true);
    await controller.markChapterDownloaded(episodeId: 'a', isDownloaded: true);
    await controller.deleteChapterDownload(episodeId: 'a');
    await controller.resetWorkReadingState();
    expect(await controller.refresh(), DetailRefreshResult.skipped);
    expect(await controller.refreshFully(), DetailRefreshResult.skipped);
    expect(adapter.headers, isEmpty);
    expect(adapter.chapters, isEmpty);
    expect(adapter.writes, isEmpty);
    expect(adapter.refreshes, isEmpty);
  });

  test(
    'late refresh completion after close cannot reload or publish',
    () async {
      final adapter = _ControlledAdapter();
      final controller = _controller(adapter);
      final refresh = controller.refresh();
      controller.close();
      final closedState = controller.state;
      adapter.refreshes.single.complete(DetailRefreshResult.immediate);
      await refresh;
      expect(controller.state, same(closedState));
      expect(adapter.headers, isEmpty);
    },
  );
}

UnifiedDetailController _controller(_ControlledAdapter adapter) =>
    UnifiedDetailController(adapter: adapter, workId: 'work');

LibraryDetailHeader _header(String title) =>
    LibraryDetailHeader(workId: 'work', title: title, inShelf: true);

LibraryChapterItem _chapter(String id) => LibraryChapterItem(
  episodeId: id,
  workId: 'work',
  title: id,
  orderIndex: 0,
  isRead: false,
  isDownloaded: false,
  isBookmarked: false,
);

class _ControlledAdapter
    implements
        DetailModuleAdapter,
        DetailChapterReadStateAdapter,
        DetailWorkReadingResetAdapter,
        DetailChapterDownloadAdapter,
        DetailFullRefreshAdapter {
  final headers = <Completer<LibraryDetailHeader>>[];
  final chapters = <Completer<List<LibraryChapterItem>>>[];
  final refreshes = <Completer<DetailRefreshResult>>[];
  final readWrite = Completer<void>();
  final resetWrite = Completer<void>();
  final downloadWrite = Completer<void>();
  int fullRefreshCalls = 0;
  final writes = <String>[];

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) {
    final request = Completer<LibraryDetailHeader>();
    headers.add(request);
    return request.future;
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) {
    final request = Completer<List<LibraryChapterItem>>();
    chapters.add(request);
    return request.future;
  }

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) {
    final request = Completer<DetailRefreshResult>();
    refreshes.add(request);
    return request.future;
  }

  @override
  Future<DetailRefreshResult> refreshWorkFully({required String workId}) {
    fullRefreshCalls++;
    return refreshWork(workId: workId);
  }

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) {
    writes.add('download:$episodeId');
    return downloadWrite.future;
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) {
    writes.add('delete:$episodeId');
    return downloadWrite.future;
  }

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) {
    writes.add('read:$episodeId');
    return readWrite.future;
  }

  @override
  Future<void> resetWorkReadingState({required String workId}) {
    writes.add('reset');
    return resetWrite.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
