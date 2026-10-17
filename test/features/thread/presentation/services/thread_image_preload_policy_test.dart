import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, Size;
import 'package:y300/core/media/image_downscale_policy.dart';
import 'package:y300/features/thread/presentation/services/thread_image_preload_policy.dart';

void main() {
  const mib = 1024 * 1024;

  test('additional neighbors do not dilute the per-image admission budget', () {
    for (final (cache, ordinaryBudget, lowRamBudget) in [
      (0, 0, 0),
      (16 * mib, 4 * mib, 4 * mib),
      (64 * mib, 16 * mib, 8 * mib),
      (96 * mib, 24 * mib, 8 * mib),
      (256 * mib, 24 * mib, 8 * mib),
    ]) {
      for (final lowRam in [false, true]) {
        final policy = ThreadImagePreloadPolicy(
          imageCacheBudgetBytes: cache,
          isLowRamDevice: lowRam,
        );
        final count =
            policy.predecode.forwardImageCount +
            policy.predecode.backwardImageCount;
        final perImage = policy.predecode.maxDecodedBytesPerImage;
        expect(perImage, lowRam ? lowRamBudget : ordinaryBudget);
        expect(count, lowRam ? 2 : 4);
        expect(
          policy.layoutCacheExtent,
          ScrollCacheExtent.viewport(lowRam ? 1 : 3),
        );
        expect(policy.maxVisibleFirstFrames, lowRam ? 2 : 4);
        expect(policy.maxConcurrentOptionalWork, lowRam ? 1 : 2);
        expect(policy.predecode.decodeExtentFactor, lowRam ? 1 : 1.5);
        expect(policy.predecode.forwardDiskExtentFactor, lowRam ? 1 : 3);
      }
    }
  });

  test(
    'a DPR 4 comic page is admitted with an ordinary 64 MiB image cache',
    () {
      final policy = ThreadImagePreloadPolicy(
        imageCacheBudgetBytes: 64 * mib,
        isLowRamDevice: false,
      );
      final bytes = estimateWidthBoundDecodedBytes(
        intrinsicSize: const Size(2688, 3860),
        displaySize: const Size(336, 800),
        devicePixelRatio: 4,
      );

      expect(bytes, 10375680);
      expect(
        bytes,
        lessThanOrEqualTo(policy.predecode.maxDecodedBytesPerImage),
      );
    },
  );

  test('extreme long images remain outside both device admission limits', () {
    final bytes = estimateWidthBoundDecodedBytes(
      intrinsicSize: const Size(2000, 100000),
      displaySize: const Size(336, 800),
      devicePixelRatio: 4,
    );

    expect(bytes, isNotNull);
    for (final lowRam in [false, true]) {
      final policy = ThreadImagePreloadPolicy(
        imageCacheBudgetBytes: 256 * mib,
        isLowRamDevice: lowRam,
      );
      expect(bytes, greaterThan(policy.predecode.maxDecodedBytesPerImage));
    }
  });

  test('small source images are admitted without estimating DPR upscaling', () {
    final bytes = estimateWidthBoundDecodedBytes(
      intrinsicSize: const Size(300, 450),
      displaySize: const Size(336, 800),
      devicePixelRatio: 4,
    );

    expect(bytes, 300 * 450 * 4);
    for (final lowRam in [false, true]) {
      final policy = ThreadImagePreloadPolicy(
        imageCacheBudgetBytes: 16 * mib,
        isLowRamDevice: lowRam,
      );
      expect(
        bytes,
        lessThanOrEqualTo(policy.predecode.maxDecodedBytesPerImage),
      );
    }
  });
}
