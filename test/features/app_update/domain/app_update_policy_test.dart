import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_decision.dart';
import 'package:y300/features/app_update/domain/models/installed_app_version.dart';
import 'package:y300/features/app_update/domain/services/app_update_policy.dart';

void main() {
  const policy = SemanticVersionAppUpdatePolicy();

  test('reports a higher semantic version as an available update', () {
    final release = _release('0.0.2');

    final decision = policy.evaluate(
      installed: _installed('0.0.1', versionCode: 4),
      latest: release,
    );

    expect(decision, isA<AppUpdateAvailable>());
    expect((decision as AppUpdateAvailable).release, same(release));
  });

  test('reports the same semantic version as up to date', () {
    final decision = policy.evaluate(
      installed: _installed('0.0.1', versionCode: 999),
      latest: _release('0.0.1'),
    );

    expect(decision, isA<AppUpToDate>());
    expect((decision as AppUpToDate).localVersionIsNewer, isFalse);
  });

  test('does not offer a downgrade to a lower remote version', () {
    final decision = policy.evaluate(
      installed: _installed('0.0.2', versionCode: 5),
      latest: _release('0.0.1'),
    );

    expect(decision, isA<AppUpToDate>());
    expect((decision as AppUpToDate).localVersionIsNewer, isTrue);
  });

  test('uses numeric SemVer ordering for multi-digit components', () {
    final decision = policy.evaluate(
      installed: _installed('1.0.9', versionCode: 19),
      latest: _release('1.0.10'),
    );

    expect(decision, isA<AppUpdateAvailable>());
  });
}

InstalledAppVersion _installed(String versionName, {required int versionCode}) {
  return InstalledAppVersion(
    packageName: 'com.adws.y300',
    versionName: versionName,
    semanticVersion: Version.parse(versionName),
    versionCode: versionCode,
  );
}

AppRelease _release(String versionName) {
  return AppRelease(
    tag: 'v$versionName',
    versionName: versionName,
    semanticVersion: Version.parse(versionName),
    title: 'Y300 $versionName',
    releaseNotes: '',
    releasePageUrl: Uri.parse('https://gitee.com/example/releases'),
    apk: AppReleaseAsset(
      name: 'y300-v$versionName-android-arm64-v8a-release.apk',
      downloadUrl: Uri.parse('https://gitee.com/example/release.apk'),
      abi: AppReleaseAbi.androidArm64V8a,
      checksum: AppReleaseChecksumAsset(
        name: 'y300-v$versionName-android-arm64-v8a-release.apk.sha256',
        downloadUrl: Uri.parse('https://gitee.com/example/release.apk.sha256'),
      ),
    ),
  );
}
