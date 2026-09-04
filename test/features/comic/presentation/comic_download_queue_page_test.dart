import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';
import 'package:y300/features/comic/presentation/comic_download_queue_page.dart';

void main() {
  testWidgets('renders active, pending, and failed queue entries', (
    tester,
  ) async {
    final snapshot = ValueNotifier<ComicDownloadQueueSnapshot>(
      ComicDownloadQueueSnapshot(
        entries: <ComicDownloadQueueEntry>[
          _entry(
            id: 1,
            episodeTitle: '第 1 话',
            status: ComicDownloadQueueStatus.running,
            completed: 2,
            total: 30,
          ),
          _entry(
            id: 2,
            episodeTitle: '第 2 话',
            status: ComicDownloadQueueStatus.pending,
          ),
          _entry(
            id: 3,
            episodeTitle: '第 3 话',
            status: ComicDownloadQueueStatus.failed,
            lastError: '网络失败',
          ),
        ],
      ),
    );
    addTearDown(snapshot.dispose);
    final queue = _RecordingQueue(snapshot);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicDownloadQueueProvider.overrideWithValue(queue),
          comicDownloadQueueSnapshotProvider.overrideWithValue(snapshot),
        ],
        child: const LocalizedTestApp(home: ComicDownloadQueuePage()),
      ),
    );

    expect(find.text('正在缓存'), findsOneWidget);
    expect(find.text('第 1 话 · 2/30'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('第 2 话 · 第 1 位'), findsOneWidget);
    expect(find.text('第 3 话 · 缓存失败，请重试'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('comic-download-cancel-1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('comic-download-remove-2')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('comic-download-retry-3')),
    );
    await tester.pump();

    expect(queue.canceledIds, <int>[1]);
    expect(queue.removedIds, <int>[2]);
    expect(queue.retriedIds, <int>[3]);
  });

  testWidgets('renders a concise empty state', (tester) async {
    final snapshot = ValueNotifier<ComicDownloadQueueSnapshot>(
      ComicDownloadQueueSnapshot.empty,
    );
    addTearDown(snapshot.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicDownloadQueueProvider.overrideWithValue(
            _RecordingQueue(snapshot),
          ),
          comicDownloadQueueSnapshotProvider.overrideWithValue(snapshot),
        ],
        child: const LocalizedTestApp(home: ComicDownloadQueuePage()),
      ),
    );

    expect(find.byKey(const Key('comic-download-queue-empty')), findsOneWidget);
    expect(find.text('暂无缓存任务'), findsOneWidget);
  });

  testWidgets('supports Traditional Chinese cache terms at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot = ValueNotifier<ComicDownloadQueueSnapshot>(
      ComicDownloadQueueSnapshot(
        entries: <ComicDownloadQueueEntry>[
          _entry(
            id: 1,
            episodeTitle: '第一話',
            status: ComicDownloadQueueStatus.running,
            completed: 2,
            total: 30,
          ),
        ],
      ),
    );
    addTearDown(snapshot.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicDownloadQueueProvider.overrideWithValue(
            _RecordingQueue(snapshot),
          ),
          comicDownloadQueueSnapshotProvider.overrideWithValue(snapshot),
        ],
        child: LocalizedTestApp(
          locale: const Locale('zh', 'TW'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 720),
              textScaler: TextScaler.linear(1.6),
            ),
            child: const ComicDownloadQueuePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('快取佇列'), findsOneWidget);
    expect(find.text('正在快取'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ComicDownloadQueueEntry _entry({
  required int id,
  required String episodeTitle,
  required ComicDownloadQueueStatus status,
  int completed = 0,
  int? total,
  String? lastError,
}) {
  final now = DateTime(2026, 7, 22);
  return ComicDownloadQueueEntry(
    id: id,
    comicId: 'comic:1',
    episodeId: 'episode:$id',
    comicTitle: '测试漫画',
    episodeTitle: episodeTitle,
    status: status,
    completedImages: completed,
    totalImages: total,
    lastError: lastError,
    createdAt: now,
    updatedAt: now,
  );
}

final class _RecordingQueue implements ComicDownloadQueue {
  _RecordingQueue(this.snapshot);

  @override
  final ValueListenable<ComicDownloadQueueSnapshot> snapshot;
  final List<int> canceledIds = <int>[];
  final List<int> retriedIds = <int>[];
  final List<int> removedIds = <int>[];

  @override
  Future<void> cancel(int taskId) async {
    canceledIds.add(taskId);
  }

  @override
  Future<void> retry(int taskId) async {
    retriedIds.add(taskId);
  }

  @override
  Future<void> remove(int taskId) async {
    removedIds.add(taskId);
  }

  @override
  Future<ComicDownloadEnqueueResult> enqueueTargets(
    Iterable<ComicDownloadTarget> targets,
  ) async {
    return const ComicDownloadEnqueueResult(
      requestedCount: 0,
      enqueuedCount: 0,
      deduplicatedCount: 0,
      skippedDownloadedCount: 0,
    );
  }

  @override
  Future<void> cancelComic(String comicId) async {}

  @override
  Future<void> cancelEpisode(String comicId, String episodeId) async {}

  @override
  Future<void> start() async {}
}
