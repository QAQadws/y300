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
    this.diskCacheAttempted = false,
    this.decodePrecacheAttempted = false,
    this.cacheKey,
    this.localPath,
    this.error,
    this.failureReason,
  });

  final bool success;
  final bool fromDiskCache;
  final bool decoded;
  final bool diskCacheAttempted;
  final bool decodePrecacheAttempted;
  final String? cacheKey;
  final String? localPath;
  final Object? error;
  final String? failureReason;

  static ForumImagePrecacheResult failed(
    Object error, {
    String? failureReason,
    bool diskCacheAttempted = false,
    bool decodePrecacheAttempted = false,
  }) {
    return ForumImagePrecacheResult(
      success: false,
      error: error,
      failureReason: failureReason ?? error.runtimeType.toString(),
      diskCacheAttempted: diskCacheAttempted,
      decodePrecacheAttempted: decodePrecacheAttempted,
    );
  }
}
