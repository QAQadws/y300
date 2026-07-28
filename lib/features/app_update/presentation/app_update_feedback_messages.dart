import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/l10n/app_localizations.dart';

String appUpdateDownloadRequestFailureMessage(
  AppLocalizations l10n,
  AppUpdateFailureCode code,
) {
  return switch (code) {
    AppUpdateFailureCode.networkUnavailable =>
      l10n.appUpdateDownloadNetworkUnavailable,
    AppUpdateFailureCode.requestTimeout => l10n.appUpdateDownloadTimeout,
    AppUpdateFailureCode.invalidPayload => l10n.appUpdateDownloadInvalid,
    AppUpdateFailureCode.apkDownloadStartFailed =>
      l10n.appUpdateDownloadInProgress,
    _ => l10n.appUpdateDownloadFailed,
  };
}

String appUpdateCheckFailureMessage(
  AppLocalizations l10n,
  AppUpdateFailureCode code,
) {
  return switch (code) {
    AppUpdateFailureCode.networkUnavailable =>
      l10n.appUpdateCheckNetworkUnavailable,
    AppUpdateFailureCode.requestTimeout => l10n.appUpdateCheckTimeout,
    AppUpdateFailureCode.rateLimited => l10n.appUpdateCheckRateLimited,
    AppUpdateFailureCode.installedVersionUnavailable =>
      l10n.appUpdateInstalledVersionUnavailable,
    _ => l10n.appUpdateCheckFailed,
  };
}

String appUpdateLaunchFailureMessage(
  AppLocalizations l10n,
  AppUpdateFailureCode code,
) {
  return switch (code) {
    AppUpdateFailureCode.invalidAssetUrl => l10n.appUpdateInvalidUrl,
    AppUpdateFailureCode.externalLaunchUnavailable =>
      l10n.appUpdateBrowserUnavailable,
    AppUpdateFailureCode.externalLaunchFailed => l10n.appUpdateOpenUrlFailed,
    _ => l10n.appUpdateLaunchFailed,
  };
}
