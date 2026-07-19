import 'package:version/version.dart';

final class AppVersionCodec {
  const AppVersionCodec();

  static final RegExp _stableVersionPattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );

  Version? parseVersionName(String value) {
    if (!_stableVersionPattern.hasMatch(value)) {
      return null;
    }
    return Version.parse(value);
  }

  Version? parseReleaseTag(String value) {
    if (!value.startsWith('v')) {
      return null;
    }
    return parseVersionName(value.substring(1));
  }

  String canonicalTag(Version version) => 'v$version';
}
