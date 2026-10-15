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
    return (cacheBytes ~/ (lowRam ? 8 : 12))
        .clamp(0, (lowRam ? 4 : 8) * mib)
        .toInt();
  }
}
