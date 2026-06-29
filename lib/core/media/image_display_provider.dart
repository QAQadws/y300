import 'package:flutter/painting.dart';
import 'package:y300/core/media/cover_aware_resize_image.dart';
import 'package:y300/core/media/image_downscale_policy.dart';

/// 统一决定“某图片实际用哪个降采样后的 [ImageProvider] 来解码显示”。
///
/// 把“按 fit 选择降采样策略”这件事收敛到一处，供 AppImage / LibraryCachedImage
/// 等显示控件复用，避免各自散写：
/// - `BoxFit.cover`（封面/填充）：用 [CoverAwareResizeImage]，按 cover 缩放因子解码，
///   修复横长竖短图被上采样导致的模糊。
/// - 其它 fit（contain/列表缩略图等）：用宽度优先的 [ImageDownscalePolicy] +
///   [ResizeImage]，缩进框内即可。
///
/// 注意：返回的是**用于显示**的 provider。需要上报原始分辨率（如帖子图布局提示）
/// 时，应对未包裹的 [base] provider 解析尺寸，而非这里的返回值。
ImageProvider resolveDownscaledImageProvider({
  required ImageProvider base,
  required BoxFit fit,
  required Size displaySize,
  required double devicePixelRatio,
  ImageDownscalePolicy downscalePolicy = const WidthBoundImageDownscalePolicy(),
}) {
  if (fit == BoxFit.cover) {
    return CoverAwareResizeImage.resizeIfNeeded(
      provider: base,
      logicalWidth: displaySize.width,
      logicalHeight: displaySize.height,
      devicePixelRatio: devicePixelRatio,
    );
  }
  final target = downscalePolicy.resolve(
    displaySize: displaySize,
    devicePixelRatio: devicePixelRatio,
  );
  return ResizeImage.resizeIfNeeded(target.cacheWidth, target.cacheHeight, base);
}
