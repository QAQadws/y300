import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_crop_geometry.dart';
import 'package:y300/core/media/cover_focal_point.dart';

void main() {
  const aspect = 2 / 3; // 封面：宽/高。

  group('CoverCropGeometry.cropSizeFor', () {
    test('wide image: crop height fills, width narrower (left/right movable)',
        () {
      // 原图 300x100，比封面更宽 → 裁剪框高=100，宽=100*2/3≈66.67。
      final crop = CoverCropGeometry.cropSizeFor(const Size(300, 100), aspect);
      expect(crop.height, 100);
      expect(crop.width, closeTo(66.67, 0.01));
    });

    test('tall image: crop width fills, height shorter (up/down movable)', () {
      // 原图 100x300，比封面更高 → 裁剪框宽=100，高=100/(2/3)=150。
      final crop = CoverCropGeometry.cropSizeFor(const Size(100, 300), aspect);
      expect(crop.width, 100);
      expect(crop.height, 150);
    });

    test('invalid inputs return zero', () {
      expect(CoverCropGeometry.cropSizeFor(Size.zero, aspect), Size.zero);
      expect(
        CoverCropGeometry.cropSizeFor(const Size(100, 100), 0),
        Size.zero,
      );
    });
  });

  group('focus <-> crop top-left round trip', () {
    test('wide image maps left/center/right correctly', () {
      const imageSize = Size(300, 100);
      final cropSize = CoverCropGeometry.cropSizeFor(imageSize, aspect);
      final freeX = imageSize.width - cropSize.width; // ~233.33

      // 最左 → x = -1.
      final left = CoverCropGeometry.focusFromCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: Offset.zero,
      );
      expect(left.x, closeTo(-1.0, 1e-9));
      expect(left.y, 0.0); // 高度无余量 → 居中。

      // 最右 → x = 1.
      final right = CoverCropGeometry.focusFromCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: Offset(freeX, 0),
      );
      expect(right.x, closeTo(1.0, 1e-9));

      // 居中 → x = 0.
      final center = CoverCropGeometry.focusFromCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: Offset(freeX / 2, 0),
      );
      expect(center.x, closeTo(0.0, 1e-9));
    });

    test('cropTopLeftFromFocus inverts focusFromCropTopLeft', () {
      const imageSize = Size(100, 300);
      final cropSize = CoverCropGeometry.cropSizeFor(imageSize, aspect);
      const focus = CoverFocalPoint(0, 0.5);
      final topLeft = CoverCropGeometry.cropTopLeftFromFocus(
        imageSize: imageSize,
        cropSize: cropSize,
        focus: focus,
      );
      final recovered = CoverCropGeometry.focusFromCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: topLeft,
      );
      expect(recovered.x, closeTo(focus.x, 1e-9));
      expect(recovered.y, closeTo(focus.y, 1e-9));
    });
  });

  group('clampCropTopLeft', () {
    test('keeps the crop box inside the image', () {
      const imageSize = Size(300, 100);
      final cropSize = CoverCropGeometry.cropSizeFor(imageSize, aspect);
      final clamped = CoverCropGeometry.clampCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: const Offset(9999, 9999),
      );
      expect(clamped.dx, closeTo(imageSize.width - cropSize.width, 1e-9));
      expect(clamped.dy, 0.0); // 高度无余量。

      final clampedNeg = CoverCropGeometry.clampCropTopLeft(
        imageSize: imageSize,
        cropSize: cropSize,
        cropTopLeft: const Offset(-50, -50),
      );
      expect(clampedNeg.dx, 0.0);
      expect(clampedNeg.dy, 0.0);
    });
  });
}
