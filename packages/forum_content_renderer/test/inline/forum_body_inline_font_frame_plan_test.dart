import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache({int entries = 512}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

MixedEmphasisParentFixture _fixture({
  TextDirection direction = TextDirection.ltr,
  String child = '<ruby>B<rt>b</rt></ruby>',
  ForumBodyParagraphLayoutMode? mode,
}) => MixedEmphasisParentFixture(
  child,
  parentStyle: 'white-space:pre-wrap;line-height:.25',
  direction: direction,
  layoutMode: mode,
  prefix: '<span style="color:#ff0000">AA</span>\nCC',
  suffix:
      '\n<span style="color:#008000">DD</span>'
      '\n<span style="color:#0000ff">EE</span>',
);

ForumBodyInlineFontFramePreparation _work(
  MixedEmphasisParentFixture fixture,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
  void Function()? guard,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
}) {
  final work = ForumBodyInlineFontFramePreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: guard ?? () {},
    additionalOwnedLeases: owned,
  );
  addTearDown(work.close);
  return work;
}

int _finish(
  ForumBodyInlineFontFramePreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var parts = 0;
  for (var n = 0; !work.isReady; n++) {
    expect(n, lessThan(50000));
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
    expect(step.partsPrepared, inInclusiveRange(1, quantum));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(work.cacheMiss, isFalse);
    expect(cache.layoutBuildCount - before.$1, lessThanOrEqualTo(1));
    expect(cache.pictureBuildCount, before.$2);
    parts += step.partsPrepared;
  }
  return parts;
}

Future<Map<int, int>> _colors(
  ForumBodyTextPictureLease picture,
  Size size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.clipRect(Offset.zero & size);
  picture.paint(canvas, Offset.zero);
  final drawing = recorder.endRecording();
  final raster = await drawing.toImage(size.width.ceil(), size.height.ceil());
  try {
    final bytes = (await raster.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final result = <int, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      final color = bytes.getUint32(i);
      if (bytes.getUint8(i + 3) != 0) {
        result.update(color, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return result;
  } finally {
    raster.dispose();
    drawing.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      test('font frames retain source and whole ruby $direction $scaler', () {
        final fixture = _fixture(direction: direction), cache = _cache();
        final work = _work(fixture, cache, scaler: scaler);
        _finish(work, cache);
        expect(cache.activeLeases, 5);
        final plan = work.takePlan();
        expect(work.nativeLeases, isEmpty);
        expect(cache.activeLeases, 0);
        expect(cache.pictureBuildCount, 0);
        expect(plan.source, same(fixture.input));
        expect(plan.allocation.marks, isEmpty);
        final natural = plan.allocation.input.natural;
        expect(natural.text.units, isEmpty);
        expect(plan.lines.length, natural.geometry.lines.length);
        expect(
          plan.height,
          greaterThanOrEqualTo(natural.geometry.lines.last.bottom),
        );
        for (final (i, row) in plan.allocation.rows.indexed) {
          final original = natural.geometry.lines[i], line = row.line;
          expect(line.coverageStartUtf16, original.coverageStartUtf16);
          expect(line.coverageEndUtf16, original.coverageEndUtf16);
          expect(line.canBreakBefore, original.canBreakBefore);
          expect(line.canBreakAfter, original.canBreakAfter);
          final font = row.parentFontBounds;
          if (font != null) {
            expect(font.top, greaterThanOrEqualTo(line.top - 1e-6));
            expect(font.bottom, lessThanOrEqualTo(line.bottom + 1e-6));
          }
        }
        expect(plan.allocation.children.whereType<Object>(), hasLength(1));
        final child = plan.allocation.children.single!;
        final row = plan.lines[child.lineIndex];
        expect(child.bounds.top, greaterThanOrEqualTo(row.top - 1e-6));
        expect(child.bounds.bottom, lessThanOrEqualTo(row.bottom + 1e-6));
        final whole = plan.fragment(0, plan.lines.length);
        expect(whole.height, plan.height);
        expect(whole.coverageStartUtf16, 0);
        expect(
          whole.coverageEndUtf16,
          fixture.input.content.projection.display.text.length,
        );
        cache.close();
        // A pure plan remains usable after fonts are evicted; its keys cannot
        // authorize painting without a new current-resource binding.
        expect(plan.parentPictureInput(0, 1).commands, isNotEmpty);
        expect(
          () => plan.fragment(1, 1),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      });
    }

    test(
      'actual isolated parent pictures keep complete own ink $direction',
      () async {
        final fixture = _fixture(direction: direction), cache = _cache();
        final work = _work(fixture, cache);
        _finish(work, cache, quantum: 32);
        final measured = work.takeMeasurement();
        addTearDown(measured.close);
        expect(measured.isActive, isTrue);
        expect(measured.nativeLeases, hasLength(5));
        work.close();
        final before = cache.layoutBuildCount;
        for (final phase in measured.paint.phases) {
          cache.prepareInlineParentPaint(phase);
        }
        const layers = [
          ForumBodyParagraphPaintLayer.background,
          ForumBodyParagraphPaintLayer.foreground,
          ForumBodyParagraphPaintLayer.decoration,
        ];
        final plan = measured.plan;
        for (final (rowIndex, expectedColor) in [
          (0, 0xff0000ff),
          (2, 0x008000ff),
          (3, 0x0000ffff),
        ]) {
          final rows = [
            for (var layer = 0; layer < layers.length; layer++)
              ForumBodyInlinePaintRowView.phase(
                parent: measured.paint.phases[layer],
                reference: measured.paint.view.reference,
                lineIndex: rowIndex,
                layer: layers[layer],
                ensureOwner: () {},
                allocationOrigin: Offset(
                  0,
                  -plan.fragment(rowIndex, rowIndex + 1).top,
                ),
              ),
          ];
          final scene = ForumBodyTextPicturePreparation(
            cache: cache,
            input: plan.parentPictureInput(rowIndex, rowIndex + 1),
            text: const [],
            inlineRows: rows.where((row) => !row.selector.isEmpty),
            additionalOwnedLeases: () => measured.nativeLeases,
            ensureOwner: () {},
          );
          addTearDown(scene.close);
          while (!scene.isReady) {
            scene.advance(maxParts: 1);
          }
          final picture = scene.takeLease();
          try {
            final pixels = await _colors(
              picture,
              Size(plan.width, plan.fragment(rowIndex, rowIndex + 1).height),
            );
            // Two 20px Ahem squares. No neighboring row's differently colored ink.
            expect(pixels, {expectedColor: 800});
          } finally {
            picture.release();
          }
        }
        expect(cache.layoutBuildCount, before);
        measured.close();
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('cached-only cold miss does not shape or record, then resumes', () {
    final cache = _cache(), work = _work(_fixture(), cache);
    for (var n = 0; !work.cacheMiss; n++) {
      expect(n, lessThan(50000));
      work.advance(maxParts: 1, cachedOnly: true);
    }
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
    _finish(work, cache);
    work.takePlan();
    expect(cache.activeLeases, 0);
  });

  test('row contributions equal the actual rebased scene byte contract', () {
    final cache = _cache(), work = _work(_fixture(), cache);
    _finish(work, cache);
    final plan = work.takePlan();
    for (var start = 0; start < plan.lines.length; start++) {
      for (var end = start + 1; end <= plan.lines.length; end++) {
        final metadata = <Object, int>{};
        var bytes =
            ForumBodyTextPictureInput.baseEstimatedInputBytes +
            ForumBodyTextPictureInput.baseEstimatedPictureBytes;
        for (var row = start; row < end; row++) {
          final part = plan.sceneContributionForRow(row);
          expect(part.translationOriginY, isNull);
          bytes += part.inputCommandBytes + part.pictureCommandBytes;
          metadata.addAll(part.retainedMetadata);
        }
        bytes += metadata.values.fold<int>(0, (sum, value) => sum + value);
        expect(plan.parentPictureInput(start, end).estimatedBytes, bytes);
      }
    }
    expect(cache.activeLeases, 0);
  });

  test(
    'public flow entrance retains one actual source and prepares no paint',
    () {
      final cache = _cache();
      final document = const ForumBodyParser().parse(
        html: '<p>left<ruby>base<rt>note</rt></ruby>right</p>',
        sourceId: 'public-font-frames',
        conversionIdentity: 'none',
      );
      final flow = ForumBodyTextFlowCursor(
        document: document,
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: .5,
          ),
          fontRevision: 'public-font-frames',
          linkColor: const Color(0xff0000ff),
        ),
      );
      late ForumBodyInlineFlowContent source;
      try {
        while (!flow.isComplete) {
          flow.advance(maxEvents: 1);
          if (flow.current case ForumBodyTextFlowInline(:final content)) {
            source = content;
            break;
          }
        }
      } finally {
        flow.close();
      }
      final work = ForumBodyInlineFontFramePreparation.fromFlow(
        input: source,
        width: 300,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      addTearDown(work.close);
      _finish(work, cache);
      final measured = work.takeMeasurement();
      addTearDown(measured.close);
      expect(
        measured.plan.source.content.projection.display.text,
        'leftbasenoteright',
      );
      expect(measured.plan.source.content.identity, source.identity);
      expect(
        measured.natural.content.projection,
        same(measured.plan.source.content.projection),
      );
      expect(measured.plan.allocation.children, hasLength(1));
      expect(cache.pictureBuildCount, 0);
      measured.close();
      expect(cache.activeLeases, 0);
    },
  );

  test('retiring owner before transfer releases every measured resource', () {
    final cache = _cache();
    var active = true;
    final work = _work(
      _fixture(),
      cache,
      guard: () {
        if (!active) throw StateError('retired');
      },
    );
    _finish(work, cache);
    active = false;
    expect(work.takeMeasurement, throwsStateError);
    expect(work.nativeLeases, isEmpty);
    expect(cache.activeLeases, 0);
  });

  test('transferred paint checks the durable reader owner', () {
    final cache = _cache();
    var active = true;
    final work = _work(
      _fixture(),
      cache,
      guard: () {
        if (!active) throw StateError('retired');
      },
    );
    _finish(work, cache);
    final measured = work.takeMeasurement();
    addTearDown(measured.close);
    work.close();
    for (final phase in measured.paint.phases) {
      cache.prepareInlineParentPaint(phase);
    }
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    try {
      measured.paint.view.paintPhaseRow(
        canvas,
        Offset.zero,
        0,
        ForumBodyParagraphPaintLayer.foreground,
      );
      active = false;
      expect(
        () => measured.paint.view.paintPhaseRow(
          canvas,
          Offset.zero,
          0,
          ForumBodyParagraphPaintLayer.foreground,
        ),
        throwsStateError,
      );
    } finally {
      recorder.endRecording().dispose();
      measured.close();
    }
    expect(cache.activeLeases, 0);
  });

  test(
    'external pin waits in the same transaction and resumes after release',
    () {
      final fixture = _fixture(), cache = _cache(entries: 5);
      final pin = cache.acquire(
        content: fixture.input.content.contexts.first.content,
        width: 300,
      );
      addTearDown(pin.release);
      final work = _work(fixture, cache);
      var waiting = false;
      for (var n = 0; !waiting && n < 50000; n++) {
        waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      final before = cache.layoutBuildCount;
      expect(work.advance(maxParts: 32).waitingForLayoutBudget, isTrue);
      expect(cache.layoutBuildCount, before);
      pin.release();
      _finish(work, cache);
      work.takePlan();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'own full font prefix cannot wait forever for insufficient capacity',
    () {
      final fixture = _fixture(), cache = _cache(entries: 5);
      final pin = cache.acquire(
        content: fixture.input.content.contexts.first.content,
        width: 300,
      );
      addTearDown(pin.release);
      final work = _work(fixture, cache, owned: () => [pin]);
      expect(
        () {
          for (var n = 0; !work.isReady && n < 50000; n++) {
            final step = work.advance(maxParts: 1);
            expect(step.waitingForLayoutBudget, isFalse);
          }
        },
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(cache.activeLeases, 1);
      expect(pin.isActive, isTrue);
      expect(work.nativeLeases, isEmpty);
    },
  );

  test('intrinsic single-line input cannot use wrapping-frame admission', () {
    final fixture = _fixture(
          mode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        cache = _cache();
    expect(() => _work(fixture, cache), throwsArgumentError);
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, 0);
  });

  for (final child in [
    '<sup>2</sup>',
    'H<sub>2</sub>O',
    '<ruby>B<rt>b</rt></ruby> H<sub>2</sub>O',
  ]) {
    test(
      'mark-free allocation preserves actual neutral child frames $child',
      () {
        final fixture = _fixture(child: child), cache = _cache();
        final work = _work(fixture, cache);
        _finish(work, cache, quantum: 32);
        final plan = work.takePlan();
        final page = plan.allocation.input.natural.page;
        expect(plan.allocation.marks, isEmpty);
        expect(plan.allocation.children, hasLength(page.rubyAtoms.length));
        expect(
          page.rubyAtoms.any(
            (a) =>
                a is ForumBodyTextBaselineAtomPlan ||
                a is ForumBodyIntrinsicInlineAtomPlan,
          ),
          isTrue,
        );
        for (final child in plan.allocation.children) {
          if (child == null) continue;
          final row = plan.lines[child.lineIndex];
          expect(child.bounds.size, page.dimensions[child.atomIndex].size);
          expect(child.bounds.top, greaterThanOrEqualTo(row.top - 1e-6));
          expect(child.bounds.bottom, lessThanOrEqualTo(row.bottom + 1e-6));
        }
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'cancellation at every work-unit boundary releases only owned fonts',
    () {
      final fixture = _fixture(), cache = _cache();
      final measured = _work(fixture, cache);
      final parts = _finish(measured, cache);
      measured.takePlan();
      final before = cache.layoutBuildCount;
      for (var stop = 0; stop <= parts; stop++) {
        final work = ForumBodyInlineFontFramePreparation(
          input: fixture.input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        );
        try {
          for (var n = 0; n < stop && !work.isReady; n++) {
            work.advance(maxParts: 1, cachedOnly: true);
            expect(work.cacheMiss, isFalse);
          }
        } finally {
          work.close();
        }
        expect(work.nativeLeases, isEmpty);
        expect(cache.activeLeases, 0, reason: 'cancel at $stop of $parts');
      }
      expect(cache.layoutBuildCount, before);
      expect(cache.pictureBuildCount, 0);
    },
  );
}
