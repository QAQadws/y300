import 'package:upgrader/upgrader.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Y300's update dialog copy.
///
/// The built-in Chinese messages in upgrader are not a good fit for the
/// product vocabulary, so this keeps the update dialog concise and stable
/// regardless of the device locale.
final class Y300UpgraderMessages extends UpgraderMessages {
  Y300UpgraderMessages(this._l10n) : super(code: _l10n.localeName);

  AppLocalizations _l10n;

  void updateLocalization(AppLocalizations l10n) {
    _l10n = l10n;
  }

  @override
  String get title => _l10n.appUpdateDialogTitle;

  @override
  String get body => _l10n.appUpdateDialogBody(
    '{{appName}}',
    '{{currentAppStoreVersion}}',
    '{{currentInstalledVersion}}',
  );

  @override
  String get prompt => _l10n.appUpdateDialogPrompt;

  @override
  String get releaseNotes => _l10n.appUpdateDialogReleaseNotes;

  @override
  String get buttonTitleIgnore => _l10n.appUpdateDialogIgnore;

  @override
  String get buttonTitleLater => _l10n.appUpdateDialogLater;

  @override
  String get buttonTitleUpdate => _l10n.appUpdateDialogUpdate;
}
