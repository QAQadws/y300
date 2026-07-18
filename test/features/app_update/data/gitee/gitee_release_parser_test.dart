import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  final parser = GiteeReleaseParser();

  group('GiteeReleaseParser Phase 0 fixture', () {
    test('locks the redacted response and signed APK baseline', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final metadata = payload['FixtureMetadata'] as Map;

      expect(payload, isNot(contains('draft')));
      expect(payload, isNot(contains('published_at')));
      expect(payload, isNot(contains('html_url')));
      expect(metadata['apkSizeBytes'], 31215750);
      expect(metadata['checksumSizeBytes'], 107);
      expect(
        metadata['apkSha256'],
        'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077',
      );
      expect(
        metadata['signingCertificateSha256'],
        '6c3f720b52f587142c156543b20208de775372928201b590758bb4be6f7c8d68',
      );
      expect((payload['author'] as Map)['login'], 'redacted');
    });

    test('maps the observed stable release and exact arm64 APK', () async {
      final result = parser.parse(await loadGiteeLatestReleaseV001Fixture());

      expect(result, isA<GiteeReleaseParseSuccess>());
      final release = (result as GiteeReleaseParseSuccess).release;
      expect(release.tag, 'v0.0.1');
      expect(release.versionName, '0.0.1');
      expect(release.semanticVersion, Version(0, 0, 1));
      expect(release.title, 'v0.0.1');
      expect(release.releaseNotes, contains('Y300试发行'));
      expect(release.releasedAt, DateTime.utc(2026, 7, 18, 12, 53, 49));
      expect(
        release.releasePageUrl.toString(),
        'https://gitee.com/QAQadws/y300-releases/releases',
      );
      expect(release.apk.name, 'y300-v0.0.1-android-arm64-v8a-release.apk');
      expect(release.apk.abi, AppReleaseAbi.androidArm64V8a);
      expect(release.apk.sizeBytes, isNull);
      expect(release.apk.downloadUrl.scheme, 'https');
      expect(release.apk.downloadUrl.host, 'gitee.com');
      expect(
        release.apk.checksum.name,
        'y300-v0.0.1-android-arm64-v8a-release.apk.sha256',
      );
      expect(release.apk.checksum.downloadUrl.scheme, 'https');
      expect(release.apk.checksum.downloadUrl.host, 'gitee.com');
    });

    test('ignores source archives and unknown supplier fields', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      payload['future_supplier_field'] = <String, Object?>{'nested': true};

      final result = parser.parse(payload);

      expect(result, isA<GiteeReleaseParseSuccess>());
      expect(
        (result as GiteeReleaseParseSuccess).release.apk.name,
        endsWith('-android-arm64-v8a-release.apk'),
      );
    });

    test('allows absent notes and an unusable optional timestamp', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      payload['name'] = '';
      payload['body'] = null;
      payload['created_at'] = <String>[];

      final result = parser.parse(payload);

      expect(result, isA<GiteeReleaseParseSuccess>());
      final release = (result as GiteeReleaseParseSuccess).release;
      expect(release.title, 'v0.0.1');
      expect(release.releaseNotes, isEmpty);
      expect(release.releasedAt, isNull);
    });
  });

  group('GiteeReleaseParser protocol rejection', () {
    for (final tag in <String>[
      '0.0.1',
      'v0.0',
      'v00.0.1',
      'v0.0.1+4',
      'v0.0.1-beta',
      'v 0.0.1',
    ]) {
      test('rejects non-canonical tag $tag', () async {
        final payload = await loadGiteeLatestReleaseV001Fixture();
        payload['tag_name'] = tag;

        expect(
          _failureCode(parser.parse(payload)),
          AppUpdateFailureCode.invalidTag,
        );
      });
    }

    test('rejects a prerelease', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      payload['prerelease'] = true;

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.prerelease,
      );
    });

    test(
      'rejects a missing exact APK while ignoring source archives',
      () async {
        final payload = await loadGiteeLatestReleaseV001Fixture();
        payload['assets'] = (payload['assets'] as List)
            .where(
              (asset) =>
                  (asset as Map)['name'] !=
                  'y300-v0.0.1-android-arm64-v8a-release.apk',
            )
            .toList();

        expect(
          _failureCode(parser.parse(payload)),
          AppUpdateFailureCode.assetMissing,
        );
      },
    );

    test('rejects duplicate exact APK assets', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final assets = List<Object?>.from(payload['assets'] as List);
      assets.add(Map<String, dynamic>.from(assets.first as Map));
      payload['assets'] = assets;

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.assetAmbiguous,
      );
    });

    test('rejects a non-HTTPS exact APK URL', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final apk = (payload['assets'] as List).first as Map;
      apk['browser_download_url'] = 'http://gitee.com/example/y300-v0.0.1.apk';

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.invalidAssetUrl,
      );
    });

    test('rejects a missing checksum asset', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      payload['assets'] = (payload['assets'] as List)
          .where(
            (asset) =>
                !(asset as Map)['name'].toString().endsWith('.apk.sha256'),
          )
          .toList();

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.checksumAssetMissing,
      );
    });

    test('rejects duplicate exact checksum assets', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final assets = List<Object?>.from(payload['assets'] as List);
      final checksumAsset = assets.singleWhere(
        (asset) => (asset as Map)['name'].toString().endsWith('.apk.sha256'),
      );
      assets.add(Map<String, dynamic>.from(checksumAsset as Map));
      payload['assets'] = assets;

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.checksumAssetAmbiguous,
      );
    });

    test('rejects a non-HTTPS checksum URL', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final checksumAsset =
          (payload['assets'] as List).singleWhere(
                (asset) =>
                    (asset as Map)['name'].toString().endsWith('.apk.sha256'),
              )
              as Map;
      checksumAsset['browser_download_url'] =
          'http://gitee.com/example/release.apk.sha256';

      expect(
        _failureCode(parser.parse(payload)),
        AppUpdateFailureCode.invalidChecksumAssetUrl,
      );
    });

    test('classifies missing and mistyped required fields', () async {
      final missingTag = await loadGiteeLatestReleaseV001Fixture();
      missingTag.remove('tag_name');
      expect(
        _failureCode(parser.parse(missingTag)),
        AppUpdateFailureCode.missingRequiredField,
      );

      final mistypedPrerelease = await loadGiteeLatestReleaseV001Fixture();
      mistypedPrerelease['prerelease'] = 'false';
      expect(
        _failureCode(parser.parse(mistypedPrerelease)),
        AppUpdateFailureCode.invalidFieldType,
      );

      expect(
        _failureCode(parser.parse(<Object?>[])),
        AppUpdateFailureCode.invalidPayload,
      );
    });
  });
}

AppUpdateFailureCode _failureCode(GiteeReleaseParseResult result) {
  expect(result, isA<GiteeReleaseParseFailure>());
  return (result as GiteeReleaseParseFailure).failure.code;
}
