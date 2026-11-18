import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/presentation/app_update_messages.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  test('updater uses the current locale for every dialog message', () {
    final simplified = AppLocalizationsZh();
    final messages = Y300UpgraderMessages(simplified);
    expect(messages.languageCode, simplified.localeName);

    for (final l10n in [simplified, AppLocalizationsZhTw()]) {
      messages.updateLocalization(l10n);
      final expected = {
        UpgraderMessage.title: l10n.appUpdateDialogTitle,
        UpgraderMessage.body: l10n.appUpdateDialogBody(
          '{{appName}}',
          '{{currentAppStoreVersion}}',
          '{{currentInstalledVersion}}',
        ),
        UpgraderMessage.prompt: l10n.appUpdateDialogPrompt,
        UpgraderMessage.releaseNotes: l10n.appUpdateDialogReleaseNotes,
        UpgraderMessage.buttonTitleIgnore: l10n.appUpdateDialogIgnore,
        UpgraderMessage.buttonTitleLater: l10n.appUpdateDialogLater,
        UpgraderMessage.buttonTitleUpdate: l10n.appUpdateDialogUpdate,
      };
      for (final entry in expected.entries) {
        expect(
          messages.message(entry.key),
          entry.value,
          reason: '${l10n.localeName}: ${entry.key}',
        );
      }
    }
  });
}
