import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_layer_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 23,
    ),
  );
  tearDown(() => cache.close());

  ({
    ForumBodyInlineParagraphView view,
    ForumBodyRubyGroupLayout group,
    ForumBodyInlineParagraphLease parent,
  })
  open(RubyLayerFixture input, {double width = 300, bool onlyAtomRow = false}) {
    final group = rubyLayerGroup(
      cache: cache,
      parts: input.parts,
      gaps: [1, 2, 3],
    );
    final parent = cache.acquireInline(
      content: input.content,
      width: width,
      dimensions: [group.placeholderDimensions],
    );
    final row = parent.layout.lines.indexWhere(
      (line) =>
          input.content.projection.atoms.single.engineUtf16 >=
              line.engineCoverageStartUtf16 &&
          input.content.projection.atoms.single.engineUtf16 <
              line.engineCoverageEndUtf16,
    );
    final view = ForumBodyInlineParagraphView.adopt(
      cache: cache,
      parent: parent,
      startLine: onlyAtomRow ? row : 0,
      endLine: onlyAtomRow ? row + 1 : parent.layout.lines.length,
      rubyGroups: {0: group},
    );
    return (view: view, group: group, parent: parent);
  }

  for (final direction in ['ltr', 'rtl']) {
    for (final missing in [false, true]) {
      test(
        'actual $direction view binds each original RTC rank, missing=$missing',
        () {
          final input = rubyLayerInput(
            direction: direction,
            base: direction == 'rtl' ? 'אב' : 'AB',
            annotations: missing
                ? const [('', 10), ('', 15), ('qq', 5)]
                : const [('xy', 10), ('z', 15), ('q', 5)],
          );
          final result = open(input);
          try {
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.activeLeases,
            );
            final contexts = input.content.resolveAtomicContexts(0, [
              input.parts.first,
              for (var i = 1; i < input.parts.length; i++)
                if (input.parts[i].projection.text.isNotEmpty) input.parts[i],
            ]);
            expect(result.view.nativeLeases.length, missing ? 3 : 5);
            for (final window in contexts) {
              final boxes = result.view.selectionBoxes(
                window.startUtf16,
                window.endUtf16,
                clipToView: false,
              );
              expect(boxes, isNotEmpty);
              final box = boxes.first.toRect();
              final point = Offset(
                direction == 'rtl' ? box.right - .1 : box.left + .1,
                box.center.dy,
              );
              final index = input.parts.indexOf(window.content);
              final origin = result.parent.layout.atomBoxes.single
                  .toRect()
                  .topLeft;
              final direct = result.group.sourceAt(point - origin);
              final hit = result.view.sourceAt(point);
              expect(direct.annotationIndex, index == 0 ? null : index - 1);
              expect(hit.sourceRune, direct.position.sourceRune);
              expect(
                hit.displayUtf16,
                window.startUtf16 + direct.position.displayUtf16,
              );
              expect(hit.isExact, isTrue);
              expect(box.top, greaterThanOrEqualTo(-1e-4));
              expect(box.bottom, lessThanOrEqualTo(result.view.height + 1e-4));
            }
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.activeLeases,
            ), before);
          } finally {
            result.view.close();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }

  test('ignored RP gaps remain approximate after actual rank routing', () {
    final input = rubyLayerInput(fallbackDelimiters: true);
    final result = open(input);
    try {
      final windows = input.content.resolveAtomicContexts(0, input.parts);
      final origin = result.parent.layout.atomBoxes.single.toRect().topLeft;
      for (var rank = 0; rank < 3; rank++) {
        final window = windows[rank + 1];
        final box = result.view
            .selectionBoxes(window.startUtf16, window.endUtf16)
            .first
            .toRect();
        final point = Offset(box.left + .1, box.center.dy);
        final child = result.group.sourceAt(point - origin);
        final hit = result.view.sourceAt(point);
        expect(child.annotationIndex, rank);
        expect(child.position.isExact, isTrue);
        expect(hit.sourceRune, child.position.sourceRune);
        expect(hit.isExact, isFalse);
      }
    } finally {
      result.view.close();
    }
    expect(cache.activeLeases, 0);
  });

  test(
    'partial emoji/accent selections remain inside the selected annotation rank',
    () {
      final input = rubyLayerInput(
        annotations: const [('👩‍👩‍👧‍👧', 10), ('e\u0301', 15), ('字', 5)],
      );
      final result = open(input);
      try {
        final contexts = input.content.resolveAtomicContexts(0, input.parts);
        final origin = result.parent.layout.atomBoxes.single.toRect().topLeft;
        for (var rank = 0; rank < 3; rank++) {
          final window = contexts[rank + 1];
          final from = rank == 2 ? 0 : 1;
          final to = from + 1;
          final boxes = result.view.selectionBoxes(
            window.startUtf16 + from,
            window.startUtf16 + to,
            clipToView: false,
          );
          final expected = result.group.selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            annotationIndex: rank,
            startUtf16: from,
            endUtf16: to,
          );
          expect(
            boxes.map((box) => box.toRect()),
            expected.map((box) => box.toRect().shift(origin)),
          );
          final band = result.group.metrics.annotations[rank];
          expect(
            boxes.every(
              (box) =>
                  box.top >= origin.dy + band.bandTop - 1e-4 &&
                  box.bottom <= origin.dy + band.bandBottom + 1e-4,
            ),
            isTrue,
          );
        }
      } finally {
        result.view.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test('a later line window retains only its visible multi-layer column', () {
    final input = rubyLayerInput(prefix: 'PPPPPP', suffix: 'QQQQQQ');
    final result = open(input, width: 60, onlyAtomRow: true);
    try {
      expect(result.view.startLine, greaterThan(0));
      expect(result.view.coverageStartUtf16, greaterThan(0));
      expect(result.view.nativeLeases.length, 5);
      final all = result.view.selectionBoxes(
        0,
        input.content.projection.display.text.length,
        clipToView: false,
      );
      expect(all, isNotEmpty);
      expect(
        all.every(
          (box) => box.top >= -1e-4 && box.bottom <= result.view.height + 1e-4,
        ),
        isTrue,
      );
      for (final window in input.content.contexts.where(
        (context) => input.parts.skip(1).contains(context.content),
      )) {
        final box = result.view
            .selectionBoxes(window.startUtf16, window.endUtf16)
            .first
            .toRect();
        final hit = result.view.sourceAt(Offset(box.left + .1, box.center.dy));
        expect(hit.isExact, isTrue);
        expect(
          hit.sourceRune,
          window.content.projection.sourceAtUtf16(0).sourceRune,
        );
      }
      expect(result.view.sourceAt(const Offset(1, -100)).isExact, isFalse);
      expect(
        result.view.sourceAt(Offset(1, result.view.height + 100)).isExact,
        isFalse,
      );
    } finally {
      result.view.close();
    }
    expect(cache.activeLeases, 0);
  });

  test(
    'a stale outer context fails binding and releases only supplied view handles',
    () {
      final old = rubyLayerInput();
      final fresh = rubyLayerInput();
      final sibling = open(old);
      try {
        final group = rubyLayerGroup(
          cache: cache,
          parts: [fresh.parts[0], fresh.parts[1], fresh.parts[2], old.parts[3]],
        );
        final parent = cache.acquireInline(
          content: fresh.content,
          width: 300,
          dimensions: [group.placeholderDimensions],
        );
        expect(
          () => ForumBodyInlineParagraphView.adopt(
            cache: cache,
            parent: parent,
            startLine: 0,
            endLine: parent.layout.lines.length,
            rubyGroups: {0: group},
          ),
          throwsA(
            isA<ForumBodyInlineViewException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyInlineViewFailure.identity,
            ),
          ),
        );
        expect(group.isActive, isFalse);
        expect(parent.isActive, isFalse);
        expect(sibling.view.isActive, isTrue);
        expect(cache.activeLeases, 5);
      } finally {
        sibling.view.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'actual Surface taps outer ranks without shaping and closes all handles on unmount',
    (tester) async {
      final input = rubyLayerInput(
        annotations: const [('', 10), ('z', 15), ('qq', 5)],
      );
      final result = open(input);
      final received = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyInlineParagraphSurface(
              view: result.view,
              onSourceTap: (hit) {
                if (hit.isExact) received.add(hit.sourceRune);
              },
            ),
          ),
        ),
      );
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      final surfaceOrigin = tester.getTopLeft(
        find.byType(ForumBodyInlineParagraphSurface),
      );
      for (final part
          in input.parts
              .skip(1)
              .where((part) => part.projection.text.isNotEmpty)) {
        final window = input.content.contexts.singleWhere(
          (context) => identical(context.content, part),
        );
        final box = result.view
            .selectionBoxes(window.startUtf16, window.endUtf16)
            .first
            .toRect();
        await tester.tapAt(
          surfaceOrigin + Offset(box.left + .1, box.center.dy),
        );
        await tester.pump();
        expect(received.last, part.projection.sourceAtUtf16(0).sourceRune);
      }
      expect(received.length, 2);
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(result.view.isActive, isFalse);
      expect(cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
