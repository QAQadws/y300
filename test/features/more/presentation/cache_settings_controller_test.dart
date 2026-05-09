import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/more/data/more_settings_repository.dart';
import 'package:y300/features/more/presentation/cache_settings_controller.dart';

void main() {
  test('loads default/effective directory from repository', () async {
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(
          _FakeMoreSettingsRepository(
            defaultDir: 'C:/default-cache',
            customDir: null,
          ),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(cacheSettingsControllerProvider.future);
    expect(state.defaultDirectory, 'C:/default-cache');
    expect(state.customDirectory, isNull);
    expect(state.effectiveDirectory, 'C:/default-cache');
  });

  test('choose custom directory updates effective directory', () async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: 'C:/default-cache',
      customDir: null,
      pickedDir: 'D:/comic-cache',
    );
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(cacheSettingsControllerProvider.future);
    await container.read(cacheSettingsControllerProvider.notifier).chooseCustomDirectory();

    final value = container.read(cacheSettingsControllerProvider).value!;
    expect(value.customDirectory, 'D:/comic-cache');
    expect(value.effectiveDirectory, 'D:/comic-cache');
  });

  test('restore default clears custom directory', () async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: 'C:/default-cache',
      customDir: 'D:/comic-cache',
    );
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(cacheSettingsControllerProvider.future);
    await container.read(cacheSettingsControllerProvider.notifier).restoreDefaultDirectory();

    final value = container.read(cacheSettingsControllerProvider).value!;
    expect(value.customDirectory, isNull);
    expect(value.effectiveDirectory, 'C:/default-cache');
  });
}

class _FakeMoreSettingsRepository implements MoreSettingsRepository {
  _FakeMoreSettingsRepository({
    required String defaultDir,
    String? customDir,
    String? pickedDir,
  })  : _defaultDir = defaultDir,
        _customDir = customDir,
        _pickedDir = pickedDir;

  final String _defaultDir;
  String? _customDir;
  final String? _pickedDir;
  int _maxBytes = 512 * 1024 * 1024;

  @override
  Future<String> getDefaultCacheDirectory() async => _defaultDir;

  @override
  Future<String?> getCustomCacheDirectory() async => _customDir;

  @override
  Future<String?> pickDirectory() async => _pickedDir;

  @override
  Future<void> setCustomCacheDirectory(String? path) async {
    _customDir = path;
  }

  @override
  Future<int> getImageCacheMaxBytes() async => _maxBytes;

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    _maxBytes = bytes;
  }
}

class _FakeImageCacheService implements ImageCacheService {
  int usageBytes = 0;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return usageBytes;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    if (usageBytes > maxBytes) {
      usageBytes = maxBytes;
    }
  }

  @override
  Future<void> clearUnprotected() async {
    usageBytes = 0;
  }
}
