/// Browser identities verified against Yamibo's mobile, desktop, API, and
/// protected-resource endpoints.
///
/// A WAF recovery delegate must reuse the exact user agent included in its
/// recovery request. Hosts may override these values when they maintain their
/// own browser identity policy.
abstract final class ForumBrowserUserAgents {
  /// Android Chrome identity used for mobile HTML and Discuz mobile API calls.
  static const String mobileChromium =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  /// Windows Chrome identity used for desktop HTML and protected resources.
  static const String desktopChromium =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
}

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

  /// Creates the verified configuration for the public Yamibo installation.
  ///
  /// Mobile HTML and Discuz API requests use [mobileUserAgent]. Desktop HTML
  /// and protected resources use [desktopUserAgent]. Supplying [apiUserAgent]
  /// or [resourceUserAgent] overrides only that request profile.
  factory ForumClientConfig.yamibo({
    String mobileUserAgent = ForumBrowserUserAgents.mobileChromium,
    String desktopUserAgent = ForumBrowserUserAgents.desktopChromium,
    String? apiUserAgent,
    String? resourceUserAgent,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 20),
  }) => ForumClientConfig(
    siteOrigin: Uri.parse('https://bbs.yamibo.com'),
    apiOrigin: Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
    userAgent: mobileUserAgent,
    desktopUserAgent: desktopUserAgent,
    apiUserAgent: apiUserAgent ?? mobileUserAgent,
    resourceUserAgent: resourceUserAgent ?? desktopUserAgent,
    connectTimeout: connectTimeout,
    receiveTimeout: receiveTimeout,
  );

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
