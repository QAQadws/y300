import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/presentation/app_update_messages.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  test('uses Y300 simplified Chinese update dialog copy', () {
    final messages = Y300UpgraderMessages(AppLocalizationsZh());

    expect(messages.languageCode, 'zh');
    expect(messages.title, '发现新版本');
    expect(
      messages.body,
      '{{appName}} v{{currentAppStoreVersion}} 已发布，当前版本为 '
      'v{{currentInstalledVersion}}',
    );
    expect(messages.prompt, '是否立即更新？');
    expect(messages.releaseNotes, '更新说明');
    expect(messages.buttonTitleIgnore, '忽略');
    expect(messages.buttonTitleLater, '关闭');
    expect(messages.buttonTitleUpdate, '更新');
  });

  test('maps every dialog message key to the custom copy', () {
    final messages = Y300UpgraderMessages(AppLocalizationsZh());

    expect(messages.message(UpgraderMessage.title), '发现新版本');
    expect(messages.message(UpgraderMessage.body), messages.body);
    expect(messages.message(UpgraderMessage.buttonTitleIgnore), '忽略');
    expect(messages.message(UpgraderMessage.buttonTitleLater), '关闭');
    expect(messages.message(UpgraderMessage.buttonTitleUpdate), '更新');
    expect(messages.message(UpgraderMessage.prompt), '是否立即更新？');
    expect(messages.message(UpgraderMessage.releaseNotes), '更新说明');
  });

  test('switches update dialog copy to Traditional Chinese', () {
    final messages = Y300UpgraderMessages(AppLocalizationsZh())
      ..updateLocalization(AppLocalizationsZhTw());

    expect(messages.title, '發現新版本');
    expect(messages.prompt, '是否立即更新？');
    expect(messages.releaseNotes, '更新說明');
    expect(messages.buttonTitleLater, '關閉');
  });
}
