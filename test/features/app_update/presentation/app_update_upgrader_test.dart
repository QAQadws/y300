import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/presentation/app_update_upgrader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual prompt bypasses the reminder interval for one check', () {
    final upgrader = _ReminderIntervalUpgrader();
    addTearDown(upgrader.dispose);

    expect(upgrader.isTooSoon(), isTrue);
    expect(upgrader.shouldDisplayUpgrade(), isFalse);

    upgrader.prepareManualPrompt();

    expect(upgrader.shouldDisplayUpgrade(), isTrue);
    expect(upgrader.isTooSoon(), isTrue);
    expect(upgrader.shouldDisplayUpgrade(), isFalse);
  });
}

final class _ReminderIntervalUpgrader extends Y300Upgrader {
  @override
  bool isUpdateAvailable() => true;

  @override
  bool isTooSoon() => true;
}
