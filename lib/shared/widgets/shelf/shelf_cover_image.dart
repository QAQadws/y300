import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/media/image_downscale_policy.dart';

/// Shelf-only cover image widget.
///
/// The shelf surface already has a background cover warmup pipeline, so this
/// widget deliberately avoids synchronous file checks and direct network
/// fallback. Missing local files fall back through Image.errorBuilder instead
/// of blocking build with `existsSync`.
///
/// 解码降采样：默认通过 [downscalePolicy] 按实际显示尺寸把封面解码到合适像素，
/// 避免按原图解码出超大 bitmap 撑爆运行时图片缓存。调用方仍可显式传
/// [cacheWidth]/[cacheHeight] 覆盖策略结果。
class ShelfCoverImage extends StatelessWidget {
  const ShelfCoverImage({
    super.key,
    required this.coverKey,
    this.localPath,
    this.remoteUrl,
    required this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.downscalePolicy = const WidthBoundImageDownscalePolicy(),
    required this.placeholder,
    this.errorPlaceholder,
  });

  final String coverKey;
  final String? localPath;
  final String? remoteUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageDownscalePolicy downscalePolicy;
  final Widget placeholder;
  final Widget? errorPlaceholder;

  @override
  Widget build(BuildContext context) {
    final local = localPath?.trim();
    if (local == null || local.isEmpty) {
      return placeholder;
    }

    final file = io.File(local);
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = _resolveDecodeTarget(context, constraints);
        return Image.file(
          file,
          key: ValueKey<String>('shelf-cover-image-$coverKey-$local'),
          fit: fit,
          width: width,
          height: height,
          cacheWidth: cacheWidth ?? target.cacheWidth,
          cacheHeight: cacheHeight ?? target.cacheHeight,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              errorPlaceholder ?? placeholder,
        );
      },
    );
  }

  ImageDecodeTarget _resolveDecodeTarget(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return downscalePolicy.resolve(
      displaySize: Size(
        _finiteOr(width, constraints.maxWidth),
        _finiteOr(height, constraints.maxHeight),
      ),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  /// 取 [preferred]（若为有限正值），否则回退到布局约束 [fallback]，
  /// 都不可用时返回 NaN，交由策略判定为“无界、不降采样”。
  double _finiteOr(double? preferred, double fallback) {
    if (preferred != null && preferred.isFinite) {
      return preferred;
    }
    return fallback.isFinite ? fallback : double.nan;
  }
}
