import 'dart:io' as io;

import 'package:flutter/material.dart';

/// Shared image widget for library surfaces.
///
/// It always prefers an existing local file.  Network URLs are treated as a
/// fallback display source only; persistence into the stage-04 cache is handled
/// by repositories/services so UI widgets do not own cache policy.
class LibraryCachedImage extends StatelessWidget {
  const LibraryCachedImage({
    super.key,
    this.localPath,
    this.imageUrl,
    required this.fit,
    this.width,
    this.height,
    required this.placeholder,
  });

  final String? localPath;
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) {
      final file = io.File(local);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      }
    }

    final remote = imageUrl?.trim();
    if (remote != null && remote.isNotEmpty) {
      return Image.network(
        remote,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    return placeholder;
  }
}
