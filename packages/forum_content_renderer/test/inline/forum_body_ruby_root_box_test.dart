import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_emphasis_fixture.dart';

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyRubyRootFontBox _font(
  ForumBodyParagraphCache cache, {
  double size = 20,
  double height = 1,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final content = rubyEmphasisFixture(
    text: '',
    emphasis: 'none',
    size: size,
    height: height,
  ).base;
  final input = ForumBodyRubyRootBoxInput(
    rootPath: 'root',
    fontStrut: ForumBodyParagraphContent.anonymousInline(
      identity: content.identity,
      fontRevision: content.fontRevision,
      styleRevision: content.styleRevision,
      style: content.style,
    ),
  );
  final lease = cache.acquire(
    content: input.fontStrut,
    width: 16384,
    textScaler: scaler,
  );
  try {
    return ForumBodyRubyRootFontBox(
      input: input,
      height: lease.layout.height,
      alphabeticBaseline: lease.layout.alphabeticBaseline,
    );
  } finally {
    lease.release();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final height in [.25, 1.0, 3.0]) {
    for (final nonlinear in [false, true]) {
      test(
        'origin-based frames retain exact previous geometry $height $nonlinear',
        () {
          final font = _font(
            _cache(),
            size: 28,
            height: height,
            scaler: nonlinear
                ? const RubyEmphasisNonlinearScaler()
                : TextScaler.noScaling,
          );
          for (final width in [0.0, 13.125, 16384.0]) {
            for (final size in [20.5, 180.25]) {
              for (final baseline in [0.0, 10.375, size]) {
                final frame = font.enclose(
                  childSize: Size(width, size),
                  childBaseline: baseline,
                );
                final ascent = math.max(baseline, font.alphabeticBaseline);
                final descent = math.max(
                  size - baseline,
                  font.height - font.alphabeticBaseline,
                );
                expect(frame.size, Size(width, ascent + descent));
                expect(frame.baseline, ascent);
                expect(frame.childTop, ascent - baseline);
                expect(frame.childOffset, Offset(0, ascent - baseline));
                expect(frame.childBounds, Rect.fromLTWH(0, 0, width, size));
                expect(frame.dimensions.size, frame.size);
                expect(frame.dimensions.baselineOffset, frame.baseline);
              }
            }
          }
        },
      );
    }
  }
  for (final height in [.25, 1.0, 3.0]) {
    test(
      'arbitrary origin is enclosed by union at the actual baseline $height',
      () {
        final cache = _cache(), font = _font(cache, size: 28, height: height);
        final before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        );
        for (final origin in [
          const Offset(-12.25, -28.375),
          const Offset(7.75, 13.5),
          const Offset(-1000.125, 1030.625),
        ]) {
          for (final baselineOffset in [0.0, 10.25, 70.75]) {
            final bounds = origin & const Size(89.375, 70.75);
            final baseline = bounds.top + baselineOffset;
            final rootBand = Rect.fromLTRB(
              bounds.left,
              baseline - font.alphabeticBaseline,
              bounds.right,
              baseline - font.alphabeticBaseline + font.height,
            );
            final union = bounds.expandToInclude(rootBand);
            final frame = font.encloseBounds(
              childBounds: bounds,
              childBaseline: baseline,
            );
            expect(frame.size.width, union.width);
            expect(frame.size.height, closeTo(union.height, 1e-8));
            expect(frame.childOffset.dx, -union.left);
            expect(frame.childOffset.dy, closeTo(-union.top, 1e-8));
            expect(frame.baseline, closeTo(baseline - union.top, 1e-8));
            expect(
              frame.childOffset.dy + baseline,
              closeTo(frame.baseline, 1e-8),
            );
            final positioned = bounds.shift(frame.childOffset);
            expect(positioned.left, 0);
            expect(positioned.top, greaterThanOrEqualTo(-1e-8));
            expect(positioned.right, frame.size.width);
            expect(
              positioned.bottom,
              lessThanOrEqualTo(frame.size.height + 1e-8),
            );
            expect(frame.childBounds, bounds);
          }
        }
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        ), before);
      },
    );
  }
  test(
    'invalid envelope, baseline and resulting size cannot enter a frame',
    () {
      final font = _font(_cache());
      for (final bounds in [
        const Rect.fromLTRB(double.nan, 0, 20, 20),
        const Rect.fromLTRB(0, double.infinity, 20, 20),
        const Rect.fromLTRB(0, 0, double.infinity, 20),
        const Rect.fromLTRB(0, 0, 20, double.nan),
        const Rect.fromLTRB(10, 0, 0, 20),
        const Rect.fromLTRB(0, 20, 10, 0),
        const Rect.fromLTRB(0, 0, 10, 0),
        const Rect.fromLTWH(-1, 0, 16385, 20),
        const Rect.fromLTWH(0, -16385, 20, 16386),
      ]) {
        expect(
          () => font.encloseBounds(childBounds: bounds, childBaseline: 0),
          throwsArgumentError,
        );
      }
      for (final baseline in [double.nan, double.infinity, -20.01, 20.01]) {
        expect(
          () => font.encloseBounds(
            childBounds: const Rect.fromLTRB(-3, -20, 20, 20),
            childBaseline: baseline,
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'actual wide emphasis envelope keeps glyph, mark and root coordinates',
    () {
      final cache = _cache();
      final fixture = rubyEmphasisFixture(text: 'A', emphasis: "'Aःःः' red");
      final line = measureRubyEmphasisLine(cache, content: fixture);
      final group = measureRubyEmphasisGroup(
        cache,
        line,
        fixture: fixture,
        empty: true,
      );
      final geometryJob = ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {},
      );
      while (!geometryJob.isReady) {
        geometryJob.advance(maxParts: 1);
      }
      final geometry = geometryJob.takeGeometry();
      expect(geometry.bounds.width, greaterThan(group.size.width));
      expect(geometry.bounds.left, lessThan(0));
      final font = _font(cache, height: 3);
      final frame = font.encloseBounds(
        childBounds: geometry.bounds,
        childBaseline: group.baseline,
      );
      final planJob = ForumBodyRubyBaseEmphasisPlanPreparation(
        geometry: geometry,
        ensureOwner: () {},
      );
      while (!planJob.isReady) {
        planJob.advance(maxParts: 1);
      }
      final plan = planJob.takePlan();
      final scene = ForumBodyRubyBaseEmphasisScenePreparation(
        input: line.input,
        plan: plan,
        cache: cache,
        ensureOwner: () {},
        width: line.requestWidth,
        expectedTextScaler: line.textScaler,
      );
      addTearDown(scene.close);
      while (!scene.isReady) {
        final step = scene.advance(maxParts: 1);
        expect(
          step.nativeLayoutsBuilt + step.picturesRecorded,
          lessThanOrEqualTo(1),
        );
        expect(step.waitingForLayoutBudget, isFalse);
      }
      final view = scene.takeLayout();
      addTearDown(view.close);
      final offset = frame.childOffset;
      expect(offset.dx, greaterThan(0));
      final placed = geometry.bounds.shift(offset);
      expect(placed.left, 0);
      expect(placed.right, frame.size.width);
      expect(offset.dy + group.baseline, closeTo(frame.baseline, 1e-8));
      final glyph = view.selectionBoxes(0, view.projection.text.length).single;
      final inRoot = glyph.toRect().shift(offset);
      final marker = geometry.marks.single.fontBounds.shift(offset);
      expect(marker.left, greaterThanOrEqualTo(0));
      expect(marker.right, lessThanOrEqualTo(frame.size.width));
      // The new root translation is inverted once; it never changes the native
      // source or interprets marker bytes as reader text.
      final hit = view.sourceAt(marker.center - offset);
      expect(hit.isExact, isFalse);
      expect(hit.displayUtf16, 0);
      expect(view.selectionBoxes(0, 1).single.toRect().shift(offset), inRoot);
      final recorder = ui.PictureRecorder();
      view.paint(Canvas(recorder), offset);
      recorder.endRecording().dispose();
      expect(cache.activeLeases, 2);
    },
  );
}
