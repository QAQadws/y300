import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_segment_fixture.dart';

({
  ForumBodyInlineParagraphView view,
  ForumBodyRubySegmentLayout segment,
  ForumBodyInlineParagraphLease parent,
  Offset origin,
})
_open(
  RubySegmentFixture fixture, {
  bool onlyAtomRow = false,
  double width = 300,
  ForumBodyInlineSpanContent? content,
}) {
  final segment = fixture.prepare(fixture.compose());
  final parent = fixture.cache.acquireInline(
    content: content ?? fixture.inlineContent,
    width: width,
    dimensions: [segment.metrics.placeholderDimensions],
    textScaler: fixture.textScaler,
  );
  final atom = parent.content.projection.atoms.single;
  final row = parent.layout.lines.indexWhere(
    (line) =>
        atom.engineUtf16 >= line.engineCoverageStartUtf16 &&
        atom.engineUtf16 < line.engineCoverageEndUtf16,
  );
  final start = onlyAtomRow ? row : 0;
  final end = onlyAtomRow ? row + 1 : parent.layout.lines.length;
  final fragment = parent.layout.fragment(start, end);
  final origin =
      parent.layout.atomBoxes.single.toRect().topLeft - Offset(0, fragment.top);
  return (
    view: ForumBodyInlineParagraphView.adopt(
      cache: fixture.cache,
      parent: parent,
      startLine: start,
      endLine: end,
      rubySegments: {0: segment},
    ),
    segment: segment,
    parent: parent,
    origin: origin,
  );
}

Future<List<int>> _pixels(Size size, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(3);
  paint(canvas);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * 3 + 3).ceil(),
      (size.height * 3 + 3).ceil(),
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var mode = 0; mode < 6; mode++) {
    test(
      'real span component binds every original member into one parent atom, mode=$mode',
      () {
        final fixture = RubySegmentFixture(
          dense: mode == 4,
          direction: mode == 1 || mode == 3
              ? TextDirection.rtl
              : TextDirection.ltr,
          lineHeight: mode == 3 ? .25 : 1,
          textScaler: mode == 3
              ? const TextScaler.linear(1.27)
              : TextScaler.noScaling,
          prefix: mode == 5 ? 'P<br>Q<br>R<br>' : '',
          suffix: mode == 5 ? '<br>S<br>T' : '',
        );
        addTearDown(fixture.close);
        final result = _open(fixture, onlyAtomRow: mode == 5);
        addTearDown(result.view.close);
        final windows = fixture.inlineContent.resolveAtomicContexts(0, [
          ...fixture.bases,
          ...fixture.annotations,
        ]);
        expect(result.view.atomIndices, [0]);
        expect(result.view.nativeLeases.length, mode == 4 ? 103 : 7);
        final before = (
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
          fixture.cache.activeLeases,
        );
        for (final window in windows) {
          final from = window.content.projection.text.length == 1 ? 0 : 1;
          final boxes = result.view.selectionBoxes(
            window.startUtf16 + from,
            window.startUtf16 + from + 1,
            clipToView: false,
          );
          expect(boxes, isNotEmpty);
          final box = boxes.first.toRect();
          final point = Offset(box.left + .001, box.center.dy);
          final direct = result.segment.sourceAt(point - result.origin);
          final hit = result.view.sourceAt(point);
          expect(hit.sourceRune, direct.position.sourceRune);
          expect(
            hit.displayUtf16,
            window.startUtf16 + direct.position.displayUtf16,
          );
          expect(hit.isExact, isTrue);
          expect(box.top, greaterThanOrEqualTo(-1e-4));
          expect(box.bottom, lessThanOrEqualTo(result.view.height + 1e-4));
        }
        if (mode == 5) {
          expect(result.view.startLine, greaterThan(0));
          final clamped = result.view.sourceAt(const Offset(-10, -10));
          expect(clamped.isExact, isFalse);
          expect(
            clamped.displayUtf16,
            inInclusiveRange(
              result.view.coverageStartUtf16,
              result.view.coverageEndUtf16,
            ),
          );
        }
        final recorder = ui.PictureRecorder();
        result.view.paint(Canvas(recorder), Offset.zero);
        recorder.endRecording().dispose();
        expect((
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
          fixture.cache.activeLeases,
        ), before);
        result.view.close();
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  for (var mode = 0; mode < 3; mode++) {
    test(
      'parent view preserves direct prepared component pixels at DPR3, mode=$mode',
      () async {
        final fixture = RubySegmentFixture(
          dense: mode == 2,
          direction: mode == 1 ? TextDirection.rtl : TextDirection.ltr,
          lineHeight: mode == 1 ? .25 : 1,
          textScaler: mode == 1
              ? const TextScaler.linear(1.27)
              : TextScaler.noScaling,
        );
        addTearDown(fixture.close);
        final result = _open(fixture);
        addTearDown(result.view.close);
        final size = Size(result.view.width, result.view.height);
        final expected = await _pixels(size, (canvas) {
          canvas.clipRect(Offset.zero & size, doAntiAlias: false);
          result.parent.layout
              .fragment(0, result.parent.layout.lines.length)
              .paintParent(canvas, Offset.zero);
          result.segment.paint(canvas, result.origin);
        });
        final actual = await _pixels(
          size,
          (canvas) => result.view.paint(canvas, Offset.zero),
        );
        var different = 0;
        for (var i = 0; i < actual.length; i++) {
          if (actual[i] != expected[i]) different++;
        }
        expect(different, 0);
      },
    );
  }

  test(
    'Unicode member selections retain the actual original UTF16/source window',
    () {
      final fixture = RubySegmentFixture(
        firstBase: '😀',
        secondBase: 'é',
        outerText: 'a👩‍👩‍👧‍👦é😀z',
      );
      addTearDown(fixture.close);
      final result = _open(fixture, width: 500);
      addTearDown(result.view.close);
      final window = fixture.inlineContent.contexts.firstWhere(
        (w) => identical(w.content, fixture.annotations[2]),
      );
      final boxes = result.view.selectionBoxes(
        window.startUtf16 + 2,
        window.endUtf16 - 1,
      );
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        final point = Offset(box.left + .01, (box.top + box.bottom) / 2);
        final direct = result.segment.sourceAt(point - result.origin);
        final actual = result.view.sourceAt(point);
        expect(actual.sourceRune, direct.position.sourceRune);
        expect(
          actual.displayUtf16,
          window.startUtf16 + direct.position.displayUtf16,
        );
        expect(actual.isExact, isTrue);
      }
    },
  );

  test(
    'equal text in a stale outer context cannot bind original component members',
    () {
      final fixture = RubySegmentFixture();
      final current = RubySegmentFixture();
      addTearDown(fixture.close);
      addTearDown(current.close);
      final segment = fixture.prepare(fixture.compose());
      final parent = fixture.cache.acquireInline(
        content: current.inlineContent,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: fixture.cache,
          parent: parent,
          startLine: 0,
          endLine: parent.layout.lines.length,
          rubySegments: {0: segment},
        ),
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.identity,
          ),
        ),
      );
      expect(fixture.cache.activeLeases, 0);
      expect(current.cache.activeLeases, 6);
    },
  );

  for (final wrongDimension in [false, true]) {
    test(
      'off-input source or altered component dimensions cannot publish, size=$wrongDimension',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final segment = fixture.prepare(fixture.compose());
        final actual = fixture.inlineContent;
        final contexts = actual.contexts.map((w) => w.content).toList();
        if (!wrongDimension) contexts.removeLast();
        final content = ForumBodyInlineSpanContent.compose(
          identity: actual.identity,
          path: actual.path,
          fontRevision: actual.fontRevision,
          styleRevision: actual.styleRevision,
          style: actual.style,
          contexts: contexts,
          atomicRanges: [
            (
              startUtf16: 0,
              endUtf16: contexts.fold<int>(
                0,
                (n, c) => n + c.projection.text.length,
              ),
            ),
          ],
        );
        final dimension = segment.metrics.placeholderDimensions;
        final parent = fixture.cache.acquireInline(
          content: content,
          width: 300,
          dimensions: [
            wrongDimension
                ? PlaceholderDimensions(
                    size: dimension.size + const Offset(1, 0),
                    alignment: dimension.alignment,
                    baseline: dimension.baseline,
                    baselineOffset: dimension.baselineOffset,
                  )
                : dimension,
          ],
        );
        expect(
          () => ForumBodyInlineParagraphView.adopt(
            cache: fixture.cache,
            parent: parent,
            startLine: 0,
            endLine: parent.layout.lines.length,
            rubySegments: {0: segment},
          ),
          throwsA(
            isA<ForumBodyInlineViewException>().having(
              (e) => e.failure,
              'failure',
              wrongDimension
                  ? ForumBodyInlineViewFailure.geometry
                  : ForumBodyInlineViewFailure.identity,
            ),
          ),
        );
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  test(
    'hidden component is rejected and a visible continuation binds only its real atom row',
    () {
      final fixture = RubySegmentFixture(
        prefix: 'A<br>B<br>C<br>',
        suffix: '<br>D',
      );
      addTearDown(fixture.close);
      final segment = fixture.prepare(fixture.compose());
      final parent = fixture.cache.acquireInline(
        content: fixture.inlineContent,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      expect(parent.layout.fragment(0, 1).atomIndices, isEmpty);
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: fixture.cache,
          parent: parent,
          startLine: 0,
          endLine: 1,
          rubySegments: {0: segment},
        ),
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.coverage,
          ),
        ),
      );
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'cross-kind duplicate ownership fails and unrelated native pins survive',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final segment = fixture.prepare(fixture.compose());
      final column = segment.columnAt(0);
      final extra = fixture.cache.acquire(
        content: fixture.bases.first,
        width: 300,
      );
      addTearDown(extra.release);
      final parent = fixture.cache.acquireInline(
        content: fixture.inlineContent,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: fixture.cache,
          parent: parent,
          startLine: 0,
          endLine: parent.layout.lines.length,
          rubyGroups: {0: column},
          rubySegments: {0: segment},
        ),
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.leases,
          ),
        ),
      );
      expect(extra.isActive, isTrue);
      expect(fixture.cache.activeLeases, 1);
    },
  );

  test(
    'borrowed immutable members carry no lifetime extension or readable proof',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final result = _open(fixture);
      addTearDown(result.view.close);
      final members = result.segment.inspectMembers();
      expect(
        identical(members.columns, result.segment.inspectMembers().columns),
        isTrue,
      );
      expect(() => members.columns.clear(), throwsUnsupportedError);
      expect(() => members.spans.clear(), throwsUnsupportedError);
      fixture.cache.close();
      expect(result.view.isActive, isFalse);
      expect(() => result.view.sourceAt(Offset.zero), throwsStateError);
      expect(() => result.view.selectionBoxes(0, 1), throwsStateError);
      expect(members.columns.every((c) => !c.isActive), isTrue);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
    },
  );
  test(
    'existing column RTs and outer spans share the actual parent source order',
    () {
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
      annotations(int column) => [
        for (final (rank, side) in fixture.sides.indexed)
          (
            content: rank == 0 ? fixture.annotations[column] : fixture.empty,
            lease: rank == 0
                ? fixture.lease(fixture.annotations[column])
                : null,
            gap: 0.0,
            side: side,
          ),
      ];
      final metrics = ForumBodyRubySegmentMetrics.compose(
        columns: [
          for (var i = 0; i < 2; i++)
            ForumBodyRubyGroupMetrics.measureLayers(
              cache: fixture.cache,
              baseLease: fixture.lease(fixture.bases[i]),
              annotations: annotations(i),
            ),
        ],
        spans: fixture.measured.skip(2).toList(),
      );
      for (final content in [...fixture.bases, ...fixture.annotations]) {
        fixture.cache.prepareBandChildPaint(fixture.lease(content));
      }
      final segment = ForumBodyRubySegmentLayout.adopt(
        cache: fixture.cache,
        columns: [
          for (var i = 0; i < 2; i++)
            ForumBodyRubyGroupLayout.adoptLayers(
              cache: fixture.cache,
              baseLease: fixture.lease(fixture.bases[i]),
              annotations: annotations(i),
              level: metrics.level,
            ),
        ],
        spans: [
          for (final content in fixture.annotations.skip(2))
            (content: content, lease: fixture.lease(content)),
        ],
        metrics: metrics,
      );
      addTearDown(segment.close);
      final original = fixture.inlineContent;
      final contexts = [
        fixture.bases[0],
        fixture.annotations[0],
        fixture.bases[1],
        fixture.annotations[1],
        ...fixture.annotations.skip(2),
      ];
      final content = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: contexts,
        sourceOrder: [0, 2, 1, 3, 4, 5],
        atomicRanges: [
          (startUtf16: 0, endUtf16: original.projection.display.text.length),
        ],
      );
      final parent = fixture.cache.acquireInline(
        content: content,
        width: 300,
        dimensions: [metrics.placeholderDimensions],
      );
      final view = ForumBodyInlineParagraphView.adopt(
        cache: fixture.cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubySegments: {0: segment},
      );
      addTearDown(view.close);
      final origin = parent.layout.atomBoxes.single.toRect().topLeft;
      var approximate = 0;
      for (final window in content.contexts) {
        final box = view
            .selectionBoxes(window.startUtf16, window.endUtf16)
            .first
            .toRect();
        final point = Offset(box.left + .001, box.center.dy);
        final actual = view.sourceAt(point);
        final direct = segment.sourceAt(point - origin);
        expect(actual.sourceRune, direct.position.sourceRune);
        expect(
          actual.displayUtf16,
          window.startUtf16 + direct.position.displayUtf16,
        );
        final affinity = content.projection.display.sourceAtUtf16(
          actual.displayUtf16,
        );
        expect(
          actual.isExact,
          direct.position.isExact &&
              affinity.isExact &&
              direct.position.sourceRune == affinity.sourceRune,
        );
        if (!actual.isExact) approximate++;
      }
      expect(approximate, greaterThan(0));
      view.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'reordered current windows cannot silently change actual member binding',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final original = fixture.inlineContent;
      final content = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: [fixture.bases[1], fixture.bases[0], ...fixture.annotations],
        sourceOrder: [1, 0, 2, 3, 4, 5],
        atomicRanges: [
          (startUtf16: 0, endUtf16: original.projection.display.text.length),
        ],
      );
      final segment = fixture.prepare(fixture.compose());
      final parent = fixture.cache.acquireInline(
        content: content,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: fixture.cache,
          parent: parent,
          startLine: 0,
          endLine: parent.layout.lines.length,
          rubySegments: {0: segment},
        ),
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.coverage,
          ),
        ),
      );
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'source-free empty base remains approximate inside its actual parent window',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final annotation = fixture.annotations.last;
      final original = fixture.inlineContent;
      fixture.releaseGlyphs();
      final request = ForumBodyRubySegmentRequest(
        bases: [ForumBodyTextRequest.paragraph(fixture.empty)],
        sides: [ForumBodyRubySide.over],
        spans: [
          (
            request: ForumBodyTextRequest.paragraph(annotation),
            startColumn: 0,
            endColumn: 1,
            annotationIndex: 0,
            gap: 0.0,
          ),
        ],
      );
      final planner = ForumBodyRubySegmentMetricsPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
      );
      addTearDown(planner.close);
      while (!planner.isReady) {
        planner.advance();
      }
      final metrics = planner.takeMetrics();
      final prepare = ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
      );
      addTearDown(prepare.close);
      while (!prepare.isReady) {
        prepare.advance();
      }
      final segment = prepare.takeLayout();
      addTearDown(segment.close);
      final content = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: [annotation],
        atomicRanges: [
          (startUtf16: 0, endUtf16: annotation.projection.text.length),
        ],
      );
      final parent = fixture.cache.acquireInline(
        content: content,
        width: 100,
        dimensions: [metrics.placeholderDimensions],
      );
      final origin = parent.layout.atomBoxes.single.toRect().topLeft;
      final view = ForumBodyInlineParagraphView.adopt(
        cache: fixture.cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubySegments: {0: segment},
      );
      addTearDown(view.close);
      final blank = view.sourceAt(
        origin + Offset(metrics.size.width / 2, metrics.baseline),
      );
      expect(blank.isExact, isFalse);
      final box = view.selectionBoxes(1, 2).single.toRect();
      expect(
        view.sourceAt(Offset(box.left + .01, box.center.dy)).isExact,
        isTrue,
      );
      view.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );
}
