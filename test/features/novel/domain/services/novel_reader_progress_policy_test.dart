import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_restore_policy.dart';

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

  test('pagedSnapshot records the visible page identity and anchor', () {
    final snapshot = policy.pagedSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      pageIndex: 2,
      pageCount: 5,
      paginationKey: 'layout-v1',
      anchorNodeId: 'paragraph-4',
      anchorTextOffset: 18,
    );

    expect(snapshot.scrollOffset, 0);
    expect(snapshot.pageIndex, 2);
    expect(snapshot.paginationKey, 'layout-v1');
    expect(snapshot.anchorNodeId, 'paragraph-4');
    expect(snapshot.anchorTextOffset, 18);
    expect(snapshot.progressPercent, 0.5);
  });

  test('incremental page count does not fabricate completion percent', () {
    final snapshot = policy.pagedSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      pageIndex: 1,
      pageCount: 2,
      paginationKey: 'layout-v1',
      isPageCountFinal: false,
      anchorNodeId: 'paragraph-2',
    );

    expect(snapshot.pageIndex, 1);
    expect(snapshot.anchorNodeId, 'paragraph-2');
    expect(snapshot.progressPercent, 0);
  });

  test(
    'paged progress can restore vertical position by percent after mode switch',
    () {
      final snapshot = policy.pagedSnapshot(
        novelId: 'novel:1',
        episodeId: 'episode-1',
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: 2,
        pageCount: 5,
        paginationKey: 'layout-v1',
      );

      expect(policy.restoreScrollOffset(snapshot, maxScrollExtent: 800), 400);
    },
  );

  test('legacy paged progress also restores vertical position by percent', () {
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 345.5,
      pageIndex: 8,
      progressPercent: 0.625,
    );

    expect(policy.restoreScrollOffset(snapshot, maxScrollExtent: 800), 500);
  });

  test('restore policy prefers same layout page, then anchor and percent', () {
    const key = NovelReaderPaginationKey(
      episodeId: 'episode-1',
      contentHash: 'content',
      viewportWidthPx: 320,
      viewportHeightPx: 600,
      typographySignature: 'type',
      themeSignature: 'theme',
      imageDimensionRevision: 1,
      rendererRevision: 1,
    );
    final plan = NovelReaderPaginationPlan(
      key: key,
      episodeId: 'episode-1',
      pages: [
        NovelReaderPageFragment(
          index: 0,
          html: '<p>one</p>',
          startAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-1',
          ),
          endAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-1',
            textOffset: 3,
          ),
          imageIndices: const [],
        ),
        NovelReaderPageFragment(
          index: 1,
          html: '<p>two</p>',
          startAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-2',
          ),
          endAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-2',
            textOffset: 3,
          ),
          imageIndices: const [],
        ),
        NovelReaderPageFragment(
          index: 2,
          html: '<p>three</p>',
          startAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-3',
          ),
          endAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-3',
            textOffset: 5,
          ),
          imageIndices: const [],
        ),
      ],
    );
    const restorePolicy = NovelReaderPaginationRestorePolicy();

    final sameLayout = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 2,
      paginationKey: key.layoutFingerprint,
      progressPercent: 0,
    );
    expect(
      restorePolicy.resolveInitialPage(plan: plan, snapshot: sameLayout),
      2,
    );

    final changedLayout = sameLayout.copyWith(
      paginationKey: 'other-layout',
      pageIndex: 0,
      anchorNodeId: 'paragraph-2',
      anchorTextOffset: 1,
    );
    expect(
      restorePolicy.resolveInitialPage(plan: plan, snapshot: changedLayout),
      1,
    );

    final percentOnly = sameLayout.copyWith(
      clearPaginationKey: true,
      pageIndex: 99,
      progressPercent: 0.5,
      clearAnchorNodeId: true,
    );
    expect(
      restorePolicy.resolveInitialPage(plan: plan, snapshot: percentOnly),
      1,
    );

    final invalidLegacy = percentOnly.copyWith(progressPercent: 0);
    expect(
      restorePolicy.resolveInitialPage(plan: plan, snapshot: invalidLegacy),
      0,
    );

    final partialPlan = NovelReaderPaginationPlan(
      key: key,
      episodeId: plan.episodeId,
      pages: <NovelReaderPageFragment>[plan.pages.first],
    );
    expect(
      restorePolicy.resolveAvailablePage(
        plan: partialPlan,
        snapshot: changedLayout,
        isPlanComplete: false,
      ),
      isNull,
    );
    expect(
      restorePolicy.resolveAvailablePage(
        plan: plan,
        snapshot: changedLayout,
        isPlanComplete: false,
      ),
      1,
    );
    expect(
      restorePolicy.resolveAvailablePage(
        plan: partialPlan,
        snapshot: invalidLegacy,
        isPlanComplete: true,
      ),
      0,
    );
  });
}
