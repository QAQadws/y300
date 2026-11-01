import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_segment_fixture.dart';

Future<List<int>> _pixels(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(400, 300);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Independent native painters and a direct small-grid reference; does not use
/// production segment/column dimensions, baselines or positioned span output.
Future<List<int>> _reference(RubySegmentFixture fixture) async {
  final contents = [...fixture.bases, ...fixture.annotations];
  final painters = [
    for (final content in contents)
      TextPainter(
        text: content.textSpan,
        textDirection: content.style.textDirection,
        textScaler: fixture.textScaler,
      )..layout(),
  ];
  try {
    final bounds = [
      for (var i = 0; i < painters.length; i++)
        painters[i]
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: contents[i].projection.text.length,
              ),
            )
            .fold(
              Rect.fromLTWH(0, 0, painters[i].width, painters[i].height),
              (rect, box) => rect.expandToInclude(box.toRect()),
            ),
    ];
    final baselines = [
      // The member contract uses the rounded physical row frame. Paragraph's
      // typographic baseline can differ with fractional, tight leading.
      for (final painter in painters)
        painter.height - painter.computeLineMetrics().single.descent,
    ];
    final widths = [bounds[0].width, bounds[1].width];
    final order = List.generate(fixture.measured.length, (i) => i)
      ..sort((a, b) {
        final x = fixture.measured[a];
        final y = fixture.measured[b];
        final length = (x.endColumn - x.startColumn).compareTo(
          y.endColumn - y.startColumn,
        );
        return length == 0 ? a.compareTo(b) : length;
      });
    for (final index in order) {
      final span = fixture.measured[index];
      final total = widths
          .sublist(span.startColumn, span.endColumn)
          .reduce((a, b) => a + b);
      final extra =
          math.max(0, bounds[index + 2].width - total) /
          (span.endColumn - span.startColumn);
      for (var i = span.startColumn; i < span.endColumn; i++) {
        widths[i] += extra;
      }
    }
    final baseAscent = math.max(
      baselines[0] - bounds[0].top,
      baselines[1] - bounds[1].top,
    );
    final baseDescent = math.max(
      bounds[0].bottom - baselines[0],
      bounds[1].bottom - baselines[1],
    );
    var over = baseAscent;
    var under = baseDescent;
    final relative = <double>[];
    for (var rank = 0; rank < fixture.sides.length; rank++) {
      var ascent = 0.0;
      var descent = 0.0;
      for (var i = 0; i < fixture.measured.length; i++) {
        if (fixture.measured[i].annotationIndex != rank) continue;
        ascent = math.max(ascent, baselines[i + 2] - bounds[i + 2].top);
        descent = math.max(descent, bounds[i + 2].bottom - baselines[i + 2]);
      }
      if (fixture.sides[rank] == ForumBodyRubySide.over) {
        relative.add(-over - descent);
        over += ascent + descent;
      } else {
        relative.add(under + ascent);
        under += ascent + descent;
      }
    }
    final prefix = [0.0, widths[0], widths[0] + widths[1]];
    final origins = <Offset>[];
    for (var col = 0; col < 2; col++) {
      final left = fixture.direction == TextDirection.ltr
          ? prefix[col]
          : prefix.last - prefix[col + 1];
      origins.add(
        Offset(
          left + (widths[col] - bounds[col].width) / 2 - bounds[col].left,
          over - baselines[col],
        ),
      );
    }
    for (var i = 0; i < fixture.measured.length; i++) {
      final span = fixture.measured[i];
      final width = prefix[span.endColumn] - prefix[span.startColumn];
      final left = fixture.direction == TextDirection.ltr
          ? prefix[span.startColumn]
          : prefix.last - prefix[span.endColumn];
      origins.add(
        Offset(
          left + (width - bounds[i + 2].width) / 2 - bounds[i + 2].left,
          over + relative[span.annotationIndex] - baselines[i + 2],
        ),
      );
    }
    return await _pixels((canvas) {
      for (var i = 0; i < painters.length; i++) {
        painters[i].paint(canvas, const Offset(20, 20) + origins[i]);
      }
    });
  } finally {
    for (final painter in painters) {
      painter.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var mode = 0; mode < 5; mode++) {
    test(
      'actual spanning columns match independent native paint/source, mode=$mode',
      () async {
        final fixture = RubySegmentFixture(
          direction: mode.isOdd ? TextDirection.rtl : TextDirection.ltr,
          position: mode == 1
              ? 'over'
              : mode == 2
              ? 'under'
              : 'alternate',
          lineHeight: mode >= 3 ? .25 : 1,
          textScaler: mode >= 3
              ? TextScaler.linear(1.27)
              : TextScaler.noScaling,
        );
        addTearDown(fixture.close);
        final metrics = fixture.compose(quantum: 1);
        final layout = fixture.prepare(metrics);
        expect(layout.nativeLeases.length, 6);
        expect(layout.isOwnedBy(fixture.cache), isTrue);
        final counters = (
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
          fixture.cache.activeLeases,
        );
        expect(
          await _pixels((canvas) => layout.paint(canvas, const Offset(20, 20))),
          await _reference(fixture),
        );
        for (var i = 0; i < fixture.annotations.length; i++) {
          final box = layout
              .selectionBoxesForSpan(spanIndex: i, startUtf16: 1, endUtf16: 2)
              .single;
          expect(box.top, greaterThanOrEqualTo(-1e-4));
          expect(box.bottom, lessThanOrEqualTo(layout.size.height + 1e-4));
          final hit = layout.sourceAt(
            Offset(box.left + .01, (box.top + box.bottom) / 2),
          );
          expect(hit.spanIndex, i);
          expect(hit.columnIndex, isNull);
          expect(hit.position.isExact, isTrue);
          expect(
            hit.position.sourceRune,
            fixture.annotations[i].projection.sourceAtUtf16(1).sourceRune,
          );
        }
        for (var col = 0; col < 2; col++) {
          final box = layout
              .selectionBoxesForColumn(
                columnIndex: col,
                part: ForumBodyRubyPart.base,
                startUtf16: 0,
                endUtf16: 1,
              )
              .single;
          final hit = layout.sourceAt(
            Offset(box.left + .01, (box.top + box.bottom) / 2),
          );
          expect(hit.columnIndex, col);
          expect(hit.spanIndex, isNull);
          expect(hit.position.sourceRune, col);
        }
        expect((
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
          fixture.cache.activeLeases,
        ), counters);
        layout.close();
        layout.close();
        expect(fixture.cache.activeLeases, 0);
        expect(layout.isActive, isFalse);
        expect(layout.nativeLeases, isEmpty);
      },
    );
  }

  test(
    '100 actual spanning annotations paint once and preserve independent base glyphs',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final layout = fixture.prepare(fixture.compose(quantum: 7));
      expect(layout.nativeLeases.length, 102);
      expect(fixture.cache.pictureBuildCount, 102);
      for (var i = 0; i < 100; i++) {
        final box = layout
            .selectionBoxesForSpan(spanIndex: i, startUtf16: 1, endUtf16: 2)
            .single;
        final hit = layout.sourceAt(
          Offset(box.left + .001, (box.top + box.bottom) / 2),
        );
        expect(hit.spanIndex, i);
        expect(hit.position.isExact, isTrue);
        expect(
          hit.position.sourceRune,
          fixture.annotations[i].projection.sourceAtUtf16(1).sourceRune,
        );
      }
      layout.close();
      fixture.close();
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'existing prepared RT columns compose with outer spanning annotations without re-shaping',
    () async {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      List<
        ({
          ForumBodyParagraphContent content,
          ForumBodyTextLease? lease,
          double gap,
          ForumBodyRubySide side,
        })
      >
      inputs(int col) => [
        for (final (rank, side) in fixture.sides.indexed)
          (
            content: rank == 0 ? fixture.annotations[col] : fixture.empty,
            lease: rank == 0 ? fixture.lease(fixture.annotations[col]) : null,
            gap: 0.0,
            side: side,
          ),
      ];
      final raw = [
        for (var col = 0; col < 2; col++)
          ForumBodyRubyGroupMetrics.measureLayers(
            cache: fixture.cache,
            baseLease: fixture.lease(fixture.bases[col]),
            annotations: inputs(col),
          ),
      ];
      final metrics = ForumBodyRubySegmentMetrics.compose(
        columns: raw,
        spans: fixture.measured.skip(2).toList(),
      );
      for (final content in [...fixture.bases, ...fixture.annotations]) {
        fixture.cache.prepareBandChildPaint(fixture.lease(content));
      }
      final columns = [
        for (var col = 0; col < 2; col++)
          ForumBodyRubyGroupLayout.adoptLayers(
            cache: fixture.cache,
            baseLease: fixture.lease(fixture.bases[col]),
            annotations: inputs(col),
            level: metrics.level,
          ),
      ];
      final layout = ForumBodyRubySegmentLayout.adopt(
        cache: fixture.cache,
        columns: columns,
        spans: [
          for (final content in fixture.annotations.skip(2))
            (content: content, lease: fixture.lease(content)),
        ],
        metrics: metrics,
      );
      try {
        expect(layout.nativeLeases.length, 6);
        expect(metrics.columnWidths, [45, 55]);
        expect(
          await _pixels((canvas) => layout.paint(canvas, const Offset(20, 20))),
          await _reference(fixture),
        );
        for (var col = 0; col < 2; col++) {
          final box = layout
              .selectionBoxesForColumn(
                columnIndex: col,
                part: ForumBodyRubyPart.annotation,
                annotationIndex: 0,
                startUtf16: 1,
                endUtf16: 2,
              )
              .single;
          final hit = layout.sourceAt(
            Offset(box.left + .01, (box.top + box.bottom) / 2),
          );
          expect(hit.columnIndex, col);
          expect(hit.columnHit!.annotationIndex, 0);
          expect(hit.position.isExact, isTrue);
          expect(
            hit.position.sourceRune,
            fixture.annotations[col].projection.sourceAtUtf16(1).sourceRune,
          );
        }
      } finally {
        layout.close();
      }
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'foreign owner rejection retires supplied members and preserves unrelated pins',
    () {
      final fixture = RubySegmentFixture();
      final other = RubySegmentFixture();
      addTearDown(fixture.close);
      addTearDown(other.close);
      final metrics = fixture.compose();
      final columns = fixture.prepareColumns(metrics);
      final unrelated = fixture.cache.acquireBandChild(
        content: ForumBodyTextBandContent(contexts: [fixture.bases.first]),
        childIndex: 0,
      );
      try {
        expect(
          () => ForumBodyRubySegmentLayout.adopt(
            cache: other.cache,
            columns: columns,
            spans: [
              for (final content in fixture.annotations)
                (content: content, lease: fixture.lease(content)),
            ],
            metrics: metrics,
          ),
          throwsStateError,
        );
        expect(unrelated.isActive, isTrue);
        expect(fixture.cache.activeLeases, 1);
      } finally {
        unrelated.release();
      }
    },
  );

  test('duplicate span handles reject and consume only supplied ownership', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final metrics = fixture.compose();
    final columns = fixture.prepareColumns(metrics);
    final first = fixture.annotations.first;
    final notSupplied = fixture.lease(fixture.annotations[1]);
    expect(
      () => ForumBodyRubySegmentLayout.adopt(
        cache: fixture.cache,
        columns: columns,
        spans: [
          (content: first, lease: fixture.lease(first)),
          (content: first, lease: fixture.lease(first)),
          for (final content in fixture.annotations.skip(2))
            (content: content, lease: fixture.lease(content)),
        ],
        metrics: metrics,
      ),
      throwsA(isA<ForumBodyRubyGroupException>()),
    );
    expect(columns.every((column) => !column.isActive), isTrue);
    expect(notSupplied.isActive, isTrue);
    expect(fixture.cache.activeLeases, 1);
  });

  test(
    'wrong column geometry or unreadable span cannot adopt numeric-only proof',
    () {
      for (final wrongGeometry in [false, true]) {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final metrics = fixture.compose();
        final columns = fixture.prepareColumns(
          metrics,
          prepareAnnotations: wrongGeometry,
        );
        expect(
          () => ForumBodyRubySegmentLayout.adopt(
            cache: fixture.cache,
            columns: wrongGeometry ? columns.reversed.toList() : columns,
            spans: [
              for (final content in fixture.annotations)
                (content: content, lease: fixture.lease(content)),
            ],
            metrics: metrics,
          ),
          wrongGeometry
              ? throwsA(isA<ForumBodyRubyGroupException>())
              : throwsStateError,
        );
        expect(fixture.cache.activeLeases, 0);
      }
    },
  );

  test(
    'reading owner retirement invalidates all segment paint and source calls',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final layout = fixture.prepare(fixture.compose());
      fixture.cache.close();
      expect(layout.isActive, isFalse);
      expect(() => layout.sourceAt(Offset.zero), throwsStateError);
      final recorder = ui.PictureRecorder();
      expect(
        () => layout.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
      layout.close();
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
    },
  );
}
