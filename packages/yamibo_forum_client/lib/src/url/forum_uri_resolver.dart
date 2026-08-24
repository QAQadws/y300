import 'package:html/parser.dart' as html_parser;

final class ForumUriResolver {
  const ForumUriResolver({required this.siteOrigin});
  final Uri siteOrigin;

  Uri resolve(String value) {
    final decoded = (html_parser.parseFragment(value).text ?? '').trim();
    if (decoded.isEmpty) {
      throw const FormatException('forum_uri_empty');
    }
    final attachment = _normalizeAttachmentPseudoUri(decoded);
    if (attachment != null) {
      return _normalizeAttachmentPath(siteOrigin.resolve(attachment));
    }
    if (decoded.startsWith('//')) {
      return _normalizeAttachmentPath(
        Uri.parse('${siteOrigin.scheme}:$decoded'),
      );
    }
    final parsed = Uri.parse(decoded);
    final pseudoPath = _legacyPseudoAttachmentPath(parsed);
    final resolved = pseudoPath == null
        ? (parsed.isAbsolute ? parsed : siteOrigin.resolveUri(parsed))
        : siteOrigin.resolve(pseudoPath);
    return _normalizeAttachmentPath(resolved);
  }

  bool isSameSite(Uri uri) =>
      uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
      (uri.scheme == 'http' || uri.scheme == 'https');

  String? _normalizeAttachmentPseudoUri(String value) {
    final match = RegExp(
      r'^(?:attachment|attach)://(\d+)$',
      caseSensitive: false,
    ).firstMatch(value);
    final aid = match?.group(1);
    if (aid == null) return null;
    return '/forum.php?mod=attachment&aid=$aid';
  }

  String? _legacyPseudoAttachmentPath(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.toLowerCase() != 'data') {
      return null;
    }
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (!path.toLowerCase().startsWith('attachment/')) return null;
    return Uri(
      path: 'data/$path',
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  Uri _normalizeAttachmentPath(Uri uri) {
    final path = uri.path;
    final prefix = path.startsWith('/')
        ? '/data/attachment/'
        : 'data/attachment/';
    if (!path.toLowerCase().startsWith(prefix)) return uri;
    final remainder = path
        .substring(prefix.length)
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '');
    return uri.replace(path: '$prefix$remainder');
  }
}
