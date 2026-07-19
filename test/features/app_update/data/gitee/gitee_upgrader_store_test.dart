import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/gitee/gitee_upgrader_store.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';

void main() {
  group('GiteeUpgraderStore', () {
    test('maps a Gitee candidate to UpgraderVersionInfo', () async {
      final repository = _FakeRepository(
        GiteeReleaseLookupSuccess(
          candidate: _candidate(),
          source: GiteeReleaseLookupSource.network,
        ),
      );
      final store = GiteeUpgraderStore(repository: repository);
      final installedVersion = Version(0, 0, 1);

      final info = await store.getVersionInfo(
        state: Upgrader().state,
        installedVersion: installedVersion,
        country: 'CN',
        language: 'zh',
      );

      expect(info.installedVersion, installedVersion);
      expect(info.appStoreVersion, Version(0, 0, 2));
      expect(
        info.appStoreListingURL,
        'https://gitee.com/QAQadws/y300-releases/releases/download/'
        'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
      );
      expect(info.releaseNotes, 'Release notes');
      expect(info.isCriticalUpdate, isNull);
      expect(info.minAppVersion, isNull);
      expect(repository.callCount, 1);
    });

    test('reports expected failures and returns safe empty info', () async {
      const failure = AppUpdateFailure(
        code: AppUpdateFailureCode.rateLimited,
        message: 'rate limited',
      );
      final reported = <AppUpdateFailure>[];
      final store = GiteeUpgraderStore(
        repository: _FakeRepository(
          const GiteeReleaseLookupFailure(
            failure: failure,
            source: GiteeReleaseLookupSource.network,
          ),
        ),
        onFailure: reported.add,
      );
      final installedVersion = Version(1, 0, 0);

      final info = await store.getVersionInfo(
        state: Upgrader().state,
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.installedVersion, installedVersion);
      expect(info.appStoreVersion, isNull);
      expect(info.appStoreListingURL, isNull);
      expect(reported, <AppUpdateFailure>[failure]);
    });

    test('contains unexpected repository exceptions', () async {
      final reported = <AppUpdateFailure>[];
      final store = GiteeUpgraderStore(
        repository: _ThrowingRepository(),
        onFailure: reported.add,
      );

      final info = await store.getVersionInfo(
        state: Upgrader().state,
        installedVersion: Version(1, 0, 0),
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, isNull);
      expect(reported.single.code, AppUpdateFailureCode.remoteUnavailable);
    });
  });
}

GiteeReleaseCandidate _candidate() {
  return GiteeReleaseCandidate(
    tag: 'v0.0.2',
    version: Version(0, 0, 2),
    apkUri: Uri.parse(
      'https://gitee.com/QAQadws/y300-releases/releases/download/'
      'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
    ),
    checksumUri: Uri.parse(
      'https://gitee.com/QAQadws/y300-releases/releases/download/'
      'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk.sha256',
    ),
    releaseNotes: 'Release notes',
  );
}

final class _FakeRepository implements GiteeLatestReleaseRepository {
  _FakeRepository(this.result);

  final GiteeReleaseLookupResult result;
  int callCount = 0;

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
    callCount += 1;
    return result;
  }
}

final class _ThrowingRepository implements GiteeLatestReleaseRepository {
  @override
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false}) {
    throw StateError('boom');
  }
}
