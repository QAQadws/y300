import 'dart:convert';
import 'dart:io';

const giteeLatestReleaseV001FixturePath =
    'test/features/app_update/fixtures/phase0/'
    'gitee_latest_release_v0_0_1.json';

const giteeLatestReleaseV001ChecksumFixturePath =
    'test/features/app_update/fixtures/phase0/'
    'y300-v0.0.1-android-arm64-v8a-release.apk.sha256';

Future<Map<String, dynamic>> loadGiteeLatestReleaseV001Fixture() async {
  final text = await File(
    giteeLatestReleaseV001FixturePath,
  ).readAsString(encoding: utf8);
  final decoded = jsonDecode(text);
  if (decoded is! Map) {
    throw const FormatException('Gitee fixture root must be a JSON object.');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

Future<String> loadGiteeLatestReleaseV001ChecksumFixture() {
  return File(
    giteeLatestReleaseV001ChecksumFixturePath,
  ).readAsString(encoding: utf8);
}
