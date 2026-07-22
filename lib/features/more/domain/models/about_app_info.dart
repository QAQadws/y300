final class AboutAppInfo {
  const AboutAppInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get displayVersion {
    final normalizedBuild = buildNumber.trim();
    return normalizedBuild.isEmpty
        ? '版本 ${version.trim()}'
        : '版本 ${version.trim()} ($normalizedBuild)';
  }
}
