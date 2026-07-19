final class AppUpdateApkUriPolicy {
  const AppUpdateApkUriPolicy();

  static const String allowedHost = 'gitee.com';
  static final RegExp _apkFileNamePattern = RegExp(
    r'^y300-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-android-arm64-v8a-release\.apk$',
  );

  bool isAllowedReleaseAsset(Uri? uri, {required String expectedName}) {
    return _hasAllowedOrigin(uri) && uri!.pathSegments.last == expectedName;
  }

  bool isAllowedApk(Uri? uri) {
    return _hasAllowedOrigin(uri) &&
        _apkFileNamePattern.hasMatch(uri!.pathSegments.last);
  }

  bool _hasAllowedOrigin(Uri? uri) {
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == allowedHost &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.pathSegments.isNotEmpty;
  }
}
