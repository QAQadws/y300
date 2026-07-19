import 'package:upgrader/upgrader.dart';

/// Presentation-side capability used to distinguish an explicit manual check
/// from Upgrader's automatic startup evaluation.
abstract interface class AppUpdateManualPromptGate {
  void prepareManualPrompt();

  void cancelManualPrompt();
}

/// The single Upgrader instance owned by Y300.
///
/// A manual check is an explicit user request, so its next evaluation may
/// display an available update even when the automatic reminder interval or
/// ignored-version preference would suppress startup prompting. The saved
/// Upgrader settings are left untouched; the override lasts for one check only.
class Y300Upgrader extends Upgrader implements AppUpdateManualPromptGate {
  Y300Upgrader({
    super.durationUntilAlertAgain,
    super.messages,
    super.storeController,
  });

  bool _manualPromptPending = false;

  @override
  void prepareManualPrompt() {
    _manualPromptPending = true;
  }

  @override
  void cancelManualPrompt() {
    _manualPromptPending = false;
  }

  @override
  bool shouldDisplayUpgrade() {
    if (!_manualPromptPending) {
      return super.shouldDisplayUpgrade();
    }

    _manualPromptPending = false;
    final display = isUpdateAvailable();
    willDisplayUpgrade?.call(
      display: display,
      installedVersion: state.packageInfo?.version,
      versionInfo: versionInfo,
    );
    return display;
  }
}
