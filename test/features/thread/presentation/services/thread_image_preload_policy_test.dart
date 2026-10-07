import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_image_preload_policy.dart';

void main() {
  test('balanced target budgets stay below a quarter of the global cache', () {
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
        final bytes = count * policy.predecode.maxDecodedBytesPerImage;
        expect(bytes, lessThanOrEqualTo(cache ~/ 4));
        expect(bytes, lessThanOrEqualTo((lowRam ? 8 : 24) * mib));
        expect(count, lowRam ? 2 : 3);
      }
    }
  });
}
