import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_anchor_map.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_coverage.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_coverage_cursor.dart';

final class _Fixture {
  _Fixture(
    String html, {
    double width = 100,
    double height = 100,
    bool complete = true,
  }) {
    final semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    final body = const ForumBodyParser().parse(
      html: html.trim(),
      sourceId: 'source',
      conversionIdentity: 'none',
    );
    anchors = const NovelReaderNativeAnchorBinder().bind(
      episodeId: 'episode',
      sourceId: 'source',
      semanticDocument: semantic,
      bodyDocument: body,
    );
    cache = ForumBodyParagraphCache(maxEntries: 32, maxEstimatedBytes: 1 << 22);
    session = ForumBodyTextPageSession(
      document: body,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xFF0000FF),
        paragraphAfter: 0,
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 20000,
        maxRuns: 1000,
        maxIssuedLeases: 64,
      ),
      layoutId: 'generation-a',
      width: width,
      height: height,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
    if (complete) finishSource();
  }
  late final NovelReaderNativeAnchorMap anchors;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;

  void finishSource({int? pages}) {
    var calls = 0;
    while (!session.isComplete &&
        (pages == null || session.snapshot.length < pages)) {
      if (++calls > 10000) fail('Source failed to make bounded progress');
      session.advance(maxEvents: 16, maxLines: 4);
    }
  }

  List<ForumBodyParagraphLease> prepare(int page) {
    final preparation = session.openPagePreparation(page);
    var calls = 0;
    while (!preparation.isReady) {
      if (++calls > 1000) fail('View failed to prepare');
      preparation.advance(maxFragments: 8);
    }
    return preparation.takeLeases();
  }

  NovelReaderNativePageCoverageCursor cursor(
    int page,
    List<ForumBodyParagraphLease> leases, {
    NovelReaderNativeCoverageLimits limits =
        const NovelReaderNativeCoverageLimits(),
  }) => NovelReaderNativePageCoverageCursor(
    anchors: anchors,
    snapshot: session.snapshot,
    pageIndex: page,
    layoutId: 'generation-a',
    leases: leases,
    limits: limits,
  );

  NovelReaderTextAnchor anchor(int offset, {String node = 'node-0'}) => anchors
      .segments
      .firstWhere((segment) => segment.projection.baseAnchor.nodeId == node)
      .projection
      .baseAnchor
      .copyWith(textOffset: offset);
}

NovelReaderNativePageCoverage _finish(
  NovelReaderNativePageCoverageCursor cursor,
) {
  var calls = 0;
  while (cursor.state == NovelReaderNativeCoverageState.active) {
    if (++calls > 10000) fail('Coverage failed to make bounded progress');
    final step = cursor.advance(maxGraphemes: 2, maxFragments: 1);
    expect(step.graphemesChecked, lessThanOrEqualTo(2));
    expect(step.fragmentsCompleted, lessThanOrEqualTo(1));
    expect(step.madeProgress, isTrue);
  }
  return cursor.result;
}

Matcher _failure(NovelReaderNativeCoverageFailure failure) => throwsA(
  isA<NovelReaderNativeCoverageException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bounded native box checks publish only whole immutable proof and never shape', () {
    final fixture = _Fixture('<p>abcdef</p>', width: 30, height: 20);
    final leases = fixture.prepare(0);
    final cursor = fixture.cursor(0, leases);
    final builds = fixture.cache.layoutBuildCount;
    final first = cursor.advance(maxGraphemes: 1, maxFragments: 1);
    expect(first.graphemesChecked, 1);
    expect(first.isComplete, isFalse);
    expect(() => cursor.result, throwsStateError);
    final coverage = _finish(cursor);
    expect(fixture.cache.layoutBuildCount, builds);
    expect(coverage.points, hasLength(12));
    expect(
      coverage.locate(fixture.anchor(0))!.affinity,
      HtmlProjectionAffinity.downstream,
    );
    expect(
      coverage.locate(fixture.anchor(6))!.affinity,
      HtmlProjectionAffinity.upstream,
    );
    expect(coverage.layoutId, 'generation-a');
    expect(coverage.pageIndex, 0);
    expect(() => coverage.points.clear(), throwsUnsupportedError);
    cursor.close();
    expect(leases.every((lease) => lease.isActive), isTrue);
    expect(coverage.locate(fixture.anchor(3)), isNotNull);
    expect(() => cursor.result, throwsStateError);
  });

  test('actual line windows exclude unpaged suffix and preserve a fixed partial prefix', () {
    final fixture = _Fixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 1);
    final prefix = fixture.session.snapshot;
    expect(prefix.isComplete, isFalse);
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    expect(coverage.locate(fixture.anchor(2)), isNotNull);
    expect(coverage.locate(fixture.anchor(3)), isNull);
    final before = coverage.points.toList();
    fixture.finishSource();
    expect(prefix, hasLength(1));
    expect(coverage.points, before);
    final next = _finish(fixture.cursor(1, fixture.prepare(1)));
    expect(
      next.locate(fixture.anchor(2))!.affinity,
      HtmlProjectionAffinity.downstream,
    );
    expect(
      coverage.locate(fixture.anchor(2))!.affinity,
      HtmlProjectionAffinity.upstream,
    );
  });

  test('hidden interiors are never covered, while explicit visible sides resolve source gaps', () {
    final fixture = _Fixture(
      '<p>a<span style="display:none">secret</span>b<span style="visibility:hidden">xyz</span>c</p>',
    );
    final leases = fixture.prepare(0);
    final coverage = _finish(fixture.cursor(0, leases));
    expect(coverage.points.map((p) => p.anchor.textOffset).toSet(), {
      0,
      1,
      7,
      8,
      11,
      12,
    });
    for (final offset in [2, 3, 4, 5, 6, 9, 10]) {
      expect(coverage.locate(fixture.anchor(offset)), isNull);
    }
    final snapped = fixture.anchors.projectDisplayPosition(
      content: leases.single.content,
      displayUtf16: 1,
      affinity: HtmlProjectionAffinity.downstream,
    )!;
    expect(snapped.isExact, isFalse);
    // The known b-start is exact only after the legal grapheme, actual clip,
    // visible style and explicit downstream neighbour have all been checked.
    expect(coverage.locate(fixture.anchor(7))!.sourceRune, 7);
  });

  test('an entirely invisible paragraph contributes no textual proof', () {
    final fixture = _Fixture('<p style="visibility:hidden">abc</p>');
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    expect(coverage.points, isEmpty);
    expect(coverage.locate(fixture.anchor(0)), isNull);
  });

  test('a partly hidden combining grapheme is excluded as a whole', () {
    final fixture = _Fixture(
      '<p>e<span style="visibility:hidden">\u0301</span>b</p>',
    );
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    expect(coverage.points.map((point) => point.anchor.textOffset).toSet(), {
      2,
      3,
    });
    expect(coverage.locate(fixture.anchor(1)), isNull);
  });

  test('RTL coverage uses native boxes and logical semantic codepoints', () {
    final fixture = _Fixture('<p dir="rtl">אבג</p>');
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    for (var offset = 0; offset <= 3; offset++) {
      expect(coverage.locate(fixture.anchor(offset)), isNotNull);
    }
  });

  test('an unmapped glyph cannot borrow its hidden neighbour origin at a shared endpoint', () {
    final fixture = _Fixture(
      '<p><a href="https://example.org">a<script>x</script>b</a><span style="visibility:hidden">尾</span></p>',
    );
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    expect(fixture.anchors.unmappedPaths, ['0/0']);
    expect(coverage.points, isEmpty);
    expect(coverage.locate(fixture.anchor(3)), isNull);
  });

  test('a clipped native glyph cannot prove its raw source interval', () {
    final fixture = _Fixture('<p>a</p>', width: 3, height: 10);
    final leases = fixture.prepare(0);
    expect(
      leases.single.layout.selectionBoxes(0, 1).single.right,
      greaterThan(3),
    );
    final coverage = _finish(fixture.cursor(0, leases));
    expect(coverage.points, isEmpty);
  });

  test('an omitted terminal BR is not covered merely because its semantic node exists', () {
    final fixture = _Fixture('<p>a<br>b<br></p>');
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    expect(coverage.locate(fixture.anchor(2)), isNotNull);
    expect(coverage.locate(fixture.anchor(3)), isNotNull);
    expect(coverage.locate(fixture.anchor(4)), isNull);
  });

  test('preserved terminal empty rows have no new source coverage', () {
    final fixture = _Fixture('<p>a<br><br></p>', height: 10);
    expect(fixture.session.snapshot, hasLength(2));
    final first = _finish(fixture.cursor(0, fixture.prepare(0)));
    final empty = _finish(fixture.cursor(1, fixture.prepare(1)));
    expect(first.locate(fixture.anchor(2)), isNotNull);
    expect(empty.points, isEmpty);
  });

  test('padding-only pages produce empty proof without requiring text/view budgets', () {
    final fixture = _Fixture(
      '<div style="padding-top:20px">a</div>',
      height: 10,
    );
    expect(fixture.session.snapshot.first.fragments, isEmpty);
    final cursor = fixture.cursor(
      0,
      const [],
      limits: const NovelReaderNativeCoverageLimits(
        maxFragments: 0,
        maxGraphemes: 0,
        maxPoints: 0,
      ),
    );
    final step = cursor.advance(maxGraphemes: 1, maxFragments: 1);
    expect(step.isComplete, isTrue);
    expect(step.madeProgress, isTrue);
    expect(cursor.result.points, isEmpty);
  });

  test('lease retirement cancels partial proof and does not revive it', () {
    final fixture = _Fixture('<p>abc</p>');
    final leases = fixture.prepare(0);
    final cursor = fixture.cursor(0, leases);
    cursor.advance(maxGraphemes: 1, maxFragments: 1);
    leases.single.release();
    expect(
      () => cursor.advance(maxGraphemes: 1, maxFragments: 1),
      _failure(NovelReaderNativeCoverageFailure.retired),
    );
    expect(cursor.state, NovelReaderNativeCoverageState.failed);
    expect(() => cursor.result, throwsStateError);
    expect(
      () => cursor.advance(maxGraphemes: 1, maxFragments: 1),
      throwsStateError,
    );
  });

  test('closing the native owner invalidates partially checked coverage', () {
    final fixture = _Fixture('<p>abc</p>');
    final cursor = fixture.cursor(0, fixture.prepare(0));
    cursor.advance(maxGraphemes: 1, maxFragments: 1);
    fixture.cache.close();
    expect(
      () => cursor.advance(maxGraphemes: 1, maxFragments: 1),
      _failure(NovelReaderNativeCoverageFailure.retired),
    );
    expect(cursor.state, NovelReaderNativeCoverageState.failed);
    expect(() => cursor.result, throwsStateError);
    expect(fixture.cache.activeLeases, 0);
  });

  test('coverage cancellation preserves caller-owned leases and the source session', () {
    final fixture = _Fixture('<p>abc</p>');
    final leases = fixture.prepare(0);
    final cursor = fixture.cursor(0, leases);
    expect(
      () => cursor.advance(maxGraphemes: 0, maxFragments: 1),
      throwsArgumentError,
    );
    expect(cursor.state, NovelReaderNativeCoverageState.active);
    cursor.advance(maxGraphemes: 1, maxFragments: 1);
    cursor.close();
    cursor.close();
    expect(leases.single.isActive, isTrue);
    expect(fixture.session.isComplete, isTrue);
    expect(_finish(fixture.cursor(0, leases)).points, isNotEmpty);
  });

  test('point, fragment and work retention budgets fail transactionally', () {
    final fixture = _Fixture('<p>abc</p>');
    final leases = fixture.prepare(0);
    expect(
      () => fixture.cursor(
        0,
        leases,
        limits: const NovelReaderNativeCoverageLimits(maxFragments: 0),
      ),
      _failure(NovelReaderNativeCoverageFailure.budget),
    );
    for (final limits in [
      const NovelReaderNativeCoverageLimits(maxPoints: 1),
      const NovelReaderNativeCoverageLimits(maxGraphemes: 1),
    ]) {
      final cursor = fixture.cursor(0, leases, limits: limits);
      expect(
        () => _finish(cursor),
        _failure(NovelReaderNativeCoverageFailure.budget),
      );
      expect(cursor.state, NovelReaderNativeCoverageState.failed);
      expect(() => cursor.result, throwsStateError);
      expect(leases.single.isActive, isTrue);
    }
  });

  test('only matching canonical identities can locate a covered point', () {
    final fixture = _Fixture('<p>abc</p>');
    final coverage = _finish(fixture.cursor(0, fixture.prepare(0)));
    final anchor = fixture.anchor(1);
    for (final wrong in [
      anchor.copyWith(formatVersion: 0),
      anchor.copyWith(formatVersion: 999),
      anchor.copyWith(clearTextIdentity: true),
      anchor.copyWith(textIdentity: 'other'),
      anchor.copyWith(nodeId: 'node-999'),
      anchor.copyWith(episodeId: 'other'),
      anchor.copyWith(textOffset: -1),
      anchor.copyWith(textOffset: 99),
    ]) {
      expect(coverage.locate(wrong), isNull);
    }
    expect(coverage.locate(anchor), isNotNull);
  });

  test(
    'readiness gate rejects wrong generation, identity or retired leases',
    () {
      final fixture = _Fixture('<p>abc</p>');
      final leases = fixture.prepare(0);
      expect(
        () => NovelReaderNativePageCoverageCursor(
          anchors: fixture.anchors,
          snapshot: fixture.session.snapshot,
          pageIndex: 0,
          layoutId: 'wrong',
          leases: leases,
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      final other = _Fixture('<p>other</p>');
      expect(
        () => NovelReaderNativePageCoverageCursor(
          anchors: other.anchors,
          snapshot: fixture.session.snapshot,
          pageIndex: 0,
          layoutId: 'generation-a',
          leases: leases,
        ),
        _failure(NovelReaderNativeCoverageFailure.identity),
      );
      leases.single.release();
      expect(
        () => fixture.cursor(0, leases),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
    },
  );
}
