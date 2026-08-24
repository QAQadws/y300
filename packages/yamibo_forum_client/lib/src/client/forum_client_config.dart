final class ForumClientConfig {
  const ForumClientConfig({
    required this.siteOrigin,
    this.apiOrigin,
    this.userAgent = 'YamiboForumClient/1.0',
    this.desktopUserAgent,
    this.apiUserAgent,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });
  final Uri siteOrigin;
  final Uri? apiOrigin;

  /// Mobile browser identity kept under the original field name for 4-A
  /// source compatibility.
  final String userAgent;
  final String? desktopUserAgent;
  final String? apiUserAgent;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  String get mobileUserAgent => userAgent;
  String get effectiveDesktopUserAgent => desktopUserAgent ?? userAgent;
  String get effectiveApiUserAgent => apiUserAgent ?? userAgent;
}
