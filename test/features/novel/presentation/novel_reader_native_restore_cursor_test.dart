import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_coverage.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_view_job.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_restore_cursor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';

import '../test_support/native_reader_test_fixture.dart';

NovelReaderTextAnchor _anchor(NativeReaderTestFixture fixture, int offset) =>
    fixture.anchors.segments.first.projection.baseAnchor.copyWith(
      textOffset: offset,
    );

NovelReaderProgressSnapshot _position({
  NovelReaderTextAnchor? anchor,
  String episodeId = 'episode',
}) => NovelReaderProgressSnapshot(
  novelId: 'novel',
  episodeId: episodeId,
  flowMode: NovelReaderFlowMode.pagedLtr,
  scrollOffset: 0,
  pageIndex: 99,
  paginationKey: 'old-geometry',
  anchorNodeId: anchor?.nodeId,
  anchorTextOffset: anchor?.textOffset ?? 0,
  anchorFormatVersion: anchor?.formatVersion ?? 0,
  anchorTextIdentity: anchor?.textIdentity,
  progressPercent: 0,
);

NovelReaderNativeRestoreCursor _cursor(
  NativeReaderTestFixture fixture,
  NovelReaderProgressSnapshot position, {
  NovelReaderTextAnchor? conversionAnchor,
  int maxCoveragePoints = 8192,
}) {
  final cursor = NovelReaderNativeRestoreCursor(
    identity: fixture.anchors.identity,
    layoutId: 'generation-a',
    episodeId: 'episode',
    paginationKey: 'native-geometry',
    position: position,
    conversionAnchor: conversionAnchor,
    maxCoveragePoints: maxCoveragePoints,
  );
  addTearDown(cursor.close);
  return cursor;
}

Future<NovelReaderNativePageCoverage> _coverage(
  NativeReaderTestFixture fixture,
  int page,
) async {
  final view = await NovelReaderNativePageViewJob(
    session: fixture.session,
    anchors: fixture.anchors,
    pageIndex: page,
    parent: fixture.parent,
    scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
  ).run();
  final proof = view.coverage;
  view.close();
  return proof;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'partial exact coverage wins and later EOF cannot jump by old percentage',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      fixture.finishSource(pages: 2);
      final saved = _position(anchor: _anchor(fixture, 3))
          .copyWith(progressPercent: .95, isProgressPercentValid: true);
      final cursor = _cursor(fixture, saved);
      expect(cursor.requiresCompletePageCount, isTrue);
      expect(cursor.resolve(fixture.session.snapshot), isNull);
      cursor.observe(
        snapshot: fixture.session.snapshot,
        coverage: await _coverage(fixture, 1),
      );
      final first = cursor.resolve(fixture.session.snapshot)!;
      expect(first.pageIndex, 1);
      expect(first.isReadOnlyCompatibilityRestore, isFalse);
      expect(cursor.requiresCompletePageCount, isFalse);
      expect(cursor.targetAnchor, isNull);
      fixture.finishSource();
      expect(cursor.resolve(fixture.session.snapshot), same(first));
      expect(saved.progressPercent, .95);
      expect(saved.anchorTextOffset, 3);
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );

  test(
    'complete exact coverage cannot authorize a different percentage page',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
      );
      final cursor = _cursor(
        fixture,
        _position(anchor: _anchor(fixture, 1)).copyWith(
          progressPercent: .95,
          isProgressPercentValid: true,
          pageCount: 8,
        ),
      );
      cursor.observe(
        snapshot: fixture.session.snapshot,
        coverage: await _coverage(fixture, 0),
      );
      final result = cursor.resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, 0);
      expect(result.isReadOnlyCompatibilityRestore, isFalse);
    },
  );

  test('a canonical offset outside partial coverage waits instead of using node head', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 1);
    final cursor = _cursor(fixture, _position(anchor: _anchor(fixture, 7)));
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 0),
    );
    expect(cursor.resolve(fixture.session.snapshot), isNull);
    fixture.finishSource();
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 3),
    );
    expect(cursor.resolve(fixture.session.snapshot)!.pageIndex, 3);
  });

  test('only explicitly valid zero resolves the first stable prefix without proof', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final saved = _position(anchor: _anchor(fixture, 7))
        .copyWith(anchorFormatVersion: 37);
    final valid = _cursor(
      fixture,
      saved.copyWith(isProgressPercentValid: true),
    );
    expect(valid.resolve(fixture.session.snapshot), isNull);
    fixture.finishSource(pages: 1);
    final result = valid.resolve(fixture.session.snapshot)!;
    expect(result.pageIndex, 0);
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
    for (final position in [
      saved,
      saved.copyWith(isProgressPercentValid: false),
    ]) {
      expect(
        _cursor(fixture, position).resolve(fixture.session.snapshot),
        isNull,
      );
    }
    // Even proof arriving later cannot silently upgrade a read-only selection.
    valid.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 0),
    );
    fixture.finishSource();
    expect(valid.resolve(fixture.session.snapshot), same(result));
  });

  test('valid zero is writable only when that selected first page proves the saved anchor', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
    );
    for (final offset in [1, 7]) {
      final cursor = _cursor(
        fixture,
        _position(anchor: _anchor(fixture, offset))
            .copyWith(isProgressPercentValid: true),
      );
      cursor.observe(
        snapshot: fixture.session.snapshot,
        coverage: await _coverage(fixture, offset == 1 ? 0 : 3),
      );
      final result = cursor.resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, 0);
      expect(result.isReadOnlyCompatibilityRestore, offset != 1);
    }
  });

  test('legacy, future and changed text identities stay read-only with matching layout hints', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 2);
    final proof = await _coverage(fixture, 1);
    final canonical = _position(anchor: _anchor(fixture, 3));
    for (final saved in [
      canonical.copyWith(anchorFormatVersion: 0),
      canonical.copyWith(anchorFormatVersion: 37),
      canonical.copyWith(anchorTextIdentity: 'changed'),
      canonical.copyWith(anchorTextOffset: 999),
    ]) {
      final cursor = _cursor(
        fixture,
        saved.copyWith(paginationKey: 'native-geometry', pageIndex: 1),
      );
      cursor.observe(snapshot: fixture.session.snapshot, coverage: proof);
      final result = cursor.resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, 1);
      expect(result.isReadOnlyCompatibilityRestore, isTrue);
    }
  });

  test('observed node compatibility remains read-only when text identity cannot match', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 2);
    final cursor = _cursor(
      fixture,
      _position(anchor: _anchor(fixture, 3)).copyWith(anchorFormatVersion: 37),
    );
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 1),
    );
    final result = cursor.resolve(fixture.session.snapshot)!;
    expect(result.pageIndex, 1);
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
  });

  test('a same-key compatibility selection cannot upgrade when exact proof arrives later', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 2);
    final cursor = _cursor(
      fixture,
      _position(anchor: _anchor(fixture, 3))
          .copyWith(paginationKey: 'native-geometry', pageIndex: 1),
    );
    final result = cursor.resolve(fixture.session.snapshot)!;
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 1),
    );
    expect(cursor.resolve(fixture.session.snapshot), same(result));
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
  });

  test('conversion coverage takes priority but remains read-only and releases old percentage demand', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 2);
    final target = _anchor(fixture, 3);
    final cursor = _cursor(
      fixture,
      _position(anchor: _anchor(fixture, 0))
          .copyWith(progressPercent: .9, isProgressPercentValid: true),
      conversionAnchor: target,
    );
    expect(cursor.targetAnchor, same(target));
    expect(cursor.requiresCompletePageCount, isFalse);
    expect(cursor.resolve(fixture.session.snapshot), isNull);
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 1),
    );
    final result = cursor.resolve(fixture.session.snapshot)!;
    expect(result.pageIndex, 1);
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
    expect(cursor.requiresCompletePageCount, isFalse);
    fixture.finishSource();
    expect(cursor.resolve(fixture.session.snapshot), same(result));
  });

  test('missing conversion hints wait for actual EOF and their fallback cannot become writable', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 1);
    final cursor = _cursor(
      fixture,
      _position(anchor: _anchor(fixture, 1)),
      conversionAnchor: _anchor(fixture, 99),
    );
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 0),
    );
    expect(cursor.resolve(fixture.session.snapshot), isNull);
    fixture.finishSource();
    final result = cursor.resolve(fixture.session.snapshot)!;
    expect(result.pageIndex, 0);
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
  });

  test('percentage approximation preserves current and legacy conventions at actual EOF', () {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 2);
    final base = _position().copyWith(
      progressPercent: .5,
      isProgressPercentValid: true,
    );
    final cursors = [
      _cursor(fixture, base),
      _cursor(fixture, base.copyWith(pageCount: 99)),
      _cursor(fixture, base.copyWith(flowMode: NovelReaderFlowMode.vertical)),
      _cursor(fixture, base.copyWith(progressPercent: 9)),
    ];
    for (final cursor in cursors) {
      expect(cursor.resolve(fixture.session.snapshot), isNull);
      expect(cursor.requiresCompletePageCount, isTrue);
    }
    fixture.finishSource();
    for (var index = 0; index < cursors.length; index++) {
      final result = cursors[index].resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, [1, 2, 2, 3][index]);
      expect(result.isReadOnlyCompatibilityRestore, isTrue);
    }
  });

  test('unknown future percentage basis remains opaque even with canonical coverage', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
    );
    final position = _position(anchor: _anchor(fixture, 3)).copyWith(
      percentBasis: 'futureBasis',
      progressPercent: .95,
      isProgressPercentValid: true,
    );
    final cursor = _cursor(fixture, position);
    cursor.observe(
      snapshot: fixture.session.snapshot,
      coverage: await _coverage(fixture, 1),
    );
    final result = cursor.resolve(fixture.session.snapshot)!;
    expect(result.pageIndex, 1);
    expect(result.isReadOnlyCompatibilityRestore, isTrue);
    expect(position.percentBasis, 'futureBasis');
    expect(position.progressPercent, .95);
  });

  test('nonfinite, negative and unavailable percentages do not create completion demand', () {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
    );
    for (final value in [double.nan, double.infinity, -1.0, 0.0]) {
      final cursor = _cursor(
        fixture,
        _position().copyWith(progressPercent: value),
      );
      expect(cursor.requiresCompletePageCount, isFalse);
      final result = cursor.resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, 0);
      expect(result.isReadOnlyCompatibilityRestore, isTrue);
    }
    expect(
      _cursor(
        fixture,
        _position().copyWith(
          progressPercent: .8,
          isProgressPercentValid: false,
        ),
      ).requiresCompletePageCount,
      isFalse,
    );
  });

  test(
    'oversized stale page falls back to head rather than the final page',
    () {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
      );
      for (final page in [-1, 2, 99]) {
        final result = _cursor(
          fixture,
          _position().copyWith(pageIndex: page),
        ).resolve(fixture.session.snapshot)!;
        expect(result.pageIndex, page == 2 ? 2 : 0);
        expect(result.isReadOnlyCompatibilityRestore, isTrue);
      }
    },
  );

  test(
    'another episode cannot impose its percentage or proof on this restore',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      fixture.finishSource(pages: 1);
      final position =
          _position(episodeId: 'foreign', anchor: _anchor(fixture, 1)).copyWith(
            progressPercent: .9,
            isProgressPercentValid: true,
            percentBasis: 'futureBasis',
          );
      final cursor = _cursor(fixture, position);
      expect(cursor.requiresCompletePageCount, isFalse);
      cursor.observe(
        snapshot: fixture.session.snapshot,
        coverage: await _coverage(fixture, 0),
      );
      final result = cursor.resolve(fixture.session.snapshot)!;
      expect(result.pageIndex, 0);
      expect(result.isReadOnlyCompatibilityRestore, isTrue);
      expect(position.percentBasis, 'futureBasis');
      expect(position.anchorTextOffset, 1);
      expect(position.progressPercent, .9);
    },
  );

  test('prefix identity, monotonic publication and proof budgets are checked before selection', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final empty = fixture.session.snapshot;
    fixture.finishSource(pages: 1);
    final cursor = _cursor(fixture, _position(anchor: _anchor(fixture, 7)));
    expect(cursor.resolve(fixture.session.snapshot), isNull);
    expect(() => cursor.resolve(empty), throwsStateError);
    final foreign = NativeReaderTestFixture('<p>different</p>');
    expect(() => cursor.resolve(foreign.session.snapshot), throwsStateError);
    final proof = await _coverage(fixture, 0);
    expect(
      () => _cursor(
        fixture,
        _position(),
        maxCoveragePoints: 0,
      ).observe(snapshot: fixture.session.snapshot, coverage: proof),
      throwsStateError,
    );
    for (final wrong in [
      NovelReaderNativePageCoverage(
        identity: proof.identity,
        layoutId: 'retired',
        pageIndex: 0,
        points: proof.points,
      ),
      NovelReaderNativePageCoverage(
        identity: proof.identity,
        layoutId: proof.layoutId,
        pageIndex: 99,
        points: proof.points,
      ),
    ]) {
      expect(
        () =>
            cursor.observe(snapshot: fixture.session.snapshot, coverage: wrong),
        throwsStateError,
      );
    }
    cursor.close();
    cursor.close();
    expect(cursor.requiresCompletePageCount, isFalse);
    expect(cursor.targetAnchor, isNull);
    expect(() => cursor.resolve(fixture.session.snapshot), throwsStateError);
  });
}
