final class ForumClientConfig {
  const ForumClientConfig({
    required this.siteOrigin,
    this.apiOrigin,
    this.userAgent = 'YamiboForumClient/1.0',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });
  final Uri siteOrigin;
  final Uri? apiOrigin;
  final String userAgent;
  final Duration connectTimeout;
  final Duration receiveTimeout;
}
