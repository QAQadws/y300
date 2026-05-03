import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

class DiscuzSearchHtmlParser {
  static final RegExp _tidPattern = RegExp(
    r'forum\.php\?[^#]*\bmod=viewthread\b[^#]*\btid=(\d+)',
    caseSensitive: false,
  );
  static final RegExp _fidPattern = RegExp(
    r'forum\.php\?[^#]*\bmod=forumdisplay\b[^#]*\bfid=(\d+)',
    caseSensitive: false,
  );

  DiscuzSearchResult parse(String html) {
    final document = html_parser.parse(html);
    final items = <DiscuzSearchResultItem>[];

    for (final node in document.querySelectorAll('li.list')) {
      final viewThreadAnchor = node.querySelector('a[href*="mod=viewthread"]');
      if (viewThreadAnchor == null) {
        continue;
      }
      final rawHref = (viewThreadAnchor.attributes['href'] ?? '').trim();
      final normalizedUrl = _normalizeUrl(rawHref);
      if (normalizedUrl == null) {
        continue;
      }
      final tid = _extractTid(normalizedUrl);
      if (tid == null) {
        continue;
      }

      final titleNode = node.querySelector('.threadlist_tit em') ?? node.querySelector('.threadlist_tit');
      final title = (titleNode?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) {
        continue;
      }

      final fidAnchor = node.querySelector('.threadlist_foot a[href*="mod=forumdisplay"]');
      final fid = _extractFid(fidAnchor?.attributes['href'] ?? '') ?? '';
      final author = node.querySelector('.muser .mmc')?.text.trim();
      final timeText = node.querySelector('.muser .mtime')?.text.trim();

      items.add(
        DiscuzSearchResultItem(
          tid: tid,
          title: title,
          url: normalizedUrl,
          fid: fid,
          author: (author == null || author.isEmpty) ? null : author,
          timeText: (timeText == null || timeText.isEmpty) ? null : timeText,
        ),
      );
    }

    return DiscuzSearchResult(items: items);
  }

  String? _normalizeUrl(String href) {
    if (href.isEmpty) {
      return null;
    }
    var decoded = href;
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }
    if (uri.hasScheme) {
      return uri.toString();
    }
    final base = Uri.parse('${AppConfig.siteBaseUrl}/');
    return base.resolveUri(uri).toString();
  }

  String? _extractTid(String url) {
    final match = _tidPattern.firstMatch(url);
    return match?.group(1);
  }

  String? _extractFid(String href) {
    var decoded = href;
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    final match = _fidPattern.firstMatch(decoded);
    return match?.group(1);
  }
}

