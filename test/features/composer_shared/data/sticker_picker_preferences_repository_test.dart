import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/composer_shared/data/sticker_picker_preferences_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPreferencesStickerPickerPreferencesRepository', () {
    test('saves and loads last sticker group id', () async {
      final repository = SharedPreferencesStickerPickerPreferencesRepository();

      await repository.saveLastGroupId('bugcat');

      expect(await repository.loadLastGroupId(), 'bugcat');
    });

    test('ignores blank group id', () async {
      final repository = SharedPreferencesStickerPickerPreferencesRepository();

      await repository.saveLastGroupId('   ');

      expect(await repository.loadLastGroupId(), isNull);
    });
  });
}
