import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_aware_resize_image.dart';

void main() {
  group('CoverAwareResizeImage.computeTargetSize', () {
    // 竖瓦片显示框：宽 100、高 150（物理像素）。
    final provider = CoverAwareResizeImage(
      const AssetImage('x'),
      boxWidth: 100,
      boxHeight: 150,
    );

    test('wide-short image decodes large enough to cover the box height', () {
      // 1000x300 的横长图：cover 缩放因子 = max(100/1000, 150/300) = 0.5。
      final target = provider.computeTargetSize(1000, 300);
      // 解码后高 = 300*0.5 = 150 >= 框高 150（关键：不再被上采样致模糊）。
      expect(target.height, 150);
      expect(target.width, 500);
    });

    test('tall image is bound by width', () {
      // 300x1000 竖图：cover 缩放 = max(100/300, 150/1000) = 0.333。
      final target = provider.computeTargetSize(300, 1000);
      expect(target.width, 100);
      expect(target.height, greaterThanOrEqualTo(150));
    });

    test('does not upscale when source is smaller than the box', () {
      // 50x60 小图：cover 缩放 > 1，但封顶 1 -> 按原尺寸解码。
      final target = provider.computeTargetSize(50, 60);
      expect(target.width, 50);
      expect(target.height, 60);
    });

    test('returns unbounded target for degenerate intrinsic size', () {
      final target = provider.computeTargetSize(0, 0);
      expect(target.width, isNull);
      expect(target.height, isNull);
    });
  });

  group('CoverAwareResizeImage.resizeIfNeeded', () {
    test('returns the base provider when a dimension is unknown', () {
      const base = AssetImage('x');
      final result = CoverAwareResizeImage.resizeIfNeeded(
        provider: base,
        logicalWidth: 100,
        logicalHeight: null,
        devicePixelRatio: 2,
      );
      expect(identical(result, base), isTrue);
    });

    test('wraps in cover-aware provider with physical-pixel box', () {
      const base = AssetImage('x');
      final result = CoverAwareResizeImage.resizeIfNeeded(
        provider: base,
        logicalWidth: 100,
        logicalHeight: 150,
        devicePixelRatio: 2,
      );
      expect(result, isA<CoverAwareResizeImage>());
      final cover = result as CoverAwareResizeImage;
      expect(cover.boxWidth, 200);
      expect(cover.boxHeight, 300);
    });
  });
}
