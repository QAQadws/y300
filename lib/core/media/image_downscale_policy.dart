import 'dart:ui';

/// 解码目标像素尺寸。
///
/// `null` 表示该维度不限制（按原图解码）。配合 [ImageDownscalePolicy] 使用，
/// 把“图片显示多大”与“图片解码到多大”两件事解耦——显示控件只需要拿到
/// 这个值塞给 `Image` 的 `cacheWidth`/`cacheHeight`，无需自己做 `* dpr` 之类的计算。
class ImageDecodeTarget {
  const ImageDecodeTarget({this.cacheWidth, this.cacheHeight});

  final int? cacheWidth;
  final int? cacheHeight;

  /// 不做任何降采样（按原始分辨率解码）。
  static const ImageDecodeTarget none = ImageDecodeTarget();

  bool get isUnbounded => cacheWidth == null && cacheHeight == null;
}

/// 将“显示尺寸 + 设备像素比”翻译成解码目标像素。
///
/// 存在意义：一张大图按原图解码成 bitmap 会按像素面积吃满运行时图片缓存
/// （`PaintingBinding.instance.imageCache`），导致 LRU 频繁驱逐、滚动回看时
/// 反复重新解码。把解码尺寸收敛到“实际显示尺寸”后，同样的内存预算可容纳
/// 数十倍的图片，来回滚动即可命中缓存而不重解码。
///
/// 该抽象是 Strategy 模式：不同场景（封面、竖向阅读页、缩略图）可替换具体策略，
/// 而显示控件只持有抽象、不感知策略细节。
abstract class ImageDownscalePolicy {
  const ImageDownscalePolicy();

  ImageDecodeTarget resolve({
    required Size displaySize,
    required double devicePixelRatio,
  });
}

/// 按“显示宽度 × 设备像素比”限制解码宽度，高度按比例自动缩放。
///
/// 适用于宽度受限的绝大多数场景：书架封面、竖向阅读页、列表缩略图、头像等。
/// 这些场景下宽度由布局约束确定，高度随图片纵横比变化，因此只约束宽度即可，
/// 既保证清晰度（按物理像素解码）又避免超大 bitmap。
///
/// [maxDecodeWidth] 是安全上限，避免在异常大的显示宽度或高 DPR 下解码出
/// 过大的 bitmap。
class WidthBoundImageDownscalePolicy extends ImageDownscalePolicy {
  const WidthBoundImageDownscalePolicy({this.maxDecodeWidth = 2048});

  final int maxDecodeWidth;

  @override
  ImageDecodeTarget resolve({
    required Size displaySize,
    required double devicePixelRatio,
  }) {
    final width = displaySize.width;
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    if (!width.isFinite || width <= 0) {
      // 宽度未知（无界约束）时不强行降采样，交回原图，避免解码出错误尺寸。
      return ImageDecodeTarget.none;
    }
    final target = (width * dpr).round().clamp(1, maxDecodeWidth);
    return ImageDecodeTarget(cacheWidth: target);
  }
}
