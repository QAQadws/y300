import 'dart:io' show Platform;

import 'package:flutter/painting.dart' show ImageCache;
import 'package:y300/core/media/device_memory_profile.dart';

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

/// 使用既有 Android 普通/低内存标记与 memoryClass 估算图片 LRU 预算。
/// 未取得有效档位时沿平台默认值；不将其当作进程或 live 图片的内存上限。
class PlatformImageCacheTuner implements GlobalImageCacheTuner {
  const PlatformImageCacheTuner({this.deviceProfile});

  final DeviceMemoryProfile? deviceProfile;

  static const int _mb = 1024 * 1024;

  @override
  int recommendedBudgetBytes() {
    final profile = deviceProfile;
    final memoryClassMb = profile?.memoryClassMb;
    if (profile != null && memoryClassMb != null && memoryClassMb > 0) {
      if (profile.isLowRamDevice) {
        return (memoryClassMb * _mb * 0.08)
            .round()
            .clamp(16 * _mb, 48 * _mb)
            .toInt();
      }
      return (memoryClassMb * _mb * 0.15)
          .round()
          .clamp(64 * _mb, 192 * _mb)
          .toInt();
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return 256 * _mb;
    }
    return 96 * _mb;
  }

  @override
  void applyTo(ImageCache cache) {
    cache.maximumSizeBytes = recommendedBudgetBytes();
  }
}
