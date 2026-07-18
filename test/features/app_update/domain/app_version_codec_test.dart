import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:y300/features/app_update/domain/services/app_version_codec.dart';

void main() {
  const codec = AppVersionCodec();

  test('parses stable three-component version names and release tags', () {
    expect(codec.parseVersionName('0.0.1'), Version(0, 0, 1));
    expect(codec.parseReleaseTag('v1.0.10'), Version(1, 0, 10));
    expect(codec.canonicalTag(Version(2, 3, 4)), 'v2.3.4');
  });

  test('rejects non-canonical or decorated versions', () {
    for (final value in <String>[
      '',
      '1.0',
      '01.0.0',
      '1.0.0-beta',
      '1.0.0+5',
      'v1.0.0',
      ' 1.0.0',
    ]) {
      expect(codec.parseVersionName(value), isNull, reason: value);
    }
    for (final tag in <String>[
      '1.0.0',
      'v1.0',
      'v01.0.0',
      'v1.0.0-beta',
      'v1.0.0+5',
    ]) {
      expect(codec.parseReleaseTag(tag), isNull, reason: tag);
    }
  });
}
