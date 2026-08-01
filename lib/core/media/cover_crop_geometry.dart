import 'dart:ui';

import 'package:y300/core/media/cover_focal_point.dart';

/// `BoxFit.cover` 焦点选区的纯几何换算。
///
/// 模型：把整张原图按 `contain` 完整显示，在其上叠加一个**封面宽高比**的裁剪框
/// （即 cover 真正会展示的区域）。裁剪框是「能放进原图的、该宽高比的最大矩形」，
/// 用户拖动它来选定焦点。裁剪框中心 ↔ [Alignment]（`BoxFit.cover` 的 alignment）
/// 之间是线性双射，因此这里的换算同时服务“选区→保存的焦点”和“已存焦点→选区”。
///
/// 全部为纯函数，便于单测；不依赖任何 Widget。
class CoverCropGeometry {
  const CoverCropGeometry._();

  /// 在 [imageSize] 内、按 [aspectRatio]（宽/高）能容纳的最大裁剪框尺寸。
  ///
  /// 这正是 `BoxFit.cover` 实际展示的图像区域：图比框“宽”时按高对齐裁掉左右，
  /// 图比框“高”时按宽对齐裁掉上下。
  static Size cropSizeFor(Size imageSize, double aspectRatio) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        aspectRatio <= 0 ||
        !aspectRatio.isFinite) {
      return Size.zero;
    }
    final imageAspect = imageSize.width / imageSize.height;
    if (imageAspect > aspectRatio) {
      // 原图更宽：裁剪框高度撑满，宽度按比例，左右可移动。
      final cropHeight = imageSize.height;
      return Size(cropHeight * aspectRatio, cropHeight);
    }
    // 原图更高（或等比）：裁剪框宽度撑满，高度按比例，上下可移动。
    final cropWidth = imageSize.width;
    return Size(cropWidth, cropWidth / aspectRatio);
  }

  /// 由裁剪框左上角偏移换算归一化焦点（[-1,1]）。
  ///
  /// 某一维若无可移动余量（裁剪框等于原图该维），该维焦点取 0（居中）。
  static CoverFocalPoint focusFromCropTopLeft({
    required Size imageSize,
    required Size cropSize,
    required Offset cropTopLeft,
  }) {
    final freeX = imageSize.width - cropSize.width;
    final freeY = imageSize.height - cropSize.height;
    final x = freeX <= 0
        ? 0.0
        : ((cropTopLeft.dx / freeX) * 2 - 1).clamp(-1.0, 1.0).toDouble();
    final y = freeY <= 0
        ? 0.0
        : ((cropTopLeft.dy / freeY) * 2 - 1).clamp(-1.0, 1.0).toDouble();
    return CoverFocalPoint(x, y);
  }

  /// [focusFromCropTopLeft] 的逆运算：由已存焦点还原裁剪框左上角偏移。
  static Offset cropTopLeftFromFocus({
    required Size imageSize,
    required Size cropSize,
    required CoverFocalPoint focus,
  }) {
    final clamped = focus.clamped();
    final freeX = imageSize.width - cropSize.width;
    final freeY = imageSize.height - cropSize.height;
    final dx = freeX <= 0 ? 0.0 : (clamped.x + 1) / 2 * freeX;
    final dy = freeY <= 0 ? 0.0 : (clamped.y + 1) / 2 * freeY;
    return Offset(dx, dy);
  }

  /// 把裁剪框左上角夹紧到合法范围（不越出原图）。
  static Offset clampCropTopLeft({
    required Size imageSize,
    required Size cropSize,
    required Offset cropTopLeft,
  }) {
    final maxX = (imageSize.width - cropSize.width).clamp(0.0, double.infinity);
    final maxY = (imageSize.height - cropSize.height).clamp(
      0.0,
      double.infinity,
    );
    return Offset(
      cropTopLeft.dx.clamp(0.0, maxX).toDouble(),
      cropTopLeft.dy.clamp(0.0, maxY).toDouble(),
    );
  }
}
