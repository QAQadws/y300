import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/site_url_resolver.dart';

abstract class ImageRequestHeaderBuilder {
  Future<Map<String, String>> buildHeaders(String imageUrl);
}

class DiscuzImageRequestHeaderBuilder implements ImageRequestHeaderBuilder {
  const DiscuzImageRequestHeaderBuilder({
    required CookieStore cookieStore,
    String referer = '${AppConfig.siteBaseUrl}/',
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _cookieStore = cookieStore,
       _referer = referer,
       _urlResolver = urlResolver;

  static const String browserUserAgent = BrowserUserAgents.desktop;
  static const String mobileBrowserUserAgent = BrowserUserAgents.mobile;
  static const String imageAcceptHeader =
      'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

  final CookieStore _cookieStore;
  final String _referer;
  final SiteUrlResolver _urlResolver;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    final normalized = _urlResolver.resolve(imageUrl);
    final uri = normalized == null ? null : Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const <String, String>{};
    }

    final headers = <String, String>{
      'Referer': _referer,
      'User-Agent': browserUserAgent,
      'Accept': imageAcceptHeader,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };

    // Cookie is scoped to the image host. This avoids leaking Yamibo cookies to
    // third-party image hosts while still allowing same-site attachments to load.
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }
}
