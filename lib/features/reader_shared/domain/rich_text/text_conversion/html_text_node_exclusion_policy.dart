import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';

/// Decides whether an element and its text subtree must be left untouched.
abstract interface class HtmlTextNodeExclusionPolicy {
  String get id;

  bool excludes(html_dom.Element element);
}

/// Protects Yamibo user identity links from server-content conversion.
///
/// The policy is intentionally structural. It does not try to infer a
/// username from ordinary text, because that could incorrectly change titles
/// or prose that merely resembles an account name.
final class YamiboUserProfileLinkExclusionPolicy
    implements HtmlTextNodeExclusionPolicy {
  const YamiboUserProfileLinkExclusionPolicy({
    SiteUrlResolver siteUrlResolver = const SiteUrlResolver(),
  }) : _siteUrlResolver = siteUrlResolver;

  static const _profilePath = '/home.php';
  static final _prettyProfilePath = RegExp(
    r'^/space-uid-[1-9][0-9]*\.html$',
    caseSensitive: false,
  );

  final SiteUrlResolver _siteUrlResolver;

  @override
  String get id => 'yamibo-user-profile-link-v1';

  @override
  bool excludes(html_dom.Element element) {
    if (element.localName?.toLowerCase() != 'a') {
      return false;
    }
    final rawHref = element.attributes['href'];
    if (rawHref == null || rawHref.trim().isEmpty) {
      return false;
    }
    final normalized = _siteUrlResolver.resolve(rawHref);
    final uri = normalized == null ? null : Uri.tryParse(normalized);
    if (uri == null || !_isTrustedSiteUri(uri)) {
      return false;
    }

    final path = uri.path.toLowerCase();
    if (path == _profilePath &&
        uri.queryParameters['mod']?.toLowerCase() == 'space') {
      return _isPositiveInteger(uri.queryParameters['uid']);
    }
    return _prettyProfilePath.hasMatch(path);
  }

  bool _isTrustedSiteUri(Uri uri) {
    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.toLowerCase() == siteUri.host.toLowerCase() &&
        uri.port == siteUri.port;
  }

  bool _isPositiveInteger(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(trimmed)) {
      return false;
    }
    return int.tryParse(trimmed) != null;
  }
}
