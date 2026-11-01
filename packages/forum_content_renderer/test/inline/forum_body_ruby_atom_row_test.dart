import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart'
    show ForumBodyRubyLevelUnion, ForumBodyRubySegmentAlignment;
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';

import '../pagination/test_support/ruby_atom_page_fixture.dart';
import 'test_support/ruby_row_fixture.dart';
import 'test_support/ruby_segment_fixture.dart';

void _drive(ForumBodyRubyRowAlignment work, int q) {
  for (var i = 0; !work.isComplete && !work.needsRows && i < 30000; i++) {
    expect(work.advance(maxParts: q), inInclusiveRange(1, q));
  }
  expect(work.isComplete || work.needsRows, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final direction in TextDirection.values) {
      test(
        'span-only font extents and original horizontal rectangles survive row target q=$q $direction',
        () {
          final source = RubySegmentFixture(dense: true, direction: direction);
          final larger = RubySegmentFixture(
            dense: true,
            direction: direction,
            textScaler: TextScaler.linear(1.27),
          );
          addTearDown(source.close);
          addTearDown(larger.close);
          final raw = source.compose();
          final big = larger.compose();
          expect(raw.columns.every((c) => !c.hasAnnotation), isTrue);
          expect(raw.level.annotations.every((a) => a.hasAnnotation), isTrue);
          final union = ForumBodyRubyLevelUnion();
          for (final input in [raw.level, big.level]) {
            final merge = union.mergeLevel(input);
            expect(() => union.value, throwsStateError);
            var units = 0;
            while (!merge.isComplete) {
              final count = merge.advance(maxParts: q);
              expect(count, inInclusiveRange(1, q));
              units += count;
            }
            expect(units, 101);
          }
          final target = union.value;
          for (var rank = 0; rank < 100; rank++) {
            expect(
              target.annotations[rank].ascent,
              big.level.annotations[rank].ascent,
            );
            expect(
              target.annotations[rank].descent,
              big.level.annotations[rank].descent,
            );
          }
          final before = (
            source.cache.layoutBuildCount,
            source.cache.pictureBuildCount,
          );
          source.close();
          larger.close();
          final job = ForumBodyRubySegmentAlignment(
            segment: raw,
            level: target,
            prepareResult: true,
          );
          expect(() => job.result, throwsStateError);
          for (var i = 0; !job.isComplete && i < 30000; i++) {
            expect(job.advance(maxParts: q), inInclusiveRange(1, q));
          }
          expect(job.isComplete, isTrue);
          expect(job.hasChanges, isTrue);
          final aligned = job.result;
          expect(aligned.size.width, raw.size.width);
          expect(aligned.size.height, big.size.height);
          expect(aligned.baseline, big.baseline);
          expect(aligned.columnWidths, raw.columnWidths);
          expect(aligned.columnLefts, raw.columnLefts);
          expect(aligned.columnOffsets, raw.columnOffsets);
          for (final (i, span) in aligned.spans.indexed) {
            expect(identical(span.input, raw.spans[i].input), isTrue);
            expect(
              (span.left, span.width, span.offset.dx),
              (raw.spans[i].left, raw.spans[i].width, raw.spans[i].offset.dx),
            );
            final baseline =
                span.metrics.fontBaseline + span.offset.dy - aligned.baseline;
            final other = big.spans[i];
            expect(
              baseline,
              closeTo(
                other.metrics.fontBaseline + other.offset.dy - big.baseline,
                1e-4,
              ),
            );
          }
          expect(aligned.needsLevelAlignment(target), isFalse);
          expect(
            aligned.alignedTo(target).columnOffsets,
            aligned.columnOffsets,
          );
          expect(() => aligned.columnWidths.clear(), throwsUnsupportedError);
          expect(() => aligned.columns.clear(), throwsUnsupportedError);
          expect(() => aligned.spans.clear(), throwsUnsupportedError);
          expect(() => job.advance(maxParts: q), throwsStateError);
          expect((
            source.cache.layoutBuildCount,
            source.cache.pictureBuildCount,
          ), before);
          expect(source.cache.activeLeases, 0);
          expect(source.cache.estimatedRetainedBytes, 0);
        },
      );
    }

    for (final narrow in [false, true]) {
      test(
        'one actual root uses Column plus one-column component through physical rows and cold Page q=$q narrow=$narrow',
        () {
          // These are the two original explicit columns of ONE root, not a wide
          // span duplicated as a neighbour. Wide spans are tested separately.
          final source = RubyRowFixture(textScaler: TextScaler.linear(1.27));
          addTearDown(source.close);
          final request = source.columns[1];
          final segmentRequest = ForumBodyRubySegmentRequest(
            bases: [request.base],
            sides: request.annotations.map((a) => a.side).toList(),
            spans: [
              for (final (rank, a) in request.annotations.indexed)
                (
                  request: a.request,
                  startColumn: 0,
                  endColumn: 1,
                  annotationIndex: rank,
                  gap: a.gap,
                ),
            ],
          );
          final planning = ForumBodyRubySegmentMetricsPreparation(
            cache: source.cache,
            request: segmentRequest,
            ensureOwner: () {},
            textScaler: source.textScaler,
          );
          addTearDown(planning.close);
          while (!planning.isReady) {
            final step = planning.advance(maxParts: q);
            expect(step.formatUnitsPrepared, lessThanOrEqualTo(q));
            expect(step.layoutsBuilt, lessThanOrEqualTo(1));
            expect(step.picturesBuilt, 0);
          }
          final segment = planning.takeMetrics();
          final work = ForumBodyRubyRowAlignment.atoms(
            atoms: [
              ForumBodyRubyAtomMetrics.column(source.metrics[0]),
              ForumBodyRubyAtomMetrics.segment(segment),
            ],
            // Actual fixture has exactly one parsed root.
            levelIds: [0, 0],
            atomOffsets: source.content.projection.atoms
                .map((a) => a.engineUtf16)
                .toList(),
          );
          expect(() => work.results, throwsStateError);
          expect(() => work.columns, throwsStateError);
          final nativeBefore = (
            source.cache.layoutBuildCount,
            source.cache.pictureBuildCount,
          );
          _drive(work, q);
          expect(work.needsRows, isTrue);
          final width = narrow ? 45.0 : 100.0;
          final provisional = source.parent(width, work.dimensions);
          expect(provisional.layout.lines.length, narrow ? 2 : 1);
          work.attachRows(provisional.layout.lines);
          _drive(work, q);
          expect(work.isComplete, isTrue);
          expect(work.hasChanges, !narrow);
          expect(source.cache.pictureBuildCount, nativeBefore.$2);
          expect(source.cache.layoutBuildCount, nativeBefore.$1 + 1);
          provisional.releaseProvisional();
          final finalParent = source.parent(width, work.dimensions);
          if (!narrow) {
            while (!work.isVerified) {
              expect(
                work.verifyRows(finalParent.layout.lines, maxParts: q),
                inInclusiveRange(1, q),
              );
            }
            expect(
              work.dimensions[0].baselineOffset,
              work.dimensions[1].baselineOffset,
            );
          } else {
            expect(work.targets, [null, null]);
            expect(
              identical(
                (work.results[1] as ForumBodyRubyComponentMetrics).value,
                segment,
              ),
              isTrue,
            );
          }
          finalParent.releaseProvisional();
          expect(() => work.results.clear(), throwsUnsupportedError);
          final aligned =
              (work.results[1] as ForumBodyRubyComponentMetrics).value;
          expect(aligned.columnWidths, segment.columnWidths);
          final input = ForumBodyInlinePageContent.atoms(
            content: source.content,
            dimensions: work.dimensions,
            rubyAtoms: [
              ForumBodyRubyAtomPlan.column(
                request: source.columns[0],
                level: work.targets[0],
              ),
              ForumBodyRubyAtomPlan.segment(
                request: segmentRequest,
                metrics: aligned,
              ),
            ],
          );
          final page = RubyAtomPageFixture.compose(
            input: input,
            planning: source.cache,
            width: width,
            height: 1000,
            textScaler: source.textScaler,
            entries: 5,
          );
          addTearDown(page.close);
          final visible = page.open(0);
          page.finish(visible, q: q);
          final fragment =
              visible.takeFragments().single as ForumBodyPreparedInlineFragment;
          expect(fragment.nativeLeases.length, 203);
          expect(page.cache.pictureBuildCount, 202);
          final baselines = <(int, int), double>{};
          for (final (column, parts) in source.parts.indexed) {
            for (final (rank, part) in parts.indexed) {
              final window = source.content.contexts.singleWhere(
                (c) => identical(c.content, part),
              );
              final box = fragment
                  .glyphBoxes(window.startUtf16, window.startUtf16 + 1)
                  .first;
              expect(
                fragment.view
                    .sourceAt(
                      Offset(box.left + .001, (box.top + box.bottom) / 2),
                    )
                    .sourceRune,
                part.projection.sourceAtUtf16(0).sourceRune,
              );
              final native = fragment.nativeLeases
                  .whereType<ForumBodyTextLease>()
                  .singleWhere((l) => identical(l.content, part));
              final local = native.layout.selectionBoxes(0, 1).first.toRect();
              final key = (narrow ? column : 0, rank);
              final baseline =
                  box.top - local.top + native.layout.alphabeticBaseline;
              if (baselines.containsKey(key)) {
                expect(baseline, closeTo(baselines[key]!, 1e-4));
              } else {
                baselines[key] = baseline;
              }
            }
          }
          fragment.close();
          page.close();
          expect(page.cache.activeLeases, 0);
          expect(page.cache.estimatedRetainedBytes, 0);
        },
      );
    }
  }

  test(
    'segment validates late rank even after an earlier actual baseline shift',
    () {
      final source = RubySegmentFixture(dense: true);
      final wrong = RubyRowFixture(
        flipLastSide: true,
        textScaler: TextScaler.linear(1.27),
      );
      addTearDown(source.close);
      addTearDown(wrong.close);
      final raw = source.compose();
      final target = ForumBodyRubyLevelMetrics.single(
        wrong.metrics[0],
      ).include(wrong.metrics[1]);
      final check = ForumBodyRubySegmentAlignment(segment: raw, level: target);
      for (var rank = 0; rank < 99; rank++) {
        expect(check.advance(maxParts: 1), 1);
        expect(check.isComplete, isFalse);
      }
      expect(
        () => check.advance(maxParts: 1),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => raw.needsLevelAlignment(target),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
    },
  );

  for (final direction in TextDirection.values) {
    test(
      'original wide spans remain readable after a larger numeric level target $direction',
      () {
        final source = RubySegmentFixture(direction: direction);
        final other = RubySegmentFixture(
          direction: direction,
          textScaler: TextScaler.linear(1.27),
        );
        addTearDown(source.close);
        addTearDown(other.close);
        final raw = source.compose();
        final target = other.compose().level;
        final aligned = raw.alignedTo(target);
        final layout = source.prepare(aligned);
        expect(layout.metrics.columnWidths, raw.columnWidths);
        expect(layout.nativeLeases.length, 6);
        for (final (i, part) in source.annotations.indexed) {
          final boxes = layout.selectionBoxesForSpan(
            spanIndex: i,
            startUtf16: 0,
            endUtf16: part.projection.text.length,
          );
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            expect(box.top, greaterThanOrEqualTo(-1e-4));
            expect(box.bottom, lessThanOrEqualTo(aligned.size.height + 1e-4));
          }
        }
        layout.close();
        expect(source.cache.activeLeases, 0);
      },
    );
  }
}
