import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:y300/features/app_update/data/platform/url_launcher_app_update_launcher.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';

void main() {
  group('UrlLauncherAppUpdateLauncher', () {
    test('opens a canonical Gitee APK with an external application', () async {
      Uri? launchedUri;
      LaunchMode? launchedMode;
      final launcher = UrlLauncherAppUpdateLauncher(
        launch: (uri, mode) async {
          launchedUri = uri;
          launchedMode = mode;
          return true;
        },
      );

      final result = await launcher.openApk(_validApkUri);

      expect(result, isA<AppUpdateLaunchSuccess>());
      expect(launchedUri, _validApkUri);
      expect(launchedMode, LaunchMode.externalApplication);
    });

    test('rejects non-canonical URLs before launching', () async {
      var launchCalls = 0;
      final launcher = UrlLauncherAppUpdateLauncher(
        launch: (uri, mode) async {
          launchCalls += 1;
          return true;
        },
      );

      for (final uri in <Uri>[
        Uri.parse(
          'http://gitee.com/example/'
          'y300-v0.0.2-android-arm64-v8a-release.apk',
        ),
        Uri.parse(
          'https://example.com/example/'
          'y300-v0.0.2-android-arm64-v8a-release.apk',
        ),
        Uri.parse('https://gitee.com/example/not-y300.apk'),
        Uri.parse(
          'https://user@gitee.com/example/'
          'y300-v0.0.2-android-arm64-v8a-release.apk',
        ),
        Uri.parse(
          'https://gitee.com/example/'
          'y300-v0.0.2-android-arm64-v8a-release.apk#fragment',
        ),
      ]) {
        final result = await launcher.openApk(uri);
        expect(_failureCode(result), AppUpdateFailureCode.invalidAssetUrl);
      }

      expect(launchCalls, 0);
    });

    test('classifies unavailable handlers and launch exceptions', () async {
      final unavailable = UrlLauncherAppUpdateLauncher(
        launch: (uri, mode) async => false,
      );
      expect(
        _failureCode(await unavailable.openApk(_validApkUri)),
        AppUpdateFailureCode.externalLaunchUnavailable,
      );

      final failed = UrlLauncherAppUpdateLauncher(
        launch: (uri, mode) => throw StateError('failed'),
      );
      expect(
        _failureCode(await failed.openApk(_validApkUri)),
        AppUpdateFailureCode.externalLaunchFailed,
      );
    });
  });
}

final Uri _validApkUri = Uri.parse(
  'https://gitee.com/QAQadws/y300-releases/releases/download/'
  'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
);

AppUpdateFailureCode _failureCode(AppUpdateLaunchResult result) {
  expect(result, isA<AppUpdateLaunchFailure>());
  return (result as AppUpdateLaunchFailure).failure.code;
}
