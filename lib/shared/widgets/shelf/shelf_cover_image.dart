import 'dart:io' as io;

import 'package:flutter/material.dart';

/// Shelf-only cover image widget.
///
/// The shelf surface already has a background cover warmup pipeline, so this
/// widget deliberately avoids synchronous file checks and direct network
/// fallback. Missing local files fall back through Image.errorBuilder instead
/// of blocking build with `existsSync`.
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
  final Widget placeholder;
  final Widget? errorPlaceholder;

  @override
  Widget build(BuildContext context) {
    final local = localPath?.trim();
    if (local == null || local.isEmpty) {
      return placeholder;
    }

    final file = io.File(local);
    return Image.file(
      file,
      key: ValueKey<String>('shelf-cover-image-$coverKey-$local'),
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => errorPlaceholder ?? placeholder,
    );
  }
}
