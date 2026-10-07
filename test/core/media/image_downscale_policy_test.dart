import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/image_downscale_policy.dart';

void main() {
  group('WidthBoundImageDownscalePolicy', () {
    const policy = WidthBoundImageDownscalePolicy();

    test('decodes to display width times device pixel ratio', () {
      final target = policy.resolve(
        displaySize: const Size(100, 200),
        devicePixelRatio: 3,
      );
      expect(target.cacheWidth, 300);
      // 高度不约束，按宽度等比解码即可。
      expect(target.cacheHeight, isNull);
    });

    test('clamps to max decode width to avoid oversized bitmaps', () {
      const clamped = WidthBoundImageDownscalePolicy(maxDecodeWidth: 512);
      final target = clamped.resolve(
        displaySize: const Size(1000, 1000),
        devicePixelRatio: 3,
      );
      expect(target.cacheWidth, 512);
    });

    test('returns unbounded target when width is not finite', () {
      final target = policy.resolve(
        displaySize: const Size(double.nan, 200),
        devicePixelRatio: 3,
      );
      expect(target.isUnbounded, isTrue);
    });

    test('treats non-positive device pixel ratio as 1x', () {
      final target = policy.resolve(
        displaySize: const Size(120, 120),
        devicePixelRatio: 0,
      );
      expect(target.cacheWidth, 120);
    });
  });

  group('estimateWidthBoundDecodedBytes', () {
    test('uses intrinsic ratio and DPR instead of the placeholder height', () {
      for (final layoutHeight in [160.0, 10000.0, double.nan]) {
        expect(
          estimateWidthBoundDecodedBytes(
            intrinsicSize: const Size(1920, 1080),
            displaySize: Size(320, layoutHeight),
            devicePixelRatio: 2,
          ),
          640 * 360 * 4,
        );
      }
    });

    test('does not upscale a source narrower than the decode target', () {
      expect(
        estimateWidthBoundDecodedBytes(
          intrinsicSize: const Size(100, 75),
          displaySize: const Size(320, 240),
          devicePixelRatio: 3,
        ),
        100 * 75 * 4,
      );
    });

    test('shares the display width cap and rounds long-image height up', () {
      expect(
        estimateWidthBoundDecodedBytes(
          intrinsicSize: const Size(6000, 3001),
          displaySize: const Size(2000, 1000),
          devicePixelRatio: 3,
        ),
        2048 * 1025 * 4,
      );
      expect(
        estimateWidthBoundDecodedBytes(
          intrinsicSize: const Size(2000, 100000),
          displaySize: const Size(320, 160),
          devicePixelRatio: 2,
        ),
        640 * 32000 * 4,
      );
    });

    test('unknown or malformed inputs cannot pass memory admission', () {
      for (final intrinsic in [
        Size.zero,
        const Size(200, double.nan),
        const Size(double.infinity, 100),
        const Size(1, 1e308),
      ]) {
        expect(
          estimateWidthBoundDecodedBytes(
            intrinsicSize: intrinsic,
            displaySize: const Size(320, 160),
            devicePixelRatio: 2,
          ),
          isNull,
        );
      }
      for (final width in [0.0, -1.0, double.nan, double.infinity, 1e308]) {
        expect(
          estimateWidthBoundDecodedBytes(
            intrinsicSize: const Size(400, 200),
            displaySize: Size(width, 160),
            devicePixelRatio: 2,
          ),
          isNull,
        );
      }
      for (final dpr in [double.nan, double.infinity]) {
        expect(
          estimateWidthBoundDecodedBytes(
            intrinsicSize: const Size(400, 200),
            displaySize: const Size(320, 160),
            devicePixelRatio: dpr,
          ),
          isNull,
        );
      }
    });
  });
}
