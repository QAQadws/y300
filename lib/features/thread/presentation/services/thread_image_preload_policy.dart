import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Thread-only resource defaults; the renderer does not inspect device/cache
/// providers and other HTML consumers do not inherit this opt-in policy.
final class ThreadImagePreloadPolicy {
  ThreadImagePreloadPolicy({
    required int imageCacheBudgetBytes,
    required bool isLowRamDevice,
  }) : layoutCacheExtent = ScrollCacheExtent.viewport(isLowRamDevice ? 1 : 2),
       predecode = ForumHtmlImagePredecodePolicy(
         forwardImageCount: isLowRamDevice ? 1 : 2,
         forwardDiskExtentFactor: isLowRamDevice ? 1 : 2,
         maxDecodedBytesPerImage: _perImageBudget(
           imageCacheBudgetBytes,
           isLowRamDevice,
         ),
       );

  final ScrollCacheExtent layoutCacheExtent;
  final ForumHtmlImagePredecodePolicy predecode;

  static int _perImageBudget(int cacheBytes, bool lowRam) {
    const mib = 1024 * 1024;
    final cap = (lowRam ? 8 : 24) * mib;
    final available = (cacheBytes ~/ 4).clamp(0, cap);
    return available ~/ (lowRam ? 2 : 3);
  }
}
