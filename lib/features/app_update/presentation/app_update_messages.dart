import 'package:upgrader/upgrader.dart';

/// Y300's update dialog copy.
///
/// The built-in Chinese messages in upgrader are not a good fit for the
/// product vocabulary, so this keeps the update dialog concise and stable
/// regardless of the device locale.
final class Y300UpgraderMessages extends UpgraderMessages {
  Y300UpgraderMessages() : super(code: 'zh');

  @override
  String get title => '发现新版本';

  @override
  String get body =>
      '{{appName}} v{{currentAppStoreVersion}} 已发布，当前版本为 '
      'v{{currentInstalledVersion}}';

  @override
  String get prompt => '是否立即更新？';

  @override
  String get releaseNotes => '更新说明';

  @override
  String get buttonTitleIgnore => '忽略';

  @override
  String get buttonTitleLater => '关闭';

  @override
  String get buttonTitleUpdate => '更新';
}
