import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/device_memory_profile.dart';
import 'package:y300/core/media/global_image_cache_tuner.dart';

void main() {
  test(
    'ordinary profile increases the byte floor without changing item limits',
    () {
      final cache = ImageCache()
        ..maximumSize = 17
        ..maximumSizeBytes = 48 * 1024 * 1024;
      const tuner = PlatformImageCacheTuner(
        deviceProfile: DeviceMemoryProfile(
          isLowRamDevice: false,
          memoryClassMb: 256,
        ),
      );

      tuner.applyTo(cache);

      expect(cache.maximumSizeBytes, 64 * 1024 * 1024);
      expect(cache.maximumSize, 17);
    },
  );

  test(
    'larger profiles remain capped and low-memory profiles keep their range',
    () {
      for (final lowRam in [false, true]) {
        final cache = ImageCache();
        PlatformImageCacheTuner(
          deviceProfile: DeviceMemoryProfile(
            isLowRamDevice: lowRam,
            memoryClassMb: 2048,
          ),
        ).applyTo(cache);
        expect(cache.maximumSizeBytes, (lowRam ? 48 : 192) * 1024 * 1024);
      }
      expect(
        const PlatformImageCacheTuner(
          deviceProfile: DeviceMemoryProfile(
            isLowRamDevice: true,
            memoryClassMb: 128,
          ),
        ).recommendedBudgetBytes(),
        16 * 1024 * 1024,
      );
    },
  );
}
