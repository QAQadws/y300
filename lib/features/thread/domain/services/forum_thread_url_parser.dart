import 'package:y300/core/config/app_config.dart';

/// Normalizes Yamibo thread links and extracts thread ids from known Discuz
/// link shapes. Keep this focused on URLs; callers decide whether a link is
/// semantically useful for comic, novel, or favorite parsing.
class ForumThreadUrlParser {
  const ForumThreadUrlParser({
    this.siteOrigin = '${AppConfig.siteBaseUrl}/',
  });

  final String siteOrigin;

  static final RegExp _threadPathPattern = RegExp(
    r'thread-(\d+)-\d+-\d+\.html',
    caseSensitive: false,
  );
  static final RegExp _damagedTidPattern = RegExp(
    r'(^|[?&;])tid=(\d+)(?:[&#]|$)',
    caseSensitive: false,
  );

  String? normalizeHref(String href) {
    var decoded = href.trim();
    if (decoded.isEmpty) {
      return null;
    }
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }

    final damagedTid = _extractTidFromDamagedHref(decoded);
    if ((decoded.startsWith(';tid=') || decoded.startsWith('tid=')) && damagedTid != null) {
      return _viewThreadUrl(damagedTid);
    }

    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }

    final origin = Uri.tryParse(siteOrigin) ?? Uri.parse('${AppConfig.siteBaseUrl}/');
    final effectiveUri = uri.hasScheme ? uri : origin.resolveUri(uri);
    final isThreadHtml = _threadPathPattern.hasMatch(effectiveUri.path);
    final isForumViewThread = effectiveUri.path.toLowerCase().endsWith('forum.php') &&
        effectiveUri.queryParameters['mod']?.toLowerCase() == 'viewthread' &&
        (effectiveUri.queryParameters['tid']?.trim().isNotEmpty ?? false);

    String? normalizedQuery;
    if (isForumViewThread) {
      final tid = effectiveUri.queryParameters['tid'];
      final fromuid = effectiveUri.queryParameters['fromuid'];
      normalizedQuery = <String>[
        'mod=viewthread',
        if (tid != null) 'tid=$tid',
        if (fromuid != null && fromuid.trim().isNotEmpty) 'fromuid=$fromuid',
      ].join('&');
    } else if (isThreadHtml) {
      normalizedQuery = null;
    } else {
      normalizedQuery = effectiveUri.hasQuery ? effectiveUri.query : null;
    }

    return Uri(
      scheme: effectiveUri.scheme,
      userInfo: effectiveUri.userInfo,
      host: effectiveUri.host,
      port: effectiveUri.hasPort ? effectiveUri.port : null,
      path: effectiveUri.path,
      query: normalizedQuery,
    ).toString();
  }

  String? extractTid(String normalizedUrl) {
    final threadMatch = _threadPathPattern.firstMatch(normalizedUrl);
    if (threadMatch != null) {
      return threadMatch.group(1);
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri != null &&
        uri.path.toLowerCase().endsWith('forum.php') &&
        uri.queryParameters['mod']?.toLowerCase() == 'viewthread') {
      final tid = uri.queryParameters['tid']?.trim();
      if (tid != null && tid.isNotEmpty) {
        return tid;
      }
    }

    return _extractTidFromDamagedHref(normalizedUrl);
  }

  bool isThreadUrl(String normalizedUrl) => extractTid(normalizedUrl) != null;

  String _viewThreadUrl(String tid) {
    final origin = Uri.tryParse(siteOrigin) ?? Uri.parse('${AppConfig.siteBaseUrl}/');
    return origin.resolve('forum.php?mod=viewthread&tid=$tid').toString();
  }

  String? _extractTidFromDamagedHref(String href) {
    final match = _damagedTidPattern.firstMatch(href);
    return match?.group(2);
  }
}
