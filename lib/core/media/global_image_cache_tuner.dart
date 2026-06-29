import 'dart:io' show Platform;

import 'package:flutter/painting.dart' show ImageCache;

/// 配置运行时解码图片缓存（`PaintingBinding.instance.imageCache`）的字节预算。
///
/// ⚠️ 这与磁盘文件缓存的清理上限是**两件不同的事**：
/// - 本类设置的是 *运行时已解码 bitmap* 常驻内存的字节数
///   （`ImageCache.maximumSizeBytes`），决定“滚回去时图还在不在内存里”。
/// - `ImageCacheService.pruneToLimit` 管的是磁盘上缓存文件占多少空间。
///
/// 项目此前只配置了后者（见 `AppStorageKeys.imageCacheMaxBytes`），运行时解码
/// 缓存一直走 Flutter 默认值（约 100MB / 1000 张），是“来回滚动反复重解码”的
/// 主要根因之一。
///
/// 通过抽象 + 单一实现暴露，便于测试替身注入与未来按更细机型档位调整。
abstract class GlobalImageCacheTuner {
  /// 按设备内存档位返回建议的运行时解码缓存字节预算。
  int recommendedBudgetBytes();

  /// 将预算应用到给定的 [ImageCache]。在 `main()` 中对
  /// `PaintingBinding.instance.imageCache` 调用一次即可。
  void applyTo(ImageCache cache);
}

/// 基于平台粗略分档的默认实现。
///
/// 移动端无法在不引入额外依赖的前提下精确读取物理内存，这里采用保守的平台分档：
/// 桌面端内存充裕给到高档，移动端给中档，足以让“可见区 + 上下缓冲区”的解码
/// bitmap 常驻而不被驱逐。配合 [ImageDownscalePolicy] 降采样后，单张 bitmap 很小，
/// 该预算可容纳相当多的图片。
class PlatformImageCacheTuner implements GlobalImageCacheTuner {
  const PlatformImageCacheTuner();

  static const int _mb = 1024 * 1024;

  @override
  int recommendedBudgetBytes() {
    // 桌面端（开发/平板形态）内存充裕，给高档；移动端给中档。
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return 256 * _mb;
    }
    return 192 * _mb;
  }

  @override
  void applyTo(ImageCache cache) {
    cache.maximumSizeBytes = recommendedBudgetBytes();
  }
}
