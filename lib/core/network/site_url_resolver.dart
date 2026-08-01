import 'package:y300/core/config/app_config.dart';

/// Resolves Discuz-provided URLs against the Yamibo site origin.
///
/// Discuz post HTML may expose images as absolute URLs, protocol-relative
/// URLs, root paths, or plain relative paths. Keeping the normalization here
/// prevents UI widgets and download services from each inventing their own
/// slightly different URL rules.
class SiteUrlResolver {
  const SiteUrlResolver({this.siteOrigin = '${AppConfig.siteBaseUrl}/'});

  final String siteOrigin;

  String? resolve(String raw) {
    var decoded = raw.trim();
    if (decoded.isEmpty) {
      return null;
    }
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }
    final pseudoAttachmentPath = _pseudoAttachmentPath(uri);
    if (pseudoAttachmentPath != null) {
      return _originUri().resolve(pseudoAttachmentPath).toString();
    }
    if (uri.hasScheme) {
      return uri.toString();
    }

    final origin = _originUri();
    if (decoded.startsWith('//')) {
      return Uri(scheme: origin.scheme)
          .resolve(decoded)
          .replace(query: uri.hasQuery ? uri.query : null)
          .toString();
    }
    return origin.resolveUri(uri).toString();
  }

  String? _pseudoAttachmentPath(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.toLowerCase() != 'data') {
      return null;
    }
    final normalizedPath = uri.path.startsWith('/')
        ? uri.path.substring(1)
        : uri.path;
    if (!normalizedPath.toLowerCase().startsWith('attachment/')) {
      return null;
    }
    final resolved = Uri(
      path: 'data/$normalizedPath',
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
    return resolved.toString();
  }

  Uri _originUri() {
    final parsed = Uri.tryParse(siteOrigin);
    if (parsed == null) {
      return Uri.parse('${AppConfig.siteBaseUrl}/');
    }
    if (parsed.path.isEmpty || parsed.path.endsWith('/')) {
      return parsed;
    }
    return parsed.replace(path: '${parsed.path}/');
  }
}
