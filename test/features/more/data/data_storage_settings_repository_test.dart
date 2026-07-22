import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('cache limit uses the stable default when storage is empty', () async {
    final repository = DataStorageSettingsRepositoryImpl(
      storageLocationRepository: _FakeStorageLocationRepository(),
    );

    expect(
      await repository.getCacheMaxBytes(),
      DataStorageSettingsRepositoryImpl.defaultCacheMaxBytes,
    );
  });

  test(
    'cache limit migrates and normalizes the legacy image-only key',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'image_cache_max_bytes': 64 * 1024 * 1024,
      });
      final repository = DataStorageSettingsRepositoryImpl(
        storageLocationRepository: _FakeStorageLocationRepository(),
      );

      expect(
        await repository.getCacheMaxBytes(),
        DataStorageSettingsRepositoryImpl.minCacheMaxBytes,
      );

      final migratedPrefs = await SharedPreferences.getInstance();
      expect(
        migratedPrefs.getInt('storage.cache.max_bytes.v1'),
        DataStorageSettingsRepositoryImpl.minCacheMaxBytes,
      );

      await repository.setCacheMaxBytes(4096 * 1024 * 1024);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('storage.cache.max_bytes.v1'),
        DataStorageSettingsRepositoryImpl.maxCacheMaxBytes,
      );
      expect(prefs.getInt('image_cache_max_bytes'), 64 * 1024 * 1024);
    },
  );

  test(
    'new unified cache limit takes precedence over the legacy key',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'storage.cache.max_bytes.v1': 768 * 1024 * 1024,
        'image_cache_max_bytes': 256 * 1024 * 1024,
      });
      final repository = DataStorageSettingsRepositoryImpl(
        storageLocationRepository: _FakeStorageLocationRepository(),
      );

      expect(await repository.getCacheMaxBytes(), 768 * 1024 * 1024);
    },
  );
}

class _FakeStorageLocationRepository implements StorageLocationRepository {
  @override
  Future<String?> getCustomStorageRoot() async => null;

  @override
  Future<String> getDefaultStorageRoot() async => 'default';

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<void> setCustomStorageRoot(String? path) async {}
}
