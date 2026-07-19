import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';

import '../test_support/gitee_release_phase0_fixture.dart';

void main() {
  test('maps a parsed Gitee candidate to a canonical artifact', () async {
    final parsed = GiteeReleaseParser().parse(
      await loadGiteeLatestReleaseV001Fixture(),
    );
    final candidate = (parsed as GiteeReleaseParseSuccess).candidate;

    final artifact = AppUpdateArtifact.fromCandidate(candidate);

    expect(artifact.fileName, 'y300-v0.0.1-android-arm64-v8a-release.apk');
    expect(
      artifact.checksumFileName,
      'y300-v0.0.1-android-arm64-v8a-release.apk.sha256',
    );
    expect(artifact.identityKey, contains('v0.0.1'));
    expect(artifact.releaseNotes, contains('Y300试发行'));
  });

  test('rejects a candidate that violates the canonical asset contract', () {
    final candidate = GiteeReleaseCandidate(
      tag: 'v0.0.1',
      version: Version(0, 0, 1),
      apkUri: Uri.parse(
        'https://gitee.com/QAQadws/y300-releases/releases/download/v0.0.1/not-an-apk.apk',
      ),
      checksumUri: Uri.parse(
        'https://gitee.com/QAQadws/y300-releases/releases/download/v0.0.1/not-an-apk.apk.sha256',
      ),
      releaseNotes: null,
    );

    expect(() => AppUpdateArtifact.fromCandidate(candidate), throwsStateError);
  });
}
