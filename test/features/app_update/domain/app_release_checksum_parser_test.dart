import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/services/app_release_checksum_parser.dart';

import '../test_support/gitee_release_phase0_fixture.dart';

const _apkName = 'y300-v0.0.1-android-arm64-v8a-release.apk';
const _sha256 =
    'fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077';

void main() {
  const parser = AppReleaseChecksumParser();

  test('parses the observed canonical checksum asset', () async {
    final result = parser.parse(
      content: await loadGiteeLatestReleaseV001ChecksumFixture(),
      expectedFileName: _apkName,
    );

    expect(result, isA<AppReleaseChecksumParseSuccess>());
    final checksum = (result as AppReleaseChecksumParseSuccess).checksum;
    expect(checksum.sha256Hex, _sha256);
    expect(checksum.fileName, _apkName);
    expect(checksum.matchesDigest(_sha256), isTrue);
    expect(checksum.matchesDigest(_sha256.toUpperCase()), isTrue);
    expect(
      checksum.matchesDigest(List<String>.filled(64, '0').join()),
      isFalse,
    );
  });

  test('accepts one optional CRLF from standard checksum tools', () {
    final result = parser.parse(
      content: '$_sha256  $_apkName\r\n',
      expectedFileName: _apkName,
    );

    expect(result, isA<AppReleaseChecksumParseSuccess>());
  });

  test('rejects a checksum that names another file', () {
    final result = parser.parse(
      content: '$_sha256  another.apk',
      expectedFileName: _apkName,
    );

    expect(_failureCode(result), AppUpdateFailureCode.checksumFileNameMismatch);
  });

  test('rejects malformed, uppercase, multi-line, and oversized content', () {
    for (final content in <String>[
      '',
      '$_sha256 $_apkName',
      '${_sha256.toUpperCase()}  $_apkName',
      '$_sha256  $_apkName\nextra',
      List<String>.filled(
        AppReleaseChecksumParser.maxContentLength + 1,
        'x',
      ).join(),
    ]) {
      expect(
        _failureCode(
          parser.parse(content: content, expectedFileName: _apkName),
        ),
        AppUpdateFailureCode.checksumMalformed,
        reason: content.length.toString(),
      );
    }
  });
}

AppUpdateFailureCode _failureCode(AppReleaseChecksumParseResult result) {
  expect(result, isA<AppReleaseChecksumParseFailure>());
  return (result as AppReleaseChecksumParseFailure).failure.code;
}
