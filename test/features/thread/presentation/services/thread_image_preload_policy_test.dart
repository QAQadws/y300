import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/thread/presentation/services/thread_image_preload_policy.dart';

void main() {
  test('additional neighbors do not dilute the per-image admission budget', () {
    const mib = 1024 * 1024;
    for (final cache in [0, 16 * mib, 96 * mib, 256 * mib]) {
      for (final lowRam in [false, true]) {
        final policy = ThreadImagePreloadPolicy(
          imageCacheBudgetBytes: cache,
          isLowRamDevice: lowRam,
        );
        final count =
            policy.predecode.forwardImageCount +
            policy.predecode.backwardImageCount;
        final perImage = policy.predecode.maxDecodedBytesPerImage;
        expect(perImage, lessThanOrEqualTo(cache ~/ (lowRam ? 8 : 12)));
        expect(perImage, lessThanOrEqualTo((lowRam ? 4 : 8) * mib));
        if (cache >= 96 * mib) expect(perImage, (lowRam ? 4 : 8) * mib);
        expect(count, lowRam ? 2 : 4);
        expect(
          policy.layoutCacheExtent,
          ScrollCacheExtent.viewport(lowRam ? 1 : 3),
        );
        expect(policy.maxVisibleFirstFrames, lowRam ? 2 : 4);
        expect(policy.maxConcurrentOptionalWork, lowRam ? 1 : 2);
        expect(policy.predecode.forwardDiskExtentFactor, lowRam ? 1 : 3);
      }
    }
  });
}
