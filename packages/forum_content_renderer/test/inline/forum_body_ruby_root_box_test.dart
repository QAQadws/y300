import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _RootScaler extends TextScaler {
  const _RootScaler();

  @override
  double scale(double size) => size < 20 ? size * 1.45 : size * 1.12;

  @override
  double get textScaleFactor => throw StateError('Use per-size values');
}

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
  final document = const ForumBodyParser().parse(
    html: '',
    sourceId: 'ruby-root-font-box',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: TextStyle(fontFamily: 'Ahem', fontSize: size, height: height),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final input = ForumBodyRubyRootBoxInput(
    rootPath: 'root',
    fontStrut: ForumBodyParagraphContent.anonymousInline(
      identity: styles.identity,
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: styles.root,
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
            scaler: nonlinear ? const _RootScaler() : TextScaler.noScaling,
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
}
