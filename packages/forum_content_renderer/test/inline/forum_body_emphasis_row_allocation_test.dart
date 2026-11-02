import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/emphasis_allocation_fixture.dart';

typedef _Context = EmphasisAllocationFixture;
typedef _Row = EmphasisAllocationRowFixture;

class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyEmphasisRowAllocation _finish(
  ForumBodyEmphasisRowAllocationPreparation j,
) {
  addTearDown(j.close);
  for (var n = 0; !j.isReady && n < 20000; n++) {
    expect(j.advance(maxParts: 1), 1);
  }
  expect(j.isReady, isTrue);
  expect(j.advance(maxParts: 4), 0);
  return j.takeAllocation();
}

void _contained(Rect box, double top, double bottom) {
  // Arithmetic on the frozen double coordinates, not a pixel comparison.
  expect(box.top, greaterThanOrEqualTo(top - 1e-8));
  expect(box.bottom, lessThanOrEqualTo(bottom + 1e-8));
}

void _verify(_Context c, _Row original, ForumBodyEmphasisRowAllocation plan) {
  expect(plan.source, same(original.metrics));
  expect(plan.reference, same(c.reference));
  expect(plan.rows.length, original.view.metrics.lineCount);
  expect(plan.marks.length, original.metrics.marks.length);
  expect(plan.width, original.metrics.width);
  expect(plan.alphabeticBaseline, plan.rows.first.alphabeticBaseline);
  expect(() => plan.rows.clear(), throwsUnsupportedError);
  expect(() => plan.marks.clear(), throwsUnsupportedError);
  var end = 0.0;
  for (var i = 0; i < plan.rows.length; i++) {
    final row = plan.rows[i], absolute = original.view.selector.startLine + i;
    expect(row.flowTop, end);
    expect(row.flowBottom, greaterThanOrEqualTo(row.flowTop));
    final natural = c.naturalFrames.frames[absolute];
    expect(
      row.flowBottom - row.flowTop,
      greaterThanOrEqualTo(natural.flowBottom - natural.flowTop - 1e-8),
    );
    _contained(row.fontBounds, row.flowTop, row.flowBottom);
    _contained(row.bounds, row.flowTop, row.flowBottom);
    expect(row.physicalLine, same(original.physical[i]));
    expect(row.logicalOffset.dx, original.metrics.baseOffset.dx);
    end = row.flowBottom;
  }
  expect(plan.height, end);
  _contained(plan.fontBounds, 0, plan.height);
  for (var i = 0; i < plan.marks.length; i++) {
    final placed = plan.marks[i],
        source = original.metrics.marks[i],
        row = plan.rows[source.lineIndex];
    expect(placed.markIndex, i);
    expect(placed.offset.dx, source.offset.dx);
    expect(placed.fontBounds.size, source.fontBounds.size);
    _contained(placed.fontBounds, row.flowTop, row.flowBottom);
    expect(
      placed.offset.dy - source.offset.dy,
      closeTo(row.sourceTranslationY, 1e-8),
    );
  }
}

Matcher _failure(ForumBodyEmphasisAllocationFailure failure) => throwsA(
  isA<ForumBodyEmphasisAllocationException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final leading in [0, 400]) {
      final bytes = await File(
        'test/fixtures/fonts/leading_$leading.ttf',
      ).readAsBytes();
      await (FontLoader(
        'ForumBodyLeading$leading',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
      for (final width in [1.0, 140.0]) {
        for (final height in ['.4', '1.6', '37px']) {
          test(
            'allocate real complete groups $direction/$scaler/$width/$height',
            () {
              final c = _Context(
                direction: direction,
                scaler: scaler,
                width: width,
                height: height,
              );
              var start = 0, spanning = 0;
              final covered = StringBuffer();
              while (start < c.isolated.layout.lineCount) {
                final original = c.row(start);
                final before = (
                  c.cache.layoutBuildCount,
                  c.cache.pictureBuildCount,
                  c.cache.activeLeases,
                  c.cache.hitCount,
                );
                final plan = _finish(c.prepare(original));
                expect((
                  c.cache.layoutBuildCount,
                  c.cache.pictureBuildCount,
                  c.cache.activeLeases,
                  c.cache.hitCount,
                ), before);
                _verify(c, original, plan);
                covered.write(original.view.projection.text);
                if (plan.rows.length > 1) {
                  spanning++;
                  expect(plan.height, lessThan(original.metrics.height));
                }
                start = original.view.selector.endLine;
              }
              expect(covered.toString(), c.glyphs.glyphs.projection.text);
              if (width == 1) expect(spanning, greaterThan(0));
            },
          );
        }
      }
    }
  }
  for (final leading in [0, 400]) {
    for (final height in ['normal', '.4', '1.6', '37px']) {
      for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
        test('allocate native font leading$leading/$height/$scaler', () {
          final c = _Context(
            body: 'AB CD <span style="font-size:31px">EF GH IJ</span> KL MN',
            font: 'ForumBodyLeading$leading',
            height: height,
            scaler: scaler,
          );
          for (var start = 0; start < c.isolated.layout.lineCount;) {
            final row = c.row(start), plan = _finish(c.prepare(row));
            _verify(c, row, plan);
            start = row.view.selector.endLine;
          }
        });
      }
    }
  }
  test(
    'long uniform paragraphs keep fractional final baselines without one-pixel jumps',
    () {
      final c = _Context(
        body: List.filled(2048, 'AB\n').join(),
        height: '1',
        size: 20.62499,
        font: 'ForumBodyLeading0',
        emphasis: false,
      );
      expect(c.reference.lineCount, 2049);
      expect(c.isolatedFrames.height, 524544);
      final baselines = <double>[];
      for (final start in [0, 13, 100, 1000, 2047]) {
        final row = c.row(start), plan = _finish(c.prepare(row));
        _verify(c, row, plan);
        baselines.add(plan.alphabeticBaseline);
        expect(plan.height, closeTo(21, .001));
      }
      expect(baselines.every((b) => b > 16.49 && b < 16.51), isTrue);
      expect(
        baselines.reduce((a, b) => a > b ? a : b) -
            baselines.reduce((a, b) => a < b ? a : b),
        lessThan(.001),
      );
    },
  );
  test(
    'allocation snapshots survive native disposal with intact source groups',
    () {
      final c = _Context(width: 1), row = c.row(2);
      final job = c.prepare(row);
      c.cache.close();
      final plan = _finish(job);
      expect(plan.source, same(row.metrics));
      expect(plan.rows, isNotEmpty);
      expect(c.cache.activeLeases, 0);
    },
  );
  test(
    'budgets, source tables and selector order fail without consuming caller leases',
    () {
      final c = _Context(body: 'e<b style="font-size:31px">́</b>', width: 1),
          row = c.row(0);
      expect(row.physical.length, greaterThan(1));
      expect(
        () => c.prepare(row, maxLines: 1),
        _failure(ForumBodyEmphasisAllocationFailure.limit),
      );
      expect(
        () => c.prepare(row, maxMarks: 0),
        _failure(ForumBodyEmphasisAllocationFailure.limit),
      );
      expect(
        () => _finish(c.prepare(row, maxHeight: 1)),
        _failure(ForumBodyEmphasisAllocationFailure.limit),
      );
      expect(
        () => _finish(c.prepare(row, physical: row.physical.reversed.toList())),
        _failure(ForumBodyEmphasisAllocationFailure.source),
      );
      final other = _Context(
        body: 'e<b style="font-size:31px">́</b>',
        width: 1,
      );
      expect(
        () => c.prepare(row, naturalTable: other.naturalFrames),
        _failure(ForumBodyEmphasisAllocationFailure.source),
      );
      final early = c.prepare(row);
      expect(early.takeAllocation, throwsStateError);
      expect(c.cache.activeLeases, 2);
    },
  );
  for (final retirement in ['generation', 'close', 'reentry']) {
    test('ready allocation $retirement cannot publish late output', () {
      final c = _Context(), row = c.row(0);
      void Function()? callback;
      final job = c.prepare(row, owner: () => callback?.call());
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      switch (retirement) {
        case 'generation':
          callback = () => throw StateError('generation');
        case 'close':
          callback = job.close;
        case 'reentry':
          callback = () => job.advance(maxParts: 1);
      }
      expect(job.takeAllocation, throwsStateError);
      expect(job.isReady, isFalse);
      expect(c.cache.activeLeases, 2);
    });
  }
}
