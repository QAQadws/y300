import 'package:pub_semver/pub_semver.dart';

final class InstalledAppVersion {
  const InstalledAppVersion({
    required this.packageName,
    required this.versionName,
    required this.semanticVersion,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final Version semanticVersion;
  final int versionCode;
}
