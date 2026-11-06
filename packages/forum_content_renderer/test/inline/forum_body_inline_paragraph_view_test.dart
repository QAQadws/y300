import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

typedef Input = ({
  ForumBodyInlineSpanContent content,
  ForumBodyParagraphContent base,
  ForumBodyParagraphContent annotation,
  List<ForumBodyParagraphContent> contexts,
});

ForumBodyRubyGroupLayout group(
  ForumBodyParagraphCache cache,
  Input input, {
  bool batched = true,
}) {
  if (!batched) {
    return ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
    );
  }
  final band = ForumBodyTextBandContent(
    contexts: [input.base, input.annotation],
  );
  final prepare = ForumBodyRubyGroupPreparation.fromRequests(
    cache: cache,
    base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
    annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
    ensureOwner: () {},
  );
  try {
    while (!prepare.isReady) {
      prepare.advance();
    }
    return prepare.takeLayout();
  } finally {
    prepare.close();
  }
}

ForumBodyInlineParagraphView view(
  ForumBodyParagraphCache cache,
  Input input, {
  double width = 60,
  int start = 0,
  int? end,
}) {
  final child = group(cache, input);
  final parent = cache.acquireInline(
    content: input.content,
    width: width,
    dimensions: [child.placeholderDimensions],
  );
  final fragment = parent.layout.fragment(
    start,
    end ?? parent.layout.lines.length,
  );
  final visible = fragment.atomIndices.contains(0);
  if (!visible) child.close();
  return ForumBodyInlineParagraphView.adopt(
    cache: cache,
    parent: parent,
    startLine: fragment.startLine,
    endLine: fragment.endLine,
    rubyGroups: {if (visible) 0: child},
  );
}

Future<List<int>> raster(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(200, 100);
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

Widget host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retired ruby child invalidates reads while its parent lease is active',
    () {
      final input = mixedInlineInput(prefix: '', suffix: '');
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final child = group(cache, input);
      final parent = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: [child.placeholderDimensions],
      );
      final subject = ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: 1,
        rubyGroups: {0: child},
      );
      addTearDown(subject.close);
      expect(subject.content, same(input.content));
      child.close();
      expect(parent.isActive, isTrue);
      expect(() => subject.content, throwsStateError);
      expect(() => subject.glyphBoxes(0, 1), throwsStateError);
      subject.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'fractional native placeholder overhang preserves all child pixels',
    () async {
      final input = mixedInlineInput(
        prefix: '',
        base: 'A',
        annotation: 'x',
        suffix: '',
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 18.5,
            height: 1.27,
            color: Color(0xff000000),
          ),
          fontRevision: 'fractional-ahem',
          linkColor: const Color(0xff0000ff),
        ),
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final child = group(cache, input);
      final parent = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: [child.placeholderDimensions],
      );
      final subject = ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: 1,
        rubyGroups: {0: child},
      );
      try {
        final expected = await raster((canvas) {
          canvas.scale(3);
          child.paint(canvas, Offset.zero);
        });
        final actual = await raster((canvas) {
          canvas.scale(3);
          subject.paint(canvas, Offset.zero);
        });
        expect(
          actual
              .asMap()
              .entries
              .where((entry) => entry.value != expected[entry.key])
              .length,
          0,
          reason:
              'frame=${subject.width}x${subject.height}/child=${child.size}'
              '/box=${parent.layout.atomBoxes.single.toRect()}'
              '/diffRows=${actual.asMap().entries.where((entry) => entry.value != expected[entry.key]).map((entry) => entry.key ~/ (200 * 4)).toSet()}',
        );
        expect(parent.layout.atomBoxes.single.top, 0);
        expect(subject.height, child.size.height);
        final boxes = subject.selectionBoxes(
          0,
          input.content.projection.display.text.length,
          clipToView: false,
        );
        expect(
          boxes.every((box) => box.top >= 0 && box.bottom <= subject.height),
          isTrue,
        );
      } finally {
        subject.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'mixed view paints complete parent plus band children exactly like native standalone glyphs',
    () async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 6,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final actual = view(cache, input, end: 1);
      addTearDown(actual.close);
      final expectedChild = group(cache, input, batched: false);
      addTearDown(expectedChild.close);
      final expectedParent = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [expectedChild.placeholderDimensions],
      );
      addTearDown(expectedParent.release);
      final offset = const Offset(3.25, 4.5);
      final pixels = await raster((canvas) => actual.paint(canvas, offset));
      final expected = await raster((canvas) {
        canvas.clipRect(
          offset & Size(actual.width, actual.height),
          doAntiAlias: false,
        );
        expectedParent.layout.fragment(0, 1).paintParent(canvas, offset);
        expectedChild.paint(
          canvas,
          offset + expectedParent.layout.atomBoxes.single.toRect().topLeft,
        );
      });
      expect(pixels, expected);
      expect(pixels.any((value) => value != 0), isTrue);
      expect(actual.atomIndices, [0]);
      expect((actual.coverageStartUtf16, actual.coverageEndUtf16), (0, 5));
      expect(
        input.content.contexts.map(
          (context) => (context.startUtf16, context.endUtf16),
        ),
        [(0, 1), (1, 3), (3, 5), (5, 6)],
      );
      expect(() => input.content.contexts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'base and RT hits use actual source points and parent display coordinates',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final actual = view(cache, input, end: 1);
      addTearDown(actual.close);
      for (final (from, to, content) in [
        (1, 2, input.base),
        (3, 4, input.annotation),
      ]) {
        final box = actual.selectionBoxes(from, to).single;
        final hit = actual.sourceAt(
          Offset(box.left + .1, (box.top + box.bottom) / 2),
        );
        expect(hit.sourceRune, content.projection.sourceAtUtf16(0).sourceRune);
        expect(hit.displayUtf16, from);
        expect(box.right - box.left, from == 1 ? 20 : 10);
      }
      final annotationHit = actual.sourceAt(const Offset(30.1, 5));
      expect(
        annotationHit.isExact,
        isFalse,
      ); // RP source gap remains ambiguous.
      expect(actual.selectionBoxes(1, 1), isEmpty);
      expect(actual.selectionBoxes(5, 6), isEmpty);
      expect(
        () => actual.sourceAt(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    },
  );

  test(
    'a continuation view contains no earlier atom handles and clamps off-page hits',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final actual = view(cache, input, start: 1, end: 2);
      addTearDown(actual.close);
      expect(actual.atomIndices, isEmpty);
      expect(cache.activeLeases, 1);
      final hit = actual.sourceAt(const Offset(1, 10));
      expect(
        hit.sourceRune,
        input.contexts.last.projection.sourceAtUtf16(0).sourceRune,
      );
      expect(hit.displayUtf16, 5);
      final outside = actual.sourceAt(const Offset(-100, -100));
      expect(outside.displayUtf16, inInclusiveRange(5, 6));
      expect(outside.isExact, isFalse);
      expect(actual.selectionBoxes(0, 5), isEmpty);
      expect(actual.selectionBoxes(5, 6), hasLength(1));
    },
  );

  test(
    'missing/extra children consume only supplied handles and preserve other views',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final kept = view(cache, input, end: 1);
      addTearDown(kept.close);
      final extra = group(cache, input);
      final dimensions = extra.placeholderDimensions;
      final parent = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [dimensions],
      );
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: cache,
          parent: parent,
          startLine: 1,
          endLine: 2,
          rubyGroups: {0: extra},
        ),
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyInlineViewFailure.coverage,
          ),
        ),
      );
      expect(extra.isActive, isFalse);
      expect(parent.isActive, isFalse);
      expect(kept.isActive, isTrue);
      final missing = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [dimensions],
      );
      expect(
        () => ForumBodyInlineParagraphView.adopt(
          cache: cache,
          parent: missing,
          startLine: 0,
          endLine: 1,
          rubyGroups: {},
        ),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(kept.isActive, isTrue);
    },
  );

  test('equal text from fresh contexts cannot bind an old group', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final old = mixedInlineInput();
    final current = mixedInlineInput();
    final stale = group(cache, old);
    final parent = cache.acquireInline(
      content: current.content,
      width: 60,
      dimensions: [stale.placeholderDimensions],
    );
    expect(
      () => ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: 1,
        rubyGroups: {0: stale},
      ),
      throwsA(
        isA<ForumBodyInlineViewException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyInlineViewFailure.identity,
        ),
      ),
    );
    expect(cache.activeLeases, 0);
  });

  test('same-owner proof and actual child baseline/size are required', () {
    final a = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    final b = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(a.close);
    addTearDown(b.close);
    final input = mixedInlineInput();
    final foreign = group(b, input);
    final parent = a.acquireInline(
      content: input.content,
      width: 60,
      dimensions: [foreign.placeholderDimensions],
    );
    expect(
      () => ForumBodyInlineParagraphView.adopt(
        cache: a,
        parent: parent,
        startLine: 0,
        endLine: 1,
        rubyGroups: {0: foreign},
      ),
      throwsA(
        isA<ForumBodyInlineViewException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyInlineViewFailure.leases,
        ),
      ),
    );
    final child = group(a, input);
    final mismatched = a.acquireInline(
      content: input.content,
      width: 80,
      dimensions: [
        PlaceholderDimensions(
          size: Size(child.size.width + 1, child.size.height),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: child.baseline,
        ),
      ],
    );
    expect(
      () => ForumBodyInlineParagraphView.adopt(
        cache: a,
        parent: mismatched,
        startLine: 0,
        endLine: 1,
        rubyGroups: {0: child},
      ),
      throwsA(
        isA<ForumBodyInlineViewException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyInlineViewFailure.geometry,
        ),
      ),
    );
    expect(a.activeLeases, 0);
    expect(b.activeLeases, 0);
  });

  test(
    'selection within an emoji preserves the actual child grapheme and excludes RT',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput(
        base: '👨‍👩‍👧‍👦e\u0301',
        annotation: 'abc',
      );
      final actual = view(cache, input, width: 400);
      addTearDown(actual.close);
      expect(
        actual.selectionBoxes(2, 3).map((box) => box.toRect()),
        actual.selectionBoxes(1, 12).map((box) => box.toRect()),
      );
      final box = actual.selectionBoxes(2, 3).first;
      final hit = actual.sourceAt(
        Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hit.displayUtf16, 1);
      expect(hit.sourceRune, input.base.projection.sourceAtUtf16(0).sourceRune);
    },
  );

  test(
    'RTL source routing uses child-native hits rather than interpolating the atom',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput(
        prefix: 'س',
        base: 'اب',
        annotation: 'xy',
        suffix: 'ה',
        direction: 'rtl',
      );
      final child = group(cache, input);
      final parent = cache.acquireInline(
        content: input.content,
        width: 160,
        dimensions: [child.placeholderDimensions],
      );
      final point = const Offset(1, 1);
      final expected = child.sourceAt(point);
      final origin = parent.layout.atomBoxes.single.toRect().topLeft;
      final actual = ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubyGroups: {0: child},
      );
      addTearDown(actual.close);
      final hit = actual.sourceAt(origin + point);
      expect(hit.sourceRune, expected.position.sourceRune);
      expect(hit.displayUtf16, 3 + expected.position.displayUtf16);
    },
  );

  testWidgets(
    'surface paints/taps prepared views without new cache work and releases on unmount',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final prepared = view(cache, input, end: 1);
      final layouts = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      final hits = <int>[];
      await tester.pumpWidget(
        host(
          ForumBodyInlineParagraphSurface(
            view: prepared,
            onSourceTap: (position) => hits.add(position.sourceRune),
          ),
        ),
      );
      final box = prepared.selectionBoxes(3, 4).single;
      await tester.tapAt(
        tester.getTopLeft(find.byType(ForumBodyInlineParagraphSurface)) +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hits, [input.annotation.projection.sourceAtUtf16(0).sourceRune]);
      expect(cache.layoutBuildCount, layouts);
      expect(cache.pictureBuildCount, pictures);
      await tester.pumpWidget(const SizedBox());
      expect(prepared.isActive, isFalse);
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'replacement and interaction identity changes cancel stale taps; callback rebind stays current',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      var current = view(cache, input, end: 1);
      var taps = 0;
      Widget surface(Object identity) => host(
        ForumBodyInlineParagraphSurface(
          view: current,
          interactionIdentity: identity,
          onSourceTap: (_) => taps++,
        ),
      );
      await tester.pumpWidget(surface(1));
      var gesture = await tester.startGesture(const Offset(25, 5));
      final retired = current;
      current = view(cache, input, end: 1);
      await tester.pumpWidget(surface(1));
      await gesture.up();
      expect(taps, 0);
      expect(retired.isActive, isFalse);
      gesture = await tester.startGesture(const Offset(25, 5));
      await tester.pumpWidget(surface(2));
      await gesture.up();
      expect(taps, 0);
      expect(current.isActive, isTrue);
      gesture = await tester.startGesture(const Offset(25, 5));
      await tester.pumpWidget(
        host(
          ForumBodyInlineParagraphSurface(
            view: current,
            interactionIdentity: 2,
            onSourceTap: (_) => taps += 10,
          ),
        ),
      );
      await gesture.up();
      expect(taps, 10);
      await tester.pumpWidget(const SizedBox());
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'surface semantics uses current visible body text, and owner close suppresses late taps',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput(
        base: 'A<span style="visibility:hidden">B</span>',
      );
      final prepared = view(cache, input, width: 160);
      var taps = 0;
      await tester.pumpWidget(
        host(
          ForumBodyInlineParagraphSurface(
            view: prepared,
            onSourceTap: (_) => taps++,
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(ForumBodyInlineParagraphSurface)).label,
        'XAxyY',
      );
      final gesture = await tester.startGesture(const Offset(25, 5));
      cache.close();
      await gesture.up();
      expect(taps, 0);
      tester
          .renderObject<RenderBox>(find.byType(ForumBodyInlineParagraphSurface))
          .markNeedsPaint();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(cache.activeLeases, 0);
      semantics.dispose();
    },
  );
}
