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
}
