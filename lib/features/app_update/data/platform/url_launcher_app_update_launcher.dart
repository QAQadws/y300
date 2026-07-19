import 'package:url_launcher/url_launcher.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/services/app_update_apk_uri_policy.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';

typedef AppUpdateUrlLaunch = Future<bool> Function(Uri uri, LaunchMode mode);

final class UrlLauncherAppUpdateLauncher implements AppUpdateLauncher {
  UrlLauncherAppUpdateLauncher({
    AppUpdateApkUriPolicy uriPolicy = const AppUpdateApkUriPolicy(),
    AppUpdateUrlLaunch? launch,
  }) : _uriPolicy = uriPolicy,
       _launch = launch ?? _launchExternally;

  final AppUpdateApkUriPolicy _uriPolicy;
  final AppUpdateUrlLaunch _launch;

  @override
  Future<AppUpdateLaunchResult> openApk(Uri apkUri) async {
    if (!_uriPolicy.isAllowedApk(apkUri)) {
      return const AppUpdateLaunchFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.invalidAssetUrl,
          message: 'The update APK URL is not allowed.',
        ),
      );
    }

    try {
      final launched = await _launch(apkUri, LaunchMode.externalApplication);
      if (!launched) {
        return const AppUpdateLaunchFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.externalLaunchUnavailable,
            message: 'No external application could open the update URL.',
          ),
        );
      }
      return const AppUpdateLaunchSuccess();
    } on Object {
      return const AppUpdateLaunchFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.externalLaunchFailed,
          message: 'Opening the update URL failed.',
        ),
      );
    }
  }

  static Future<bool> _launchExternally(Uri uri, LaunchMode mode) {
    return launchUrl(uri, mode: mode);
  }
}
