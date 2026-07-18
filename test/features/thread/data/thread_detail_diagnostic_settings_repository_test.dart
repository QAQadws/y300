import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/thread/data/repositories/thread_detail_diagnostic_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'scroll diagnostics default to disabled and use the stable key',
    () async {
      final repository = SharedPrefsThreadDetailDiagnosticSettingsRepository();

      expect(await repository.loadScrollDiagnosticEnabled(), isFalse);

      await repository.setScrollDiagnosticEnabled(true);
      expect(await repository.loadScrollDiagnosticEnabled(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('thread_detail_scroll_diagnostic_enabled'), isTrue);
    },
  );
}
