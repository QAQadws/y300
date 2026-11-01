import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';

import 'test_support/ruby_segment_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final dense in [false, true]) {
      test(
        'actual spanning native metrics bound all numeric work q=$q dense=$dense',
        () {
          final fixture = RubySegmentFixture(dense: dense);
          addTearDown(fixture.close);
          final job = fixture.work();
          expect(() => job.result, throwsStateError);
          var calls = 0;
          while (!job.isComplete && calls++ < 20000) {
            final before = (
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
              fixture.cache.activeLeases,
            );
            expect(job.advance(maxParts: q), inInclusiveRange(1, q));
            expect((
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
              fixture.cache.activeLeases,
            ), before);
          }
          expect(job.isComplete, isTrue);
          final result = job.result;
          expect(result.size.width, dense ? 50 : 100);
          final expectedHeight = dense
              ? fixture.annotations.fold<double>(30, (height, content) {
                  final native = fixture.lease(content).layout;
                  final bounds = native
                      .selectionBoxes(0, content.projection.text.length)
                      .fold(
                        Rect.fromLTWH(0, 0, native.width, native.height),
                        (rect, box) => rect.expandToInclude(box.toRect()),
                      );
                  return height + bounds.height;
                })
              : 63.0;
          expect(result.size.height, closeTo(expectedHeight, 1e-4));
          expect(result.columnWidths, dense ? [20, 30] : [45, 55]);
          expect(result.spans.length, dense ? 100 : 4);
          for (final span in result.spans) {
            expect(
              span.width,
              greaterThanOrEqualTo(span.metrics.bounds.width - 1e-4),
            );
            expect(
              span.metrics.bounds.shift(span.offset).top,
              greaterThanOrEqualTo(-1e-4),
            );
            expect(
              span.metrics.bounds.shift(span.offset).bottom,
              lessThanOrEqualTo(result.size.height + 1e-4),
            );
          }
          expect(() => result.columnWidths.clear(), throwsUnsupportedError);
          expect(() => result.spans.clear(), throwsUnsupportedError);
          expect(() => job.advance(maxParts: q), throwsStateError);
          fixture.close();
          expect(fixture.cache.activeLeases, 0);
          expect(fixture.cache.estimatedRetainedBytes, 0);
          expect(result.size.width, dense ? 50 : 100);
        },
      );
    }
  }

  test(
    'wider spans distribute only their deficits and keep original source order',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final spans = [
        fixture.measured[2],
        fixture.measured[0],
        fixture.measured[1],
        fixture.measured[3],
      ];
      final work = fixture.work(spans: spans);
      while (!work.isComplete) {
        work.advance(maxParts: 1);
      }
      expect(work.result.columnWidths, [45, 55]);
      expect(work.result.spans.map((span) => span.input), spans);
    },
  );

  test(
    'shorter span constraints run before longer spans without sorting source members',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      // Two actual native words: widths100 and40. The shorter constraint grows
      // column0 first, then the full-width constraint shares only its deficit.
      final full = fixture.measured[2];
      final small = fixture.measured[3];
      final spans = [
        full,
        ForumBodyRubyMeasuredSpan(
          startColumn: 0,
          endColumn: 1,
          annotationIndex: small.annotationIndex,
          annotation: small.annotation,
        ),
      ];
      final work = fixture.work(spans: spans);
      while (!work.isComplete) {
        work.advance(maxParts: 7);
      }
      expect(work.result.columnWidths, [55, 45]); // 40+30 -> add15 to each.
      expect(work.result.spans.map((span) => span.input), spans);
    },
  );

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    test(
      'logical columns retain identity through physical $direction placement',
      () {
        final fixture = RubySegmentFixture(direction: direction);
        addTearDown(fixture.close);
        final result = fixture.compose();
        expect(
          result.columnLefts,
          direction == TextDirection.ltr ? [0, 45] : [55, 0],
        );
        expect(
          result.columnOffsets.map((offset) => offset.dx),
          direction == TextDirection.ltr ? [12.5, 57.5] : [67.5, 12.5],
        );
        expect(result.spans[2].left, 0);
        expect(result.spans[2].width, 100);
      },
    );
  }

  for (var bad = 0; bad < 4; bad++) {
    test(
      'invalid span topology or overflow cannot publish partial geometry, mode=$bad',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final own = fixture.measured[2];
        final work = fixture.work(
          maxWidth: bad == 3 ? 99 : 16384,
          spans: bad == 3
              ? null
              : [
                  ForumBodyRubyMeasuredSpan(
                    startColumn: bad == 0 ? -1 : 0,
                    endColumn: 2,
                    annotationIndex: bad == 1 ? 1000 : own.annotationIndex,
                    annotation: own.annotation,
                  ),
                  if (bad == 2) own,
                ],
        );
        expect(() {
          while (!work.isComplete) {
            work.advance(maxParts: 7);
          }
        }, throwsA(isA<ForumBodyRubyGroupException>()));
        expect(() => work.result, throwsStateError);
        expect(() => work.advance(maxParts: 7), throwsStateError);
        expect(fixture.cache.pictureBuildCount, 0);
      },
    );
  }

  test(
    'numeric input snapshots survive caller list mutation and owner retirement',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final columns = fixture.rawColumns.toList();
      final spans = fixture.measured.toList();
      final work = ForumBodyRubySegmentComposition(
        columns: columns,
        spans: spans,
      );
      work.advance(maxParts: 1);
      columns.clear();
      spans.clear();
      fixture.close();
      while (!work.isComplete) {
        work.advance(maxParts: 1);
      }
      expect(work.result.size.width, 100);
      expect(work.result.size.height, closeTo(63, 1e-4));
      expect(fixture.cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'a spanning annotation cannot overlap an actual column annotation at the same rank',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final own = fixture.annotations.first;
      final occupied = ForumBodyRubyGroupMetrics.measureLayers(
        cache: fixture.cache,
        baseLease: fixture.lease(fixture.bases.first),
        annotations: [
          for (final (rank, side) in fixture.sides.indexed)
            (
              content: rank == 0 ? own : fixture.empty,
              lease: rank == 0 ? fixture.lease(own) : null,
              gap: 0.0,
              side: side,
            ),
        ],
      );
      final work = ForumBodyRubySegmentComposition(
        columns: [occupied, fixture.rawColumns.last],
        spans: fixture.measured,
      );
      expect(() {
        while (!work.isComplete) {
          work.advance(maxParts: 1);
        }
      }, throwsA(isA<ForumBodyRubyGroupException>()));
      expect(() => work.result, throwsStateError);
      expect(fixture.cache.pictureBuildCount, 0);
    },
  );
}
