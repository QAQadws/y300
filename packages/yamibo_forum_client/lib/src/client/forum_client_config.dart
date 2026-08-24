/// Origins, request identities, and timeouts used by forum transports.
final class ForumClientConfig {
  /// Creates client configuration for one managed forum installation.
  const ForumClientConfig({
    required this.siteOrigin,
    this.apiOrigin,
    this.userAgent = 'YamiboForumClient/1.0',
    this.desktopUserAgent,
    this.apiUserAgent,
    this.resourceUserAgent,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  /// Canonical browser origin for same-site checks and HTML requests.
  final Uri siteOrigin;

  /// Optional Discuz mobile API endpoint.
  final Uri? apiOrigin;

  /// Mobile browser identity kept under the original field name for 4-A
  /// source compatibility.
  final String userAgent;

  /// Optional desktop HTML request identity.
  final String? desktopUserAgent;

  /// Optional Discuz API request identity.
  final String? apiUserAgent;

  /// Optional protected-resource request identity.
  final String? resourceUserAgent;

  /// Maximum time allowed to establish a connection.
  final Duration connectTimeout;

  /// Maximum time allowed while receiving a response.
  final Duration receiveTimeout;

  /// Effective mobile HTML request identity.
  String get mobileUserAgent => userAgent;

  /// Effective desktop HTML request identity.
  String get effectiveDesktopUserAgent => desktopUserAgent ?? userAgent;

  /// Effective Discuz API request identity.
  String get effectiveApiUserAgent => apiUserAgent ?? userAgent;

  /// Effective protected-resource request identity.
  String get effectiveResourceUserAgent =>
      resourceUserAgent ?? desktopUserAgent ?? userAgent;
}
