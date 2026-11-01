import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

Future<List<int>> pixels(ui.PictureRecorder recorder, Size size) async {
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 20);
  });
  tearDown(() {
    cache.close();
  });

  test(
    'under annotation paint and hits share independently formatted native offsets',
    () async {
      final input = rubyPairInput();
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
        side: ForumBodyRubySide.under,
      );
      final base = TextPainter(
        text: input.base.textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      final rt = TextPainter(
        text: input.annotation.textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      try {
        expect(group.size, const Size(40, 32));
        expect(group.baseOffset, Offset.zero);
        expect(group.annotationOffset, const Offset(10, 22));
        expect(
          group.baseline,
          base.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        expect(group.sourceAt(const Offset(1, 5)).part, ForumBodyRubyPart.base);
        final hit = group.sourceAt(const Offset(11, 23));
        expect(hit.part, ForumBodyRubyPart.annotation);
        expect(hit.position.sourceRune, 2);
        final actual = ui.PictureRecorder();
        group.paint(Canvas(actual), Offset.zero);
        final actualPixels = await pixels(actual, group.size);
        final expected = ui.PictureRecorder();
        final canvas = Canvas(expected);
        base.paint(canvas, Offset.zero);
        rt.paint(canvas, const Offset(10, 22));
        expect(actualPixels, await pixels(expected, group.size));
      } finally {
        base.dispose();
        rt.dispose();
        group.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test('under anonymous base area remains an approximate annotation hit', () {
    final input = rubyPairInput(base: '');
    final group = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
      side: ForumBodyRubySide.under,
    );
    try {
      final blank = group.sourceAt(const Offset(1, 1));
      expect(blank.part, ForumBodyRubyPart.annotation);
      expect(blank.position.isExact, isFalse);
      final rt = group.sourceAt(const Offset(11, 25));
      expect(rt.part, ForumBodyRubyPart.annotation);
      expect(rt.position.sourceRune, 1);
      expect(rt.position.isExact, isTrue);
    } finally {
      group.close();
    }
  });

  test(
    'empty base borrows native font metrics and never becomes a text hit',
    () {
      final input = rubyPairInput(base: '');
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      try {
        expect(group.size, const Size(20, 30));
        expect(group.baseline, greaterThan(20));
        expect(
          group.selectionBoxes(
            part: ForumBodyRubyPart.base,
            startUtf16: 0,
            endUtf16: 0,
          ),
          isEmpty,
        );
        final hit = group.sourceAt(const Offset(11, 5));
        expect(hit.part, ForumBodyRubyPart.annotation);
        expect(hit.position.sourceRune, 1);
        expect(hit.position.isExact, isTrue);
        final blank = group.sourceAt(const Offset(1, 29));
        expect(blank.part, ForumBodyRubyPart.annotation);
        expect(blank.position.isExact, isFalse);
      } finally {
        group.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'natural base and annotation share an actual alphabetic baseline box',
    () {
      final input = rubyPairInput();
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
      );
      addTearDown(group.close);
      expect(group.size, const Size(40, 32));
      expect(group.baseOffset, const Offset(0, 12));
      expect(group.annotationOffset, const Offset(10, 0));
      final base = cache.acquire(content: input.base, width: 100);
      addTearDown(base.release);
      expect(group.baseline, base.layout.lines.single.baseline + 12);
      expect(group.placeholderDimensions.size, group.size);
      expect(group.placeholderDimensions.baselineOffset, group.baseline);
      expect(
        group.placeholderDimensions.alignment,
        ui.PlaceholderAlignment.baseline,
      );
      expect(cache.layoutBuildCount, 2);
    },
  );

  test('longer annotation expands the box instead of shrinking glyphs', () {
    final input = rubyPairInput(base: 'A', annotation: 'abcdef');
    final group = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
    );
    addTearDown(group.close);
    expect(group.size.width, 60);
    expect(group.baseOffset.dx, 20);
    expect(
      group
          .selectionBoxes(
            part: ForumBodyRubyPart.base,
            startUtf16: 0,
            endUtf16: 1,
          )
          .single
          .toRect()
          .width,
      20,
    );
    expect(
      group
          .selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            startUtf16: 5,
            endUtf16: 6,
          )
          .single
          .right,
      60,
    );
    expect(group.projectionFor(ForumBodyRubyPart.base).text, 'A');
    expect(group.projectionFor(ForumBodyRubyPart.annotation).text, 'abcdef');
  });

  test(
    'base and annotation hit their own source coordinates and graphemes',
    () {
      final input = rubyPairInput(
        base: '👨‍👩‍👧‍👦e\u0301',
        annotation: 'xyz',
      );
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(group.close);
      final annotation = group
          .selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            startUtf16: 0,
            endUtf16: 1,
          )
          .single;
      final annotationHit = group.sourceAt(
        Offset(annotation.left + .1, (annotation.top + annotation.bottom) / 2),
      );
      expect(annotationHit.part, ForumBodyRubyPart.annotation);
      expect(
        annotationHit.position.sourceRune,
        9,
      ); // Family7 runes + e + accent.
      final base = group.selectionBoxes(
        part: ForumBodyRubyPart.base,
        startUtf16: 1,
        endUtf16: 2,
      );
      expect(
        base.map((box) => box.toRect()),
        group
            .selectionBoxes(
              part: ForumBodyRubyPart.base,
              startUtf16: 0,
              endUtf16: 11,
            )
            .map((box) => box.toRect()),
      );
      final box = base.first;
      final baseHit = group.sourceAt(
        Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(baseHit.part, ForumBodyRubyPart.base);
      expect(baseHit.position.sourceRune, 0);
      expect(
        () => group.sourceAt(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    },
  );

  test(
    'per-size nonlinear scaling is applied once, including the parent placeholder',
    () {
      final input = rubyPairInput();
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        textScaler: const _Scaler(),
      );
      addTearDown(group.close);
      expect(
        group.size,
        const Size(60, 55),
      ); // 20->30, 10->25, not a single factor.
      final parent =
          TextPainter(
              text: TextSpan(
                style: const TextStyle(fontSize: 20, fontFamily: 'Ahem'),
                children: const [
                  TextSpan(text: 'a'),
                  WidgetSpan(
                    alignment: ui.PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: SizedBox.shrink(),
                  ),
                  TextSpan(text: 'b'),
                ],
              ),
              textDirection: TextDirection.ltr,
              textScaler: const _Scaler(),
            )
            ..setPlaceholderDimensions([group.placeholderDimensions])
            ..layout(maxWidth: 200);
      addTearDown(parent.dispose);
      final box = parent.inlinePlaceholderBoxes!.single;
      expect(box.toRect().size, group.size);
      expect(
        box.top + group.baseline,
        closeTo(parent.computeLineMetrics().single.baseline, 1e-6),
      );
    },
  );

  test(
    'tight parent lines wrap entire groups and retain both rows inside each line',
    () {
      final input = rubyPairInput();
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
      );
      addTearDown(group.close);
      const placeholder = WidgetSpan(
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SizedBox.shrink(),
      );
      final parent =
          TextPainter(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Ahem', fontSize: 20, height: .5),
                children: [
                  TextSpan(text: 'X'),
                  placeholder,
                  TextSpan(text: 'Y'),
                  placeholder,
                ],
              ),
              textDirection: TextDirection.ltr,
            )
            ..setPlaceholderDimensions([
              group.placeholderDimensions,
              group.placeholderDimensions,
            ])
            ..layout(maxWidth: 60);
      addTearDown(parent.dispose);
      final boxes = parent.inlinePlaceholderBoxes!;
      final lines = parent.computeLineMetrics();
      expect(lines, hasLength(2));
      expect(boxes, hasLength(2));
      expect(boxes[1].top, greaterThanOrEqualTo(boxes[0].bottom));
      for (var i = 0; i < boxes.length; i++) {
        expect(boxes[i].toRect().size, group.size);
        expect(boxes[i].top, greaterThanOrEqualTo(0));
        expect(boxes[i].bottom, lessThanOrEqualTo(parent.height));
        expect(boxes[i].top + group.baseline, closeTo(lines[i].baseline, 1e-6));
      }
    },
  );

  test('each side retains its own bidi and grapheme context', () {
    final input = rubyPairInput(base: 'אב', annotation: 'xy', direction: 'rtl');
    final group = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
    );
    addTearDown(group.close);
    final box = group
        .selectionBoxes(
          part: ForumBodyRubyPart.base,
          startUtf16: 0,
          endUtf16: 1,
        )
        .single;
    expect(box.direction, TextDirection.rtl);
    final hit = group.sourceAt(
      Offset(box.right - .1, (box.top + box.bottom) / 2),
    );
    expect(hit.part, ForumBodyRubyPart.base);
    expect(hit.position.sourceRune, 0);
    final isolated = rubyPairInput(base: 'e', annotation: '\u0301');
    final accent = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: isolated.base,
      annotation: isolated.annotation,
    );
    addTearDown(accent.close);
    final projection = accent.projectionFor(ForumBodyRubyPart.annotation);
    expect(projection.text, '\u0301');
    expect(projection.sourceAtUtf16(0).sourceRune, 1);
    expect(projection.graphemeRanges(startUtf16: 0, endUtf16: 1), hasLength(1));
  });

  test(
    'different source/font scopes and nonintrinsic contents fail before acquisition',
    () {
      final input = rubyPairInput();
      final otherSource = rubyPairInput(base: 'CD');
      final otherFont = rubyPairInput(fontRevision: 'replacement');
      final wrapped = rubyPairInput(
        layoutMode: ForumBodyParagraphLayoutMode.wrap,
      );
      final empty = rubyPairInput(base: '', annotation: '');
      for (final (base, annotation, failure) in [
        (input.base, otherSource.annotation, ForumBodyRubyGroupFailure.scope),
        (input.base, otherFont.annotation, ForumBodyRubyGroupFailure.scope),
        (wrapped.base, wrapped.annotation, ForumBodyRubyGroupFailure.content),
        (empty.base, empty.annotation, ForumBodyRubyGroupFailure.content),
      ]) {
        expect(
          () => ForumBodyRubyGroupLayout.create(
            cache: cache,
            base: base,
            annotation: annotation,
          ),
          throwsA(
            isA<ForumBodyRubyGroupException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
      }
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'mixed-size paint matches the two shared native layouts at their actual offsets',
    () async {
      final input = rubyPairInput(
        base: 'A<span style="font-size:30px">B</span>',
        annotation: 'xyz',
      );
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
      );
      addTearDown(group.close);
      final base = cache.acquire(content: input.base, width: 100);
      final annotation = cache.acquire(content: input.annotation, width: 100);
      addTearDown(base.release);
      addTearDown(annotation.release);
      final actual = ui.PictureRecorder();
      group.paint(Canvas(actual), Offset.zero);
      final expected = ui.PictureRecorder();
      final canvas = Canvas(expected);
      base.layout.paint(canvas, group.baseOffset);
      annotation.layout.paint(canvas, group.annotationOffset);
      expect(
        await pixels(actual, group.size),
        await pixels(expected, group.size),
      );
      expect(cache.layoutBuildCount, 2);
    },
  );

  test(
    'tight child line heights retain real font boxes without clipping either row',
    () async {
      final tight = rubyPairInput(
        baseLineHeight: .25,
        annotationLineHeight: .25,
      );
      final normal = rubyPairInput();
      final tightGroup = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: tight.base,
        annotation: tight.annotation,
        gap: 2,
      );
      final normalGroup = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: normal.base,
        annotation: normal.annotation,
        gap: 2,
      );
      addTearDown(tightGroup.close);
      addTearDown(normalGroup.close);
      final baseBoxes = tightGroup.selectionBoxes(
        part: ForumBodyRubyPart.base,
        startUtf16: 0,
        endUtf16: 2,
      );
      final annotationBoxes = tightGroup.selectionBoxes(
        part: ForumBodyRubyPart.annotation,
        startUtf16: 0,
        endUtf16: 2,
      );
      for (final box in [...baseBoxes, ...annotationBoxes]) {
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(tightGroup.size.height));
      }
      expect(
        baseBoxes.first.top,
        greaterThanOrEqualTo(annotationBoxes.first.bottom + 2),
      );
      final baseHit = tightGroup.sourceAt(
        Offset(baseBoxes.first.left + .1, baseBoxes.first.top + .1),
      );
      expect(baseHit.part, ForumBodyRubyPart.base);
      expect(baseHit.position.sourceRune, 0);
      final annotationHit = tightGroup.sourceAt(
        Offset(
          annotationBoxes.first.left + .1,
          annotationBoxes.first.bottom - .1,
        ),
      );
      expect(annotationHit.part, ForumBodyRubyPart.annotation);
      expect(annotationHit.position.sourceRune, 2);
      expect(tightGroup.size, normalGroup.size);
      final tightRecorder = ui.PictureRecorder();
      tightGroup.paint(Canvas(tightRecorder), Offset.zero);
      final normalRecorder = ui.PictureRecorder();
      normalGroup.paint(Canvas(normalRecorder), Offset.zero);
      expect(
        await pixels(tightRecorder, tightGroup.size),
        await pixels(normalRecorder, normalGroup.size),
      );
    },
  );

  test(
    'an empty annotation adds neither a native layout nor a blank upper row',
    () {
      final input = rubyPairInput(annotation: '');
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 20,
      );
      addTearDown(group.close);
      expect(group.hasAnnotation, isFalse);
      expect(group.size, const Size(40, 20));
      expect(group.baseOffset, Offset.zero);
      expect(
        group.selectionBoxes(
          part: ForumBodyRubyPart.annotation,
          startUtf16: 0,
          endUtf16: 0,
        ),
        isEmpty,
      );
      expect(cache.layoutBuildCount, 1);
      expect(group.sourceAt(Offset.zero).part, ForumBodyRubyPart.base);
    },
  );

  test(
    'gap and admission-width changes reuse native text but recompose geometry',
    () {
      final input = rubyPairInput();
      final first = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
        maxWidth: 100,
      );
      final second = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 5,
        maxWidth: 200,
      );
      expect(second.size.height, first.size.height + 3);
      expect(second.baseOffset.dy, first.baseOffset.dy + 3);
      expect(cache.layoutBuildCount, 2);
      expect(cache.activeLeases, 4);
      first.close();
      second.close();
      first.close();
      expect(cache.activeLeases, 0);
      expect(cache.isClosed, isFalse);
    },
  );

  test(
    'overflow, invalid input and a failed second acquisition release only owned leases',
    () {
      final input = rubyPairInput();
      expect(
        () => ForumBodyRubyGroupLayout.create(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
          maxWidth: 30,
        ),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyRubyGroupFailure.overflow,
          ),
        ),
      );
      expect(cache.activeLeases, 0);
      expect(
        () => ForumBodyRubyGroupLayout.create(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
          gap: double.nan,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      final tight = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(tight.close);
      expect(
        () => ForumBodyRubyGroupLayout.create(
          cache: tight,
          base: input.base,
          annotation: input.annotation,
        ),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(tight.activeLeases, 0);
      final external = tight.acquire(content: input.base, width: 100);
      expect(
        () => ForumBodyRubyGroupLayout.create(
          cache: tight,
          base: input.base,
          annotation: input.annotation,
        ),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(external.isActive, isTrue);
      expect(tight.activeLeases, 1);
      external.release();
      expect(tight.activeLeases, 0);
    },
  );

  test('owner closure retires live groups before any stale native access', () {
    final input = rubyPairInput();
    final group = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
    );
    cache.close();
    expect(group.isActive, isFalse);
    expect(() => group.placeholderDimensions, throwsStateError);
    expect(() => group.sourceAt(Offset.zero), throwsStateError);
    expect(
      () => group.selectionBoxes(
        part: ForumBodyRubyPart.base,
        startUtf16: 0,
        endUtf16: 1,
      ),
      throwsStateError,
    );
    final recorder = ui.PictureRecorder();
    expect(() => group.paint(Canvas(recorder), Offset.zero), throwsStateError);
    recorder.endRecording().dispose();
    group.close();
    group.close();
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 10 ? size * 2.5 : size * 1.5;
  @override
  double get textScaleFactor => 1.5;
}
