import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';

final class AppUpdateArtifact {
  const AppUpdateArtifact({
    required this.tag,
    required this.version,
    required this.apkUri,
    required this.checksumUri,
    required this.fileName,
    required this.releaseNotes,
  });

  factory AppUpdateArtifact.fromCandidate(GiteeReleaseCandidate candidate) {
    final fileName = canonicalApkFileName(candidate.version);
    final apkName = candidate.apkUri.pathSegments.isEmpty
        ? null
        : candidate.apkUri.pathSegments.last;
    final checksumName = candidate.checksumUri.pathSegments.isEmpty
        ? null
        : candidate.checksumUri.pathSegments.last;
    if (apkName != fileName || checksumName != '$fileName.sha256') {
      throw StateError(
        'Gitee candidate violates the canonical update asset contract.',
      );
    }
    return AppUpdateArtifact(
      tag: candidate.tag,
      version: candidate.version,
      apkUri: candidate.apkUri,
      checksumUri: candidate.checksumUri,
      fileName: fileName,
      releaseNotes: candidate.releaseNotes,
    );
  }

  static String canonicalApkFileName(Version version) {
    return 'y300-v$version-android-arm64-v8a-release.apk';
  }

  final String tag;
  final Version version;
  final Uri apkUri;
  final Uri checksumUri;
  final String fileName;
  final String? releaseNotes;

  String get checksumFileName => '$fileName.sha256';

  String get identityKey => '$tag|$version|$fileName';

  AppUpdateArtifactIdentity get identity =>
      AppUpdateArtifactIdentity.fromValues(
        tag: tag,
        version: version,
        fileName: fileName,
      );
}
