import 'package:flutter_test/flutter_test.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_hint_search.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_view_job.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';

import '../test_support/native_reader_test_fixture.dart';

NovelReaderTextAnchor _anchor(
  NativeReaderTestFixture fixture,
  int offset, {
  String node = 'node-0',
}) => fixture.anchors.segments
    .firstWhere((segment) => segment.projection.baseAnchor.nodeId == node)
    .projection
    .baseAnchor
    .copyWith(textOffset: offset);

List<NovelReaderNativePageHint> _collect(
  NovelReaderNativePageHintSearch search,
) {
  final result = <NovelReaderNativePageHint>[];
  while (!search.isComplete) {
    final step = search.advance(maxPages: 1, maxFragments: 1);
    expect(step.pagesRead, lessThanOrEqualTo(1));
    expect(step.fragmentsRead, lessThanOrEqualTo(1));
    expect(step.madeProgress, isTrue);
    result.addAll(search.takeCandidates());
  }
  result.addAll(search.takeCandidates());
  return result;
}

NovelReaderNativePageHintSearch _search(
  NativeReaderTestFixture fixture,
  NovelReaderTextAnchor anchor, {
  HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  int buffer = 32,
}) => NovelReaderNativePageHintSearch(
  snapshot: fixture.session.snapshot,
  layoutId: 'generation-a',
  anchors: fixture.anchors,
  anchor: anchor,
  affinity: affinity,
  maxBufferedCandidates: buffer,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'orphan annotation restores its real source beyond the font strut',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>aa</p><p><ruby><rt>xy</rt></ruby></p>',
        width: 20,
        height: 15,
      );
      final target = _anchor(fixture, 1, node: 'node-1');
      final builds = fixture.cache.layoutBuildCount;
      final hints = _collect(_search(fixture, target));
      expect(hints.map((hint) => hint.pageIndex), [1]);
      expect(fixture.cache.layoutBuildCount, builds);
      final view = await NovelReaderNativePageViewJob(
        session: fixture.session,
        anchors: fixture.anchors,
        pageIndex: 1,
        parent: fixture.parent,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      ).run();
      try {
        expect(view.coverage.locate(target), isNotNull);
        expect(view.coverage.points, isNotEmpty);
        expect(
          view.coverage.points.every((point) => point.sourceRune >= 2),
          isTrue,
        );
        expect(view.coverage.hasClippedGlyphs, isFalse);
      } finally {
        view.close();
      }
      expect(fixture.session.activeIssuedLeases, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test('moved base space keeps RT hints and page-local exact proof', () async {
    final fixture = NativeReaderTestFixture(
      '<p>X<ruby>AB <rt>xy</rt></ruby>Y</p>',
      width: 20,
      height: 15,
    );
    final target = _anchor(fixture, 5);
    final builds = fixture.cache.layoutBuildCount;
    final hints = _collect(_search(fixture, target));
    expect(hints.map((hint) => hint.pageIndex), [1]);
    expect(fixture.cache.layoutBuildCount, builds);
    for (final page in [1, 2]) {
      final view = await NovelReaderNativePageViewJob(
        session: fixture.session,
        anchors: fixture.anchors,
        pageIndex: page,
        parent: fixture.parent,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      ).run();
      try {
        expect(view.coverage.locate(target) != null, page == 1);
      } finally {
        view.close();
      }
      expect(fixture.session.activeIssuedLeases, 0);
      expect(fixture.cache.activeLeases, 0);
    }
  });

  test(
    'reverse lookup binds node identity and retains normalization plateaus',
    () {
      final fixture = NativeReaderTestFixture('<p>a   b</p><p>a   b</p>');
      final map = fixture.anchors;
      final first = map.sourceCandidates(_anchor(fixture, 2)).single;
      final second = map
          .sourceCandidates(_anchor(fixture, 2, node: 'node-1'))
          .single;
      expect((first.runeStart, first.runeEnd), (2, 4));
      expect((second.runeStart, second.runeEnd), (7, 9));
      final gap = NativeReaderTestFixture('<p><b>a</b>   <i>b</i></p>');
      expect(
        gap.anchors
            .sourceCandidates(_anchor(gap, 1))
            .map((range) => (range.runeStart, range.runeEnd)),
        [(1, 1), (4, 4)],
      );
      final joined = NativeReaderTestFixture('<p>a<b>b</b></p>');
      expect(joined.anchors.sourceCandidates(_anchor(joined, 1)).length, 1);
    },
  );

  test('exact source hints select later candidate pages without shaping preceding views', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
    );
    final builds = fixture.cache.layoutBuildCount;
    final target = _anchor(fixture, 4);
    final hints = _collect(_search(fixture, target));
    expect(
      hints.every((hint) => hint.identity == fixture.anchors.identity),
      isTrue,
    );
    expect(hints.every((hint) => hint.layoutId == 'generation-a'), isTrue);
    expect(hints.map((hint) => (hint.pageIndex, hint.kind)), [
      (1, NovelReaderNativePageHintKind.endpoint),
      (2, NovelReaderNativePageHintKind.preferred),
    ]);
    expect(fixture.cache.layoutBuildCount, builds);
    expect(fixture.session.activeIssuedLeases, 0);
    final job = NovelReaderNativePageViewJob(
      session: fixture.session,
      anchors: fixture.anchors,
      pageIndex: 2,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    );
    final view = await job.run();
    expect(view.coverage.locate(target), isNotNull);
    expect(fixture.session.activeIssuedLeases, 1);
    expect(fixture.cache.layoutBuildCount, builds);
    view.close();
  });

  test(
    'shared boundary hints follow explicit upstream or downstream priority',
    () {
      final fixture = NativeReaderTestFixture(
        '<p>abcd</p>',
        width: 20,
        height: 10,
      );
      final target = _anchor(fixture, 2);
      final down = _collect(_search(fixture, target));
      final up = _collect(
        _search(fixture, target, affinity: HtmlProjectionAffinity.upstream),
      );
      expect(down.map((hint) => hint.kind), [
        NovelReaderNativePageHintKind.endpoint,
        NovelReaderNativePageHintKind.preferred,
      ]);
      expect(up.map((hint) => hint.kind), [
        NovelReaderNativePageHintKind.preferred,
        NovelReaderNativePageHintKind.endpoint,
      ]);
    },
  );

  test('hidden raw source can be a page hint but never becomes exact visible proof', () async {
    final fixture = NativeReaderTestFixture(
      '<p>a<span style="display:none">hidden</span>b</p>',
    );
    final target = _anchor(fixture, 3);
    expect(_collect(_search(fixture, target)).single.pageIndex, 0);
    final view = await NovelReaderNativePageViewJob(
      session: fixture.session,
      anchors: fixture.anchors,
      pageIndex: 0,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    ).run();
    expect(view.coverage.locate(target), isNull);
    view.close();
  });

  test('candidate buffer backpressure resumes the same scan without dropping pages', () {
    final fixture = NativeReaderTestFixture(
      '<p style="white-space:pre-wrap">a        b</p>',
      width: 10,
      height: 10,
    );
    final search = _search(fixture, _anchor(fixture, 2), buffer: 1);
    final first = search.advance(maxPages: 100, maxFragments: 100);
    expect(first.bufferIsFull, isTrue);
    // The engine keeps trailing preserved spaces in the first line window.
    // Both envelopes intersect the semantic normalization plateau at 2..9.
    expect(search.nextPageIndex, 1);
    final paused = search.advance(maxPages: 100, maxFragments: 100);
    expect(paused.pagesRead, 0);
    expect(paused.fragmentsRead, 0);
    expect(paused.bufferIsFull, isTrue);
    final batch = search.takeCandidates();
    expect(() => batch.clear(), throwsUnsupportedError);
    final result = [...batch, ..._collect(search)];
    expect(result.map((hint) => hint.pageIndex), [0, 1]);
  });

  test(
    'a fixed partial prefix gains no candidates when its backing pages append',
    () {
      final fixture = NativeReaderTestFixture(
        '<p>abcdef</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      fixture.finishSource(pages: 1);
      final prefix = fixture.session.snapshot;
      final target = _anchor(fixture, 4);
      final first = _search(fixture, target);
      expect(_collect(first), isEmpty);
      fixture.finishSource(pages: 3);
      expect(prefix.length, 1);
      expect(fixture.session.isComplete, isFalse);
      final next = NovelReaderNativePageHintSearch(
        snapshot: fixture.session.snapshot,
        layoutId: 'generation-a',
        anchors: fixture.anchors,
        anchor: target,
        startPageIndex: first.nextPageIndex,
      );
      expect(_collect(next).map((hint) => hint.pageIndex), [1, 2]);
      expect(first.takeCandidates(), isEmpty);
    },
  );

  test('padding and terminal empty windows do not hint textual anchors', () {
    final fixture = NativeReaderTestFixture(
      '<div style="padding-top:20px">a</div>',
      height: 10,
    );
    expect(
      _collect(_search(fixture, _anchor(fixture, 0)))
          .map((hint) => hint.pageIndex),
      [2],
    );
    final empty = NativeReaderTestFixture('<p>a<br><br></p>', height: 10);
    expect(
      _collect(_search(empty, _anchor(empty, 2))).map((hint) => hint.pageIndex),
      [0],
    );
  });

  test(
    'unsupported anchor identities neither scan nor guess source candidates',
    () {
      final fixture = NativeReaderTestFixture('<p>abc</p>');
      final anchor = _anchor(fixture, 1);
      for (final wrong in [
        anchor.copyWith(formatVersion: 0),
        anchor.copyWith(formatVersion: 99),
        anchor.copyWith(episodeId: 'other'),
        anchor.copyWith(nodeId: 'other'),
        anchor.copyWith(textIdentity: 'other'),
        anchor.copyWith(textOffset: -1),
        anchor.copyWith(textOffset: 99),
      ]) {
        expect(fixture.anchors.sourceCandidates(wrong), isEmpty);
        final search = _search(fixture, wrong);
        expect(search.isComplete, isTrue);
        expect(search.takeCandidates(), isEmpty);
      }
    },
  );

  test(
    'scope, work bounds, buffer bounds and cancellation remain explicit',
    () {
      final fixture = NativeReaderTestFixture('<p>abc</p>');
      final target = _anchor(fixture, 1);
      expect(() => _search(fixture, target, buffer: 0), throwsArgumentError);
      expect(
        () => NovelReaderNativePageHintSearch(
          snapshot: fixture.session.snapshot,
          layoutId: 'other',
          anchors: fixture.anchors,
          anchor: target,
        ),
        throwsStateError,
      );
      final other = NativeReaderTestFixture('<p>other</p>');
      expect(
        () => NovelReaderNativePageHintSearch(
          snapshot: fixture.session.snapshot,
          layoutId: 'generation-a',
          anchors: other.anchors,
          anchor: target,
        ),
        throwsStateError,
      );
      final search = _search(fixture, target);
      expect(
        () => search.advance(maxPages: 0, maxFragments: 1),
        throwsArgumentError,
      );
      search.close();
      search.close();
      expect(search.takeCandidates, throwsStateError);
      expect(
        () => search.advance(maxPages: 1, maxFragments: 1),
        throwsStateError,
      );
    },
  );
}
