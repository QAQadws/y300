import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

abstract interface class ForumImagePrecacheService {
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec);

  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  });
}

class ForumImagePrecacheResult {
  const ForumImagePrecacheResult({
    required this.success,
    this.fromDiskCache = false,
    this.decoded = false,
    this.cacheKey,
    this.localPath,
    this.error,
  });

  final bool success;
  final bool fromDiskCache;
  final bool decoded;
  final String? cacheKey;
  final String? localPath;
  final Object? error;

  static ForumImagePrecacheResult failed(Object error) {
    return ForumImagePrecacheResult(success: false, error: error);
  }
}
