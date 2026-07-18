import 'package:pub_semver/pub_semver.dart';

enum AppReleaseAbi { androidArm64V8a }

final class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.abi,
    required this.checksum,
    this.sizeBytes,
  });

  final String name;
  final Uri downloadUrl;
  final AppReleaseAbi abi;
  final AppReleaseChecksumAsset checksum;
  final int? sizeBytes;
}

final class AppReleaseChecksumAsset {
  const AppReleaseChecksumAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final Uri downloadUrl;
}

final class AppReleaseChecksum {
  const AppReleaseChecksum({required this.sha256Hex, required this.fileName});

  final String sha256Hex;
  final String fileName;

  bool matchesDigest(String actualSha256Hex) =>
      sha256Hex == actualSha256Hex.toLowerCase();
}

final class AppRelease {
  const AppRelease({
    required this.tag,
    required this.versionName,
    required this.semanticVersion,
    required this.title,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.apk,
    this.releasedAt,
  });

  final String tag;
  final String versionName;
  final Version semanticVersion;
  final String title;
  final String releaseNotes;
  final DateTime? releasedAt;
  final Uri releasePageUrl;
  final AppReleaseAsset apk;
}
