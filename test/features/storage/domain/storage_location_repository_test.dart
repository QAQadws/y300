import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('custom download root uses the stable key and trims values', () async {
    final repository = StorageLocationRepositoryImpl();

    expect(await repository.getCustomStorageRoot(), isNull);

    await repository.setCustomStorageRoot('  E:/Y300  ');
    expect(await repository.getCustomStorageRoot(), 'E:/Y300');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('download_storage_dir'), 'E:/Y300');

    await repository.setCustomStorageRoot('   ');
    expect(await repository.getCustomStorageRoot(), isNull);
    expect(prefs.containsKey('download_storage_dir'), isFalse);
  });
}
