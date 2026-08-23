final class ForumUriResolver {
  const ForumUriResolver({required this.siteOrigin});
  final Uri siteOrigin;

  Uri resolve(String value) => Uri.parse(value).isAbsolute
      ? Uri.parse(value)
      : siteOrigin.resolve(value);

  bool isSameSite(Uri uri) =>
      uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}
