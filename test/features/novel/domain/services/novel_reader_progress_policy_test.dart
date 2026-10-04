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

      expect(snapshot.flowMode, NovelReaderFlowMode.pagedLtr);
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

  test('loaded anchor metadata preserves legacy and unsupported evidence', () {
    for (final (version, identity, validity) in <(int, String?, bool?)>[
      (0, null, null),
      (1, 'semantic-text-v1', true),
      (1, 'semantic-text-v1', false),
      (37, '  unsupported identity  ', null),
    ]) {
      final snapshot = policy.fromReadingProgress(
        novelId: 'novel:1',
        episodeId: 'episode-1',
        flowMode: NovelReaderFlowMode.pagedLtr,
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'episode-1',
          scrollOffset: 0,
          updatedAt: DateTime(2026, 10, 4),
          anchorFormatVersion: version,
          anchorTextOffset: -7,
          anchorTextIdentity: identity,
          isProgressPercentValid: validity,
        ),
      );

      expect(snapshot.anchorFormatVersion, version);
      expect(snapshot.anchorTextOffset, version == 1 ? 0 : -7);
      expect(snapshot.anchorTextIdentity, identity);
      expect(snapshot.isProgressPercentValid, validity);
      expect(snapshot.copyWith(), snapshot);
      expect(snapshot.copyWith().hashCode, snapshot.hashCode);
    }
  });

  test('snapshot copy distinguishes changed and cleared anchor metadata', () {
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorFormatVersion: 1,
      anchorTextIdentity: 'semantic-text-v1',
      progressPercent: 0,
      isProgressPercentValid: true,
    );

    expect(snapshot.copyWith(anchorFormatVersion: 2), isNot(snapshot));
    expect(
      snapshot.copyWith(anchorTextIdentity: 'semantic-text-v2'),
      isNot(snapshot),
    );
    expect(snapshot.copyWith(isProgressPercentValid: false), isNot(snapshot));
    final cleared = snapshot.copyWith(
      clearAnchorTextIdentity: true,
      clearProgressPercentValidity: true,
    );
    expect(cleared.anchorFormatVersion, 1);
    expect(cleared.anchorTextIdentity, isNull);
    expect(cleared.isProgressPercentValid, isNull);
    expect(snapshot.anchorTextIdentity, 'semantic-text-v1');
    expect(snapshot.isProgressPercentValid, isTrue);
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

  test('vertical restore uses percentage after the document is reflowed', () {
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 900,
      pageIndex: 0,
      progressPercent: 0.25,
    );

    expect(policy.restoreScrollOffset(snapshot, maxScrollExtent: 400), 100);
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
      anchorFormatVersion: 1,
      anchorTextIdentity: 'semantic-text-v1',
    );

    expect(snapshot.scrollOffset, 0);
    expect(snapshot.pageIndex, 2);
    expect(snapshot.pageCount, 5);
    expect(snapshot.paginationKey, 'layout-v1');
    expect(snapshot.anchorNodeId, 'paragraph-4');
    expect(snapshot.anchorTextOffset, 18);
    expect(snapshot.anchorFormatVersion, 1);
    expect(snapshot.anchorTextIdentity, 'semantic-text-v1');
    expect(snapshot.progressPercent, 0.4);
    expect(snapshot.isProgressPercentValid, isTrue);
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
      anchorFormatVersion: 1,
      anchorTextIdentity: 'semantic-text-v1',
    );

    expect(snapshot.pageIndex, 1);
    expect(snapshot.pageCount, isNull);
    expect(snapshot.anchorNodeId, 'paragraph-2');
    expect(snapshot.anchorFormatVersion, 1);
    expect(snapshot.anchorTextIdentity, 'semantic-text-v1');
    expect(snapshot.progressPercent, 0);
    expect(snapshot.isProgressPercentValid, isFalse);
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

      expect(policy.restoreScrollOffset(snapshot, maxScrollExtent: 800), 320);
    },
  );

  test('legacy paged progress also restores vertical position by percent', () {
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 345.5,
      pageIndex: 8,
      progressPercent: 0.625,
    );

    expect(
      policy.restoreScrollOffset(
        snapshot,
        maxScrollExtent: 800,
        viewportDimension: 200,
      ),
      300,
    );
    expect(
      policy.restoreScrollOffset(
        snapshot.copyWith(isProgressPercentValid: false),
        maxScrollExtent: 800,
        viewportDimension: 200,
      ),
      345.5,
    );
    expect(
      policy.restoreScrollOffset(
        snapshot.copyWith(progressPercent: 0, isProgressPercentValid: true),
        maxScrollExtent: 800,
        viewportDimension: 200,
      ),
      0,
    );
  });

  test('restore policy uses percentage before stale layout hints', () {
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
      pages: const [
        NovelReaderPageFragment(
          index: 0,
          html: '<p>one</p>',
          startAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-1',
          ),
          endAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-1',
            textOffset: 3,
          ),
          imageIndices: [],
        ),
        NovelReaderPageFragment(
          index: 1,
          html: '<p>two</p>',
          startAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-2',
          ),
          endAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-2',
            textOffset: 3,
          ),
          imageIndices: [],
        ),
        NovelReaderPageFragment(
          index: 2,
          html: '<p>three</p>',
          startAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-3',
          ),
          endAnchor: NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'paragraph-3',
            textOffset: 5,
          ),
          imageIndices: [],
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
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: sameLayout)
          .pageIndex,
      2,
    );

    final changedPosition = sameLayout.copyWith(progressPercent: 0.1);
    expect(
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: changedPosition)
          .pageIndex,
      0,
    );

    final changedLayout = sameLayout.copyWith(
      paginationKey: 'other-layout',
      pageIndex: 0,
      anchorNodeId: 'paragraph-2',
      anchorTextOffset: 1,
    );
    expect(
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: changedLayout)
          .pageIndex,
      1,
    );

    final percentOnly = sameLayout.copyWith(
      clearPaginationKey: true,
      pageIndex: 99,
      progressPercent: 0.5,
      clearAnchorNodeId: true,
    );
    expect(
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: percentOnly)
          .pageIndex,
      1,
    );

    final invalidLegacy = percentOnly.copyWith(progressPercent: 0);
    expect(
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: invalidLegacy)
          .pageIndex,
      0,
    );

    const verticalPercent = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 0,
      pageIndex: 0,
      progressPercent: 0.66,
    );
    expect(
      restorePolicy
          .resolveInitialPage(plan: plan, snapshot: verticalPercent)
          .pageIndex,
      1,
    );

    final partialPlan = NovelReaderPaginationPlan(
      key: key,
      episodeId: plan.episodeId,
      pages: <NovelReaderPageFragment>[plan.pages.first],
    );
    expect(
      restorePolicy
          .resolveAvailablePage(
            plan: partialPlan,
            snapshot: changedLayout,
            isPlanComplete: false,
          )
          ?.pageIndex,
      isNull,
    );
    expect(
      restorePolicy
          .resolveAvailablePage(
            plan: plan,
            snapshot: changedLayout,
            isPlanComplete: false,
          )
          ?.pageIndex,
      1,
    );
    expect(
      restorePolicy
          .resolveAvailablePage(
            plan: partialPlan,
            snapshot: invalidLegacy,
            isPlanComplete: true,
          )
          ?.pageIndex,
      0,
    );

    final canonicalPlan = NovelReaderPaginationPlan(
      key: key,
      episodeId: plan.episodeId,
      pages: [
        for (final page in plan.pages)
          NovelReaderPageFragment(
            index: page.index,
            html: page.html,
            startAnchor: page.startAnchor.copyWith(
              formatVersion: 1,
              textIdentity: 'text:${page.startAnchor.nodeId}',
            ),
            endAnchor: page.endAnchor.copyWith(
              formatVersion: 1,
              textIdentity: 'text:${page.endAnchor.nodeId}',
            ),
            imageIndices: page.imageIndices,
          ),
      ],
    );
    final exact = changedLayout.copyWith(
      anchorFormatVersion: 1,
      anchorTextIdentity: 'text:paragraph-2',
    );
    expect(
      restorePolicy
          .resolveInitialPage(plan: canonicalPlan, snapshot: exact)
          .isReadOnlyCompatibilityRestore,
      isFalse,
    );
    for (final compatibility in [
      exact.copyWith(anchorFormatVersion: 0),
      exact.copyWith(anchorFormatVersion: 37),
      exact.copyWith(anchorTextIdentity: 'changed text'),
    ]) {
      // Neither a trusted layout key nor a valid percentage proves the unit
      // of an unsupported or mismatched offset. The raw input stays untouched.
      for (final hint in [
        compatibility.copyWith(
          paginationKey: key.layoutFingerprint,
          pageIndex: 2,
        ),
        compatibility.copyWith(
          progressPercent: 0.5,
          isProgressPercentValid: true,
        ),
      ]) {
        final resolution = restorePolicy.resolveInitialPage(
          plan: canonicalPlan,
          snapshot: hint,
        );
        expect(resolution.isReadOnlyCompatibilityRestore, isTrue);
        expect(hint.anchorTextOffset, 1);
        expect(hint.anchorFormatVersion, compatibility.anchorFormatVersion);
        expect(hint.anchorTextIdentity, compatibility.anchorTextIdentity);
      }
      final nodeFirst = restorePolicy.resolveInitialPage(
        plan: canonicalPlan,
        snapshot: compatibility.copyWith(anchorTextOffset: 999),
      );
      expect(nodeFirst.pageIndex, 1);
      expect(nodeFirst.isReadOnlyCompatibilityRestore, isTrue);
    }
    expect(
      restorePolicy
          .resolveInitialPage(
            plan: canonicalPlan,
            snapshot: exact.copyWith(
              progressPercent: 0.8,
              isProgressPercentValid: false,
            ),
          )
          .pageIndex,
      1,
    );
    expect(
      restorePolicy
          .resolveInitialPage(
            plan: canonicalPlan,
            snapshot: exact.copyWith(
              progressPercent: 0,
              isProgressPercentValid: true,
            ),
          )
          .pageIndex,
      0,
    );
  });

  test('partial anchor coverage is finite and complete end is exact', () {
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
    const start = NovelReaderTextAnchor(
      episodeId: 'episode-1',
      nodeId: 'paragraph-1',
      formatVersion: 1,
      textIdentity: 'exact-paragraph-1',
    );
    NovelReaderPageFragment page(int index, int from, int to) {
      final fromAnchor = start.copyWith(textOffset: from);
      final toAnchor = start.copyWith(textOffset: to);
      return NovelReaderPageFragment(
        index: index,
        html: '<p>0123456789</p>',
        startAnchor: fromAnchor,
        endAnchor: toAnchor,
        anchorRanges: <NovelReaderPageAnchorRange>[
          NovelReaderPageAnchorRange(start: fromAnchor, end: toAnchor),
        ],
        imageIndices: const [],
      );
    }

    final firstPage = page(0, 0, 10);
    final partialPlan = NovelReaderPaginationPlan(
      key: key,
      episodeId: 'episode-1',
      pages: <NovelReaderPageFragment>[firstPage],
    );
    final extendedPlan = NovelReaderPaginationPlan(
      key: key,
      episodeId: 'episode-1',
      pages: <NovelReaderPageFragment>[firstPage, page(1, 10, 20)],
    );
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'episode-1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 99,
      paginationKey: 'previous-layout',
      anchorNodeId: 'paragraph-1',
      anchorTextOffset: 15,
      anchorFormatVersion: 1,
      anchorTextIdentity: 'exact-paragraph-1',
      progressPercent: 0,
    );
    const restorePolicy = NovelReaderPaginationRestorePolicy();
    final target = start.copyWith(textOffset: snapshot.anchorTextOffset);

    expect(target.textOffset, greaterThan(firstPage.endAnchor.textOffset));
    expect(
      partialPlan.pageIndexForAnchor(target, isPlanComplete: false),
      isNull,
    );
    expect(
      restorePolicy.resolveAvailablePage(
        plan: partialPlan,
        snapshot: snapshot,
        isPlanComplete: false,
      ),
      isNull,
    );
    expect(extendedPlan.pageIndexForAnchor(target, isPlanComplete: false), 1);
    expect(
      restorePolicy
          .resolveAvailablePage(
            plan: extendedPlan,
            snapshot: snapshot,
            isPlanComplete: false,
          )
          ?.pageIndex,
      1,
    );
    expect(
      partialPlan.pageIndexForAnchor(
        target.copyWith(nodeId: 'paragraph-2'),
        isPlanComplete: false,
      ),
      isNull,
    );
    expect(
      partialPlan.pageIndexForAnchor(
        start.copyWith(textOffset: 10),
        isPlanComplete: false,
      ),
      isNull,
    );
    expect(
      extendedPlan.pageIndexForAnchor(
        start.copyWith(textOffset: 10),
        isPlanComplete: false,
      ),
      1,
    );
    expect(
      extendedPlan.pageIndexForAnchor(
        start.copyWith(textOffset: 20),
        isPlanComplete: false,
      ),
      isNull,
    );
    expect(
      extendedPlan.pageIndexForAnchor(
        start.copyWith(textOffset: 20),
        isPlanComplete: true,
      ),
      1,
    );
    expect(
      extendedPlan.pageIndexForAnchor(
        start.copyWith(textOffset: 21),
        isPlanComplete: true,
      ),
      isNull,
    );
    expect(
      extendedPlan.pageIndexForAnchor(
        target.copyWith(textIdentity: 'changed'),
        isPlanComplete: true,
      ),
      isNull,
    );
    final nextNode = start.copyWith(
      nodeId: 'paragraph-2',
      textOffset: 0,
      textIdentity: 'exact-paragraph-2',
    );
    final multiRangeLastPage = NovelReaderPaginationPlan(
      key: key,
      episodeId: 'episode-1',
      pages: [
        NovelReaderPageFragment(
          index: 0,
          html: '<p>two nodes</p>',
          startAnchor: start,
          endAnchor: nextNode.copyWith(textOffset: 3),
          imageIndices: const [],
          anchorRanges: [
            NovelReaderPageAnchorRange(
              start: start,
              end: start.copyWith(textOffset: 10),
            ),
            NovelReaderPageAnchorRange(
              start: nextNode,
              end: nextNode.copyWith(textOffset: 3),
            ),
          ],
        ),
      ],
    );
    // Completeness only closes the actual final range, not every node range
    // contained in the final page.
    expect(
      multiRangeLastPage.pageIndexForAnchor(
        start.copyWith(textOffset: 10),
        isPlanComplete: true,
      ),
      isNull,
    );
    expect(
      multiRangeLastPage.pageIndexForAnchor(
        nextNode.copyWith(textOffset: 3),
        isPlanComplete: true,
      ),
      0,
    );
  });
}
