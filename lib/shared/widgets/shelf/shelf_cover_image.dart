import 'package:flutter/material.dart';
import 'package:y300/core/media/image_downscale_policy.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/image_loading/domain/app_image_source.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';

/// Shelf cover image widget.
///
/// Phase 1 起，本控件改为委托统一的 [AppImage]，从而**自食其力**：本地封面
/// （预热/资产已落地）优先展示，缺失时直接用网络 URL 兜底加载并缓存，不再
/// 依赖书架预热队列“先喂路径”。这修复了“快滑看不到封面、停下才加载”。
///
/// 解码降采样由 [AppImage] + [downscalePolicy] 统一处理。
class ShelfCoverImage extends StatelessWidget {
  const ShelfCoverImage({
    super.key,
    required this.coverKey,
    this.localPath,
    this.remoteUrl,
    this.imageHeaderBuilder,
    required this.fit,
    this.width,
    this.height,
    this.downscalePolicy = const WidthBoundImageDownscalePolicy(),
    required this.placeholder,
    this.errorPlaceholder,
  });

  final String coverKey;
  final String? localPath;
  final String? remoteUrl;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageDownscalePolicy downscalePolicy;
  final Widget placeholder;
  final Widget? errorPlaceholder;

  @override
  Widget build(BuildContext context) {
    final remote = remoteUrl?.trim();
    final networkSource = (remote != null && remote.isNotEmpty)
        ? NetworkAppImageSource(url: remote, headerBuilder: imageHeaderBuilder)
        : null;
    return AppImage(
      key: ValueKey<String>('shelf-cover-$coverKey'),
      localPath: localPath,
      networkSource: networkSource,
      fit: fit,
      width: width,
      height: height,
      downscalePolicy: downscalePolicy,
      placeholder: placeholder,
      errorPlaceholder: errorPlaceholder,
    );
  }
}
