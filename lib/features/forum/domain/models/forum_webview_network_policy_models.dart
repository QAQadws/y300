class ForumWebViewNetworkPolicy {
  const ForumWebViewNetworkPolicy({
    this.customUserAgent,
    this.extraHeaders = const <String, String>{},
    this.preferAppLocale = true,
  });

  final String? customUserAgent;
  final Map<String, String> extraHeaders;
  final bool preferAppLocale;
}
