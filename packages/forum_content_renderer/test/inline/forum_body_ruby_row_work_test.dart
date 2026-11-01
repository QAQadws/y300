import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart'
    show ForumBodyRubyLevelUnion, ForumBodyRubyColumnAlignment;
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';

import 'test_support/ruby_row_fixture.dart';

ForumBodyRubyRowAlignment _alignment(
  RubyRowFixture fixture, {
  List<int> ids = const [0, 0],
}) => ForumBodyRubyRowAlignment(
  columns: fixture.metrics,
  levelIds: ids,
  atomOffsets: fixture.content.projection.atoms
      .map((atom) => atom.engineUtf16)
      .toList(),
);

int _advance(
  ForumBodyRubyRowAlignment work,
  RubyRowFixture fixture,
  int quantum,
) {
  var calls = 0;
  while (!work.isComplete && !work.needsRows && calls++ < 10000) {
    final before = (
      fixture.cache.layoutBuildCount,
      fixture.cache.pictureBuildCount,
      fixture.cache.activeLeases,
    );
    expect(work.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    expect((
      fixture.cache.layoutBuildCount,
      fixture.cache.pictureBuildCount,
      fixture.cache.activeLeases,
    ), before);
  }
  expect(calls, lessThan(10000));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final quantum in [1, 7, 32]) {
    for (final narrow in [false, true]) {
      test(
        '100-rank two-column alignment follows actual rows within q=$quantum, narrow=$narrow',
        () {
          final fixture = RubyRowFixture();
          addTearDown(fixture.close);
          final work = _alignment(fixture);
          final firstCalls = _advance(work, fixture, quantum);
          expect(firstCalls, greaterThan(200 ~/ quantum));
          expect(work.needsRows, isTrue);
          final raw = fixture.parent(narrow ? 30 : 60);
          expect(raw.layout.lines.length, narrow ? 2 : 1);
          work.attachRows(raw.layout.lines);
          _advance(work, fixture, quantum);
          expect(work.isComplete, isTrue);
          expect(work.hasChanges, !narrow);
          ForumBodyInlineParagraphLease finalParent;
          if (narrow) {
            expect(work.targets, [null, null]);
            expect(
              work.dimensions,
              fixture.metrics.map((item) => item.placeholderDimensions),
            );
            finalParent = raw;
          } else {
            expect(work.targets.every((item) => item != null), isTrue);
            expect(
              work.dimensions.map((item) => item.baselineOffset).toSet().length,
              1,
            );
            raw.releaseProvisional();
            finalParent = fixture.parent(60, work.dimensions);
            while (!work.isVerified) {
              expect(
                work.verifyRows(finalParent.layout.lines, maxParts: quantum),
                inInclusiveRange(1, quantum),
              );
            }
          }
          final view = fixture.view(finalParent, work.targets);
          final handles = view.nativeLeases.toList();
          expect(handles.length, 203);
          final baselines = <(int, int), double>{};
          final baseBaselines = <int, double>{};
          var next = 1;
          for (var column = 0; column < 2; column++) {
            final contexts = fixture.content.resolveAtomicContexts(
              column,
              fixture.parts[column],
            );
            final row = narrow ? column : 0;
            for (var position = 0; position < contexts.length; position++) {
              final lease = handles[next++] as ForumBodyTextLease;
              final window = contexts[position];
              final visible = view
                  .selectionBoxes(
                    window.startUtf16,
                    window.endUtf16,
                    clipToView: false,
                  )
                  .first
                  .toRect();
              final local = lease.layout
                  .selectionBoxes(0, lease.content.projection.text.length)
                  .first
                  .toRect();
              final baseline =
                  visible.top - local.top + lease.layout.alphabeticBaseline;
              if (position == 0) {
                if (baseBaselines.containsKey(row)) {
                  expect(baseline, closeTo(baseBaselines[row]!, 1e-4));
                } else {
                  baseBaselines[row] = baseline;
                }
              } else {
                final key = (row, position - 1);
                if (baselines.containsKey(key)) {
                  expect(baseline, closeTo(baselines[key]!, 1e-4));
                } else {
                  baselines[key] = baseline;
                }
              }
              expect(visible.top, greaterThanOrEqualTo(-1e-4));
              expect(visible.bottom, lessThanOrEqualTo(view.height + 1e-4));
            }
          }
          expect(baselines[(0, 2)], lessThan(baselines[(0, 0)]!));
          expect(baselines[(0, 3)], greaterThan(baselines[(0, 1)]!));
          view.close();
          expect(fixture.cache.activeLeases, 0);
        },
      );
    }
  }

  test('already aligned 100-rank columns need only the final parent shape', () {
    final fixture = RubyRowFixture(equalColumns: true);
    addTearDown(fixture.close);
    final builds = fixture.cache.layoutBuildCount;
    final work = _alignment(fixture);
    _advance(work, fixture, 1);
    expect(work.isComplete, isTrue);
    expect(work.needsRows, isFalse);
    expect(work.hasChanges, isFalse);
    expect(work.targets, [null, null]);
    expect(fixture.cache.layoutBuildCount, builds);
    final parent = fixture.parent(60, work.dimensions);
    expect(fixture.cache.layoutBuildCount, builds + 1);
    fixture.view(parent, work.targets).close();
    expect(fixture.cache.activeLeases, 0);
  });

  test('final parent membership is rechecked against actual changed rows', () {
    final fixture = RubyRowFixture();
    addTearDown(fixture.close);
    final work = _alignment(fixture);
    _advance(work, fixture, 7);
    final raw = fixture.parent(60);
    work.attachRows(raw.layout.lines);
    _advance(work, fixture, 7);
    raw.releaseProvisional();
    final wrong = fixture.parent(30, work.dimensions);
    expect(
      () => work.verifyRows(wrong.layout.lines, maxParts: 7),
      throwsA(
        isA<ForumBodyParagraphLayoutException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyParagraphLayoutFailure.coverage,
        ),
      ),
    );
    expect(work.isVerified, isFalse);
  });

  for (final direction in ['ltr', 'rtl']) {
    test(
      'tight line height and scaled $direction 100-rank glyphs retain aligned native bounds',
      () {
        final fixture = RubyRowFixture(
          lineHeight: .25,
          textScaler: TextScaler.linear(1.27),
          direction: direction,
        );
        addTearDown(fixture.close);
        final work = _alignment(fixture);
        _advance(work, fixture, 7);
        final raw = fixture.parent(80);
        expect(raw.layout.lines.length, 1);
        work.attachRows(raw.layout.lines);
        _advance(work, fixture, 7);
        raw.releaseProvisional();
        final parent = fixture.parent(80, work.dimensions);
        while (!work.isVerified) {
          work.verifyRows(parent.layout.lines, maxParts: 7);
        }
        final view = fixture.view(parent, work.targets);
        final handles = view.nativeLeases.toList();
        for (var rank = 0; rank < 100; rank++) {
          final baselines = <double>[];
          for (var column = 0; column < 2; column++) {
            final part = fixture.parts[column][rank + 1];
            final window = fixture.content.contexts.singleWhere(
              (context) => identical(context.content, part),
            );
            final box = view
                .selectionBoxes(
                  window.startUtf16,
                  window.endUtf16,
                  clipToView: false,
                )
                .first
                .toRect();
            final lease =
                handles[2 + column * 101 + rank] as ForumBodyTextLease;
            final local = lease.layout
                .selectionBoxes(0, lease.content.projection.text.length)
                .first
                .toRect();
            baselines.add(
              box.top - local.top + lease.layout.alphabeticBaseline,
            );
            expect(box.top, greaterThanOrEqualTo(-1e-4));
            expect(box.bottom, lessThanOrEqualTo(view.height + 1e-4));
          }
          expect(baselines.first, closeTo(baselines.last, 1e-4));
        }
        view.close();
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  test(
    'missing second-column ranks retain whole level topology and shared outer offsets',
    () {
      final fixture = RubyRowFixture(missingSecond: true);
      addTearDown(fixture.close);
      final work = _alignment(fixture);
      _advance(work, fixture, 7);
      final raw = fixture.parent(60);
      work.attachRows(raw.layout.lines);
      _advance(work, fixture, 7);
      expect(work.hasChanges, isTrue);
      expect(work.targets[1]!.annotations.length, 100);
      raw.releaseProvisional();
      final parent = fixture.parent(60, work.dimensions);
      final view = fixture.view(parent, work.targets);
      expect(view.nativeLeases.length, 109);
      for (final rank in [0, 17, 34, 51, 68, 85]) {
        final part = fixture.parts[1][rank + 1];
        final window = fixture.content.contexts.singleWhere(
          (context) => identical(context.content, part),
        );
        expect(
          view.selectionBoxes(window.startUtf16, window.endUtf16),
          isNotEmpty,
        );
      }
      view.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'separate root identities do not request a shared row or pad each other',
    () {
      final fixture = RubyRowFixture();
      addTearDown(fixture.close);
      final work = _alignment(fixture, ids: [0, 1]);
      _advance(work, fixture, 7);
      expect(work.isComplete, isTrue);
      expect(work.needsRows, isFalse);
      expect(work.hasChanges, isFalse);
      expect(
        work.dimensions,
        fixture.metrics.map((item) => item.placeholderDimensions),
      );
      expect(work.targets, [null, null]);
    },
  );

  test('different ordered side topology never shares a numeric union', () {
    final fixture = RubyRowFixture();
    final other = RubyRowFixture(flipLastSide: true);
    addTearDown(fixture.close);
    addTearDown(other.close);
    final work = ForumBodyRubyRowAlignment(
      columns: [fixture.metrics[0], other.metrics[1]],
      levelIds: [0, 0],
      atomOffsets: [0, 1],
    );
    _advance(work, fixture, 7);
    expect(work.isComplete, isTrue);
    expect(work.needsRows, isFalse);
    expect(work.targets, [null, null]);
  });

  test(
    'caller list mutation between quanta cannot replace the current numeric inputs',
    () {
      final fixture = RubyRowFixture();
      addTearDown(fixture.close);
      final columns = fixture.metrics.toList();
      final ids = [0, 0];
      final offsets = [0, 1];
      final work = ForumBodyRubyRowAlignment(
        columns: columns,
        levelIds: ids,
        atomOffsets: offsets,
      );
      work.advance(maxParts: 1);
      columns.clear();
      ids.clear();
      offsets.clear();
      _advance(work, fixture, 7);
      expect(work.needsRows, isTrue);
      expect(work.columns.length, 2);
      expect(work.levelIds, [0, 0]);
      expect(work.atomOffsets, [0, 1]);
    },
  );

  test(
    'union snapshots are immutable and cannot publish a partial next column',
    () {
      final fixture = RubyRowFixture();
      addTearDown(fixture.close);
      final union = ForumBodyRubyLevelUnion();
      final first = union.merge(fixture.metrics[0]);
      expect(first.advance(maxParts: 1), 1);
      expect(() => union.value, throwsStateError);
      expect(() => union.merge(fixture.metrics[1]), throwsStateError);
      while (!first.isComplete) {
        expect(first.advance(maxParts: 7), inInclusiveRange(1, 7));
      }
      final before = union.value;
      final beforeAscent = before.annotations[0].ascent;
      final second = union.merge(fixture.metrics[1]);
      expect(second.advance(maxParts: 7), 7);
      expect(() => union.value, throwsStateError);
      while (!second.isComplete) {
        second.advance(maxParts: 7);
      }
      final after = union.value;
      expect(before.annotations[0].ascent, beforeAscent);
      expect(after.annotations[0].ascent, greaterThan(beforeAscent));
      expect(() => before.annotations.clear(), throwsUnsupportedError);
    },
  );

  test(
    'an early changed rank cannot hide a later incompatible target side',
    () {
      final fixture = RubyRowFixture();
      final wrong = RubyRowFixture(flipLastSide: true);
      addTearDown(fixture.close);
      addTearDown(wrong.close);
      final level = ForumBodyRubyLevelMetrics.single(
        wrong.metrics[0],
      ).include(wrong.metrics[1]);
      final work = ForumBodyRubyColumnAlignment(
        column: fixture.metrics[0],
        level: level,
      );
      for (var i = 0; i < 99; i++) {
        expect(work.advance(maxParts: 1), 1);
        expect(work.isComplete, isFalse);
      }
      expect(
        () => work.advance(maxParts: 1),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => fixture.metrics[0].needsLevelAlignment(level),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
    },
  );

  test(
    'pure row work continues after native owner retirement without borrowing or retaining handles',
    () {
      final fixture = RubyRowFixture();
      final work = _alignment(fixture);
      final parent = fixture.parent(60);
      final rows = parent.layout.lines;
      fixture.close();
      _advance(work, fixture, 1);
      expect(work.needsRows, isTrue);
      work.attachRows(rows);
      _advance(work, fixture, 1);
      expect(work.isComplete, isTrue);
      expect(work.hasChanges, isTrue);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
    },
  );
}
