import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Thread-only resource defaults; the renderer does not inspect device/cache
/// providers and other HTML consumers do not inherit this opt-in policy.
final class ThreadImagePreloadPolicy {
  ThreadImagePreloadPolicy({
    required int imageCacheBudgetBytes,
    required bool isLowRamDevice,
  }) : layoutCacheExtent = ScrollCacheExtent.viewport(isLowRamDevice ? 1 : 3),
       maxVisibleFirstFrames = isLowRamDevice ? 2 : 4,
       maxConcurrentOptionalWork = isLowRamDevice ? 1 : 2,
       predecode = ForumHtmlImagePredecodePolicy(
         forwardImageCount: isLowRamDevice ? 1 : 3,
         decodeExtentFactor: isLowRamDevice ? 1 : 1.5,
         forwardDiskExtentFactor: isLowRamDevice ? 1 : 3,
         maxDecodedBytesPerImage: _perImageBudget(
           imageCacheBudgetBytes,
           isLowRamDevice,
         ),
       );

  final ScrollCacheExtent layoutCacheExtent;
  final int maxVisibleFirstFrames;
  final int maxConcurrentOptionalWork;
  final ForumHtmlImagePredecodePolicy predecode;

  static int _perImageBudget(int cacheBytes, bool lowRam) {
    const mib = 1024 * 1024;
    // This is an independent per-image admission limit, not a cumulative
    // window budget. More neighboring targets do not dilute their image size.
    // A normal comic page at high DPR can exceed 8 MiB after width-bound decode.
    return (cacheBytes ~/ 4).clamp(0, (lowRam ? 8 : 24) * mib).toInt();
  }
}
