import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/app_update_checksum_parser.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  const expectedFileName = 'y300-v0.0.1-android-arm64-v8a-release.apk';
  const parser = AppUpdateChecksumParser();

  test(
    'parses the canonical checksum fixture with a trailing newline',
    () async {
      final result = parser.parse(
        await loadGiteeLatestReleaseV001ChecksumFixture(),
        expectedFileName: expectedFileName,
      );

      expect(result, isA<AppUpdateChecksumParseSuccess>());
      final checksum = (result as AppUpdateChecksumParseSuccess).checksum;
      expect(
        checksum.sha256,
        'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077',
      );
      expect(checksum.fileName, expectedFileName);
    },
  );

  test('normalizes uppercase hexadecimal digests', () {
    final result = parser.parse(
      'FBF38C93718F0709363C2EB26D613030B87D78F984329A87B24A05E79F547077  '
      '$expectedFileName\r\n',
      expectedFileName: expectedFileName,
    );

    expect(result, isA<AppUpdateChecksumParseSuccess>());
    expect(
      (result as AppUpdateChecksumParseSuccess).checksum.sha256,
      'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077',
    );
  });

  test('rejects a checksum filename mismatch', () {
    final result = parser.parse(
      'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077  other.apk\n',
      expectedFileName: expectedFileName,
    );

    expect(
      (result as AppUpdateChecksumParseFailure).failure.code,
      AppUpdateFailureCode.checksumFileNameMismatch,
    );
  });

  test('rejects malformed, multi-line and oversized responses', () {
    final malformed = parser.parse(
      'not-a-checksum\n',
      expectedFileName: expectedFileName,
    );
    final multiLine = parser.parse(
      'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077  '
      '$expectedFileName\nextra\n',
      expectedFileName: expectedFileName,
    );
    final oversized = parser.parse(
      'x' * (AppUpdateChecksumParser.maxChecksumCharacters + 1),
      expectedFileName: expectedFileName,
    );

    expect(
      (malformed as AppUpdateChecksumParseFailure).failure.code,
      AppUpdateFailureCode.checksumMalformed,
    );
    expect(
      (multiLine as AppUpdateChecksumParseFailure).failure.code,
      AppUpdateFailureCode.checksumMalformed,
    );
    expect(
      (oversized as AppUpdateChecksumParseFailure).failure.code,
      AppUpdateFailureCode.checksumContentTooLarge,
    );
  });
}
