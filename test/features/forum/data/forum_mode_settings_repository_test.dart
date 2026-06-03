import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/forum/data/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';

void main() {
  late SharedPrefsForumModeSettingsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = SharedPrefsForumModeSettingsRepository();
  });

  test('loadMode defaults to webview when nothing stored', () async {
    expect(await repository.loadMode(), ForumShellMode.webview);
  });

  test('loadMode reads persisted webview and native values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppStorageKeys.forumShellMode: ForumShellMode.native.name,
    });
    repository = SharedPrefsForumModeSettingsRepository();

    expect(await repository.loadMode(), ForumShellMode.native);

    await repository.saveMode(ForumShellMode.webview);
    expect(await repository.loadMode(), ForumShellMode.webview);
  });

  test('loadMode falls back to webview for invalid value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppStorageKeys.forumShellMode: 'broken',
    });
    repository = SharedPrefsForumModeSettingsRepository();

    expect(await repository.loadMode(), ForumShellMode.webview);
  });
}
