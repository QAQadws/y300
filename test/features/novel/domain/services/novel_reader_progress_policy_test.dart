import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

void main() {
  const policy = NovelReaderProgressPolicy();

  test('initialSnapshot always starts at the beginning', () {
    final snapshot = policy.initialSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.vertical,
    );

    expect(snapshot.flowMode, NovelReaderFlowMode.vertical);
    expect(snapshot.scrollOffset, 0);
    expect(snapshot.pageIndex, 0);
    expect(snapshot.anchorNodeId, isNull);
    expect(snapshot.progressPercent, 0);
  });

  test(
    'fromReadingProgress normalizes persisted values for the active mode',
    () {
      final snapshot = policy.fromReadingProgress(
        novelId: 'novel:1',
        episodeId: 'episode-1',
        flowMode: NovelReaderFlowMode.vertical,
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'episode-1',
          scrollOffset: -10,
          updatedAt: DateTime(2026, 7, 20),
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: -2,
          anchorNodeId: '  paragraph-8  ',
          progressPercent: 1.4,
        ),
      );

      expect(snapshot.flowMode, NovelReaderFlowMode.vertical);
      expect(snapshot.scrollOffset, 0);
      expect(snapshot.pageIndex, 0);
      expect(snapshot.anchorNodeId, 'paragraph-8');
      expect(snapshot.progressPercent, 1);
    },
  );

  test('fromReadingProgress ignores progress from another episode', () {
    final snapshot = policy.fromReadingProgress(
      novelId: 'novel:1',
      episodeId: 'episode-2',
      flowMode: NovelReaderFlowMode.vertical,
      progress: NovelReadingProgress(
        novelId: 'novel:1',
        episodeId: 'episode-1',
        scrollOffset: 200,
        updatedAt: DateTime(2026, 7, 20),
      ),
    );

    expect(snapshot.episodeId, 'episode-2');
    expect(snapshot.scrollOffset, 0);
    expect(snapshot.progressPercent, 0);
  });

  test(
    'verticalSnapshot calculates bounded progress without page semantics',
    () {
      final snapshot = policy.verticalSnapshot(
        novelId: 'novel:1',
        episodeId: 'episode-1',
        scrollOffset: 50,
        maxScrollExtent: 200,
        anchorNodeId: 'paragraph-2',
      );

      expect(snapshot.flowMode, NovelReaderFlowMode.vertical);
      expect(snapshot.scrollOffset, 50);
      expect(snapshot.pageIndex, 0);
      expect(snapshot.anchorNodeId, 'paragraph-2');
      expect(snapshot.progressPercent, 0.25);
      expect(snapshot.isPaged, isFalse);
    },
  );

  test('restoreScrollOffset clamps to the current vertical extent', () {
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 900,
      pageIndex: 0,
      progressPercent: 1,
    );

    expect(policy.restoreScrollOffset(snapshot, maxScrollExtent: 320), 320);
  });
}
