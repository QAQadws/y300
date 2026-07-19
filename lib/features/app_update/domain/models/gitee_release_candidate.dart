import 'package:version/version.dart';

final class GiteeReleaseCandidate {
  const GiteeReleaseCandidate({
    required this.tag,
    required this.version,
    required this.apkUri,
    required this.checksumUri,
    required this.releaseNotes,
  });

  final String tag;
  final Version version;
  final Uri apkUri;
  final Uri checksumUri;
  final String? releaseNotes;
}
