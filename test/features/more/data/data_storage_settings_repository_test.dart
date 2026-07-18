import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'image cache limit uses the stable default when storage is empty',
    () async {
      final repository = DataStorageSettingsRepositoryImpl(
        storageLocationRepository: _FakeStorageLocationRepository(),
      );

      expect(
        await repository.getImageCacheMaxBytes(),
        DataStorageSettingsRepositoryImpl.defaultImageCacheMaxBytes,
      );
    },
  );

  test(
    'image cache limit reads, normalizes, and writes the stable key',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'image_cache_max_bytes': 64 * 1024 * 1024,
      });
      final repository = DataStorageSettingsRepositoryImpl(
        storageLocationRepository: _FakeStorageLocationRepository(),
      );

      expect(
        await repository.getImageCacheMaxBytes(),
        DataStorageSettingsRepositoryImpl.minImageCacheMaxBytes,
      );

      await repository.setImageCacheMaxBytes(4096 * 1024 * 1024);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('image_cache_max_bytes'),
        DataStorageSettingsRepositoryImpl.maxImageCacheMaxBytes,
      );
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
