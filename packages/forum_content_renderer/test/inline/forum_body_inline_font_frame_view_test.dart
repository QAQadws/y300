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

MixedEmphasisParentFixture _fixture(
  TextDirection dir,
) => MixedEmphasisParentFixture(
  '<ruby>B<rt>b</rt></ruby>',
  direction: dir,
  parentStyle: 'white-space:pre-wrap;line-height:.25',
  prefix: '<span style="color:red">AA</span>\nCC',
  suffix:
      '\n<span style="color:green">DD</span>\n<span style="color:blue">EE</span>',
);

ForumBodyInlineFontFrameMeasurement _measure(
  MixedEmphasisParentFixture fixture,
  ForumBodyParagraphCache cache,
  TextScaler scaler,
) {
  final work = ForumBodyInlineFontFramePreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(10000));
      work.advance(maxParts: 32);
    }
    return work.takeMeasurement();
  } finally {
    work.close();
  }
}

({ForumBodyInlineParagraphView view, int parts}) _view(
  ForumBodyInlineFontFrameMeasurement measured,
  ForumBodyParagraphCache cache,
  TextScaler scaler, {
  int start = 0,
  int? end,
  bool cachedOnly = false,
  void Function()? guard,
}) {
  final work = ForumBodyInlineFontFrameViewPreparation(
    measurement: measured,
    cache: cache,
    textScaler: scaler,
    startLine: start,
    endLine: end,
    ensureOwner: guard ?? () {},
  );
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(10000));
      final before = cache.layoutBuildCount + cache.pictureBuildCount;
      final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, 1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      expect(
        cache.layoutBuildCount + cache.pictureBuildCount - before,
        lessThanOrEqualTo(1),
      );
      parts += step.partsPrepared;
    }
    final view = work.takeView();
    addTearDown(view.close);
    expect(work.nativeLeases, isEmpty);
    return (view: view, parts: parts);
  } finally {
    work.close();
  }
}

Future<Map<int, int>> _pixels(ForumBodyInlineParagraphView view) async {
  final recorder = ui.PictureRecorder();
  view.paint(Canvas(recorder), Offset.zero);
  final drawing = recorder.endRecording(),
      image = await drawing.toImage(view.width.ceil(), view.height.ceil());
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = <int, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) == 0) continue;
      pixels.update(bytes.getUint32(i), (n) => n + 1, ifAbsent: () => 1);
    }
    return pixels;
  } finally {
    image.dispose();
    drawing.dispose();
  }
}

int _sourceChecks(ForumBodyInlineParagraphView view) {
  final display = view.content.projection.display;
  var hits = 0;
  for (final context in view.content.contexts) {
    final start = context.startUtf16.clamp(
          view.coverageStartUtf16,
          view.coverageEndUtf16,
        ),
        end = context.endUtf16.clamp(
          view.coverageStartUtf16,
          view.coverageEndUtf16,
        );
    if (start >= end) continue;
    for (final range in display.graphemeRanges(
      startUtf16: start,
      endUtf16: end,
    )) {
      for (final box in view.glyphBoxes(range.startUtf16, range.endUtf16)) {
        if (box.toRect().isEmpty) continue;
        // Isolated native TextBoxes retain Float32 coordinates before their
        // physical translation; preserve those raw boxes instead of clipping.
        expect(box.top, greaterThanOrEqualTo(-1e-3));
        expect(box.bottom, lessThanOrEqualTo(view.height + 1e-3));
        final hit = view.sourceHitAt(box.toRect().center);
        expect(hit.window, same(context));
        expect(hit.position.isExact, isTrue);
        expect(hit.position.displayUtf16, inInclusiveRange(start, end));
        hits++;
      }
    }
  }
  return hits;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final dir in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      test(
        'complete allocated inline view keeps source/selection/font frames $dir $scaler',
        () {
          final fixture = _fixture(dir), cache = _cache();
          final measured = _measure(fixture, cache, scaler),
              plan = measured.plan;
          final view = _view(measured, cache, scaler).view;
          expect(measured.isActive, isFalse);
          expect(view.isActive, isTrue);
          expect(view.height, plan.height);
          expect(
            view.content.projection,
            same(fixture.input.content.projection),
          );
          expect(view.lines, hasLength(plan.lines.length));
          expect(_sourceChecks(view), greaterThanOrEqualTo(10));
          final shapes = cache.layoutBuildCount,
              pictures = cache.pictureBuildCount;
          final recorder = ui.PictureRecorder();
          view.paint(Canvas(recorder), Offset.zero);
          recorder.endRecording().dispose();
          view.selectionBoxes(0, view.coverageEndUtf16);
          expect(
            (cache.layoutBuildCount, cache.pictureBuildCount),
            (shapes, pictures),
          );
          cache.clearUnpinned();
          expect(view.isActive, isTrue);
          expect(_sourceChecks(view), greaterThanOrEqualTo(10));
          view.close();
          expect(cache.activeLeases, 0);
        },
      );
    }
    test(
      'whole and individual row pictures preserve complete parent and ruby ink $dir',
      () async {
        final fixture = _fixture(dir), cache = _cache();
        final measured = _measure(fixture, cache, TextScaler.noScaling),
            plan = measured.plan;
        final view = _view(measured, cache, TextScaler.noScaling).view;
        expect(await _pixels(view), {
          0xff0000ff: 800,
          0x123456ff: 1300,
          0x008000ff: 800,
          0x0000ffff: 800,
        });
        view.close();
        final combined = StringBuffer();
        final expected = [
          {0xff0000ff: 800},
          {0x123456ff: 1300},
          {0x008000ff: 800},
          {0x0000ffff: 800},
        ];
        for (var row = 0; row < plan.lines.length; row++) {
          final current = _measure(fixture, cache, TextScaler.noScaling);
          final part = _view(
            current,
            cache,
            TextScaler.noScaling,
            start: row,
            end: row + 1,
          ).view;
          expect(await _pixels(part), expected[row]);
          _sourceChecks(part);
          combined.write(
            part.content.projection.display.text.substring(
              part.coverageStartUtf16,
              part.coverageEndUtf16,
            ),
          );
          part.close();
        }
        expect(
          combined.toString(),
          fixture.input.content.projection.display.text,
        );
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('warm visible transaction is cache-only without new native work', () {
    final fixture = _fixture(TextDirection.ltr), cache = _cache();
    _view(
      _measure(fixture, cache, TextScaler.noScaling),
      cache,
      TextScaler.noScaling,
    ).view.close();
    final measurement = _measure(fixture, cache, TextScaler.noScaling);
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final view = _view(
      measurement,
      cache,
      TextScaler.noScaling,
      cachedOnly: true,
    ).view;
    expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
    expect(_sourceChecks(view), greaterThanOrEqualTo(10));
    view.close();
    expect(cache.activeLeases, 0);
  });

  test(
    'durable owner survives temporary preparation and rejects retired queries',
    () {
      final fixture = _fixture(TextDirection.ltr), cache = _cache();
      var active = true;
      final view = _view(
        _measure(fixture, cache, TextScaler.noScaling),
        cache,
        TextScaler.noScaling,
        guard: () {
          if (!active) throw StateError('retired');
        },
      ).view;
      expect(_sourceChecks(view), greaterThanOrEqualTo(10));
      active = false;
      expect(() => view.sourceHitAt(Offset.zero), throwsStateError);
      expect(() => view.glyphBoxes(0, 1), throwsStateError);
      view.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'cancel at each visible work-unit boundary releases actual owned resources',
    () {
      final fixture = _fixture(TextDirection.ltr), cache = _cache();
      final complete = _view(
        _measure(fixture, cache, TextScaler.noScaling),
        cache,
        TextScaler.noScaling,
      );
      complete.view.close();
      for (var stop = 0; stop <= complete.parts; stop++) {
        final measured = _measure(fixture, cache, TextScaler.noScaling);
        final work = ForumBodyInlineFontFrameViewPreparation(
          measurement: measured,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        );
        final before = (cache.layoutBuildCount, cache.pictureBuildCount);
        try {
          for (var n = 0; n < stop && !work.isReady; n++) {
            final step = work.advance(maxParts: 1, cachedOnly: true);
            expect(step.waitingForLayoutBudget, isFalse);
            expect(work.cacheMiss, isFalse);
          }
        } finally {
          work.close();
        }
        expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
        expect(
          cache.activeLeases,
          0,
          reason: 'cancel at $stop of ${complete.parts}',
        );
        expect(work.nativeLeases, isEmpty);
      }
    },
  );

  test('retire at ready refuses late transfer and releases complete view', () {
    final fixture = _fixture(TextDirection.ltr), cache = _cache();
    var active = true;
    final work = ForumBodyInlineFontFrameViewPreparation(
      measurement: _measure(fixture, cache, TextScaler.noScaling),
      cache: cache,
      textScaler: TextScaler.noScaling,
      ensureOwner: () {
        if (!active) throw StateError('retired');
      },
    );
    while (!work.isReady) {
      work.advance(maxParts: 32);
    }
    active = false;
    expect(work.takeView, throwsStateError);
    expect(work.nativeLeases, isEmpty);
    expect(cache.activeLeases, 0);
  });

  test('foreign measured owner is rejected before any new native work', () {
    final fixture = _fixture(TextDirection.ltr),
        source = _cache(),
        foreign = _cache();
    final measured = _measure(fixture, source, TextScaler.noScaling);
    expect(
      () => ForumBodyInlineFontFrameViewPreparation(
        measurement: measured,
        cache: foreign,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      ),
      throwsStateError,
    );
    expect(source.activeLeases, 0);
    expect(foreign.layoutBuildCount, 0);
    expect(foreign.activeLeases, 0);
  });

  test(
    'actual external pin waits and releasing it resumes the same page work',
    () {
      final fixture = _fixture(TextDirection.ltr), cache = _cache(entries: 7);
      final pin = cache.acquire(
        content: fixture.input.content.contexts.first.content,
        width: 300,
      );
      addTearDown(pin.release);
      final measured = _measure(fixture, cache, TextScaler.noScaling);
      final work = ForumBodyInlineFontFrameViewPreparation(
        measurement: measured,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      addTearDown(work.close);
      var waiting = false;
      for (var n = 0; !waiting && !work.isReady && n < 20000; n++) {
        waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      expect(work.advance(maxParts: 32).waitingForLayoutBudget, isTrue);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      pin.release();
      while (!work.isReady) {
        work.advance(maxParts: 1);
      }
      final view = work.takeView();
      try {
        expect(_sourceChecks(view), greaterThanOrEqualTo(10));
      } finally {
        view.close();
      }
      expect(cache.activeLeases, 0);
    },
  );
}
