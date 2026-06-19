import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

class ForumDisplayHtmlParser {
  const ForumDisplayHtmlParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ForumDisplayData parse(
    String html, {
    required String fallbackFid,
    required int fallbackPage,
  }) {
    final document = html_parser.parse(html);
    final fid = _extractFidFromDocument(document) ?? fallbackFid;
    final threads = _parseThreads(document);
    final currentPage = _parseCurrentPage(document, fallback: fallbackPage);
    final lastPage = _parseLastPage(document);
    final nextPageUrl = _resolve(
      document.querySelector('.pg a.nxt')?.attributes['href'],
    );

    return ForumDisplayData(
      fid: fid,
      forumName: _parseForumName(document),
      headImageUrl: _parseHeadImageUrl(document),
      forumIconUrl: _parseForumIconUrl(document),
      todayPosts: _parseForumStat(document, '今日'),
      totalThreads: _parseForumStat(document, '主题'),
      rank: _parseForumStat(document, '排名'),
      currentPage: currentPage,
      perPage: threads.isEmpty ? 20 : threads.length,
      lastPage: lastPage,
      hasMoreOverride:
          nextPageUrl != null || (lastPage != null && lastPage > currentPage),
      postUrl: _resolve(
        document.querySelector('#a_newthread')?.attributes['href'],
      ),
      searchUrl: _resolve(
        document.querySelector('.nav-search')?.attributes['href'],
      ),
      favoriteUrl: _resolve(
        document
            .querySelector('#nav-more-menu a[href*="favoriteforum"]')
            ?.attributes['href'],
      ),
      primaryFilters: List<ForumDisplayFilterItem>.unmodifiable(
        _parseFilters(document, '.dhnav_box li'),
      ),
      typeFilters: List<ForumDisplayFilterItem>.unmodifiable(
        _parseFilters(document, '.dhnavs_box li'),
      ),
      subForums: List<ForumDisplaySubForum>.unmodifiable(
        _parseSubForums(document),
      ),
      topEntries: List<ForumDisplayTopEntry>.unmodifiable(
        _parseTopEntries(document),
      ),
      threads: List<ForumThreadSummary>.unmodifiable(threads),
      previousPageUrl: _resolve(
        document.querySelector('.pg a.prev')?.attributes['href'],
      ),
      nextPageUrl: nextPageUrl,
    );
  }

  String _parseForumName(html_dom.Document document) {
    final iconAlt = document
        .querySelector('.forumdisplay-top h2 img')
        ?.attributes['alt']
        ?.trim();
    if (iconAlt != null && iconAlt.isNotEmpty) {
      return iconAlt;
    }

    final title = _cleanText(document.querySelector('title')?.text ?? '');
    if (title.isNotEmpty) {
      return title.split(' - ').first.trim();
    }

    final headerTitle = _cleanText(
      document.querySelector('.header h2')?.text ?? '',
    );
    return headerTitle;
  }

  String? _parseForumIconUrl(html_dom.Document document) {
    return _resolve(
      document.querySelector('.forumdisplay-top h2 img')?.attributes['src'],
    );
  }

  String? _parseHeadImageUrl(html_dom.Document document) {
    return _resolve(
      document
              .querySelector('#forum > div.forum-headimg img')
              ?.attributes['src'] ??
          document.querySelector('.forum-headimg img')?.attributes['src'],
    );
  }

  int _parseForumStat(html_dom.Document document, String label) {
    final text = _cleanText(
      document.querySelector('.forumdisplay-top p')?.text ?? '',
    );
    final match = RegExp('$label\\s*[:：]\\s*(\\d+)').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  List<ForumDisplayFilterItem> _parseFilters(
    html_dom.Document document,
    String selector,
  ) {
    final output = <ForumDisplayFilterItem>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll(selector)) {
      final anchor = item.querySelector('a');
      final label = _cleanText(anchor?.text ?? '');
      final url = _resolve(anchor?.attributes['href']);
      if (label.isEmpty || url == null || !seen.add('$label|$url')) {
        continue;
      }
      output.add(
        ForumDisplayFilterItem(
          label: label,
          url: url,
          isSelected: item.classes.contains('mon'),
          typeid: _extractQueryValue(url, 'typeid') ?? '',
        ),
      );
    }
    return output;
  }

  List<ForumDisplaySubForum> _parseSubForums(html_dom.Document document) {
    final container =
        document.querySelector('#forum > div.forumlist.cl') ??
        document.querySelector('.forumlist.cl');
    if (container == null) {
      return const <ForumDisplaySubForum>[];
    }

    final output = <ForumDisplaySubForum>[];
    final seen = <String>{};
    for (final anchor in container.querySelectorAll(
      'a.murl[href*="forumdisplay"]',
    )) {
      final url = _resolve(anchor.attributes['href']);
      final fid = _extractQueryValue(url, 'fid');
      if (url == null || fid == null || fid.isEmpty || !seen.add(fid)) {
        continue;
      }

      final item = anchor.parent;
      final icon =
          item?.querySelector('.micon img') ?? item?.querySelector('img');
      final title = _parseSubForumTitle(anchor, icon);
      if (title.isEmpty) {
        continue;
      }

      output.add(
        ForumDisplaySubForum(
          fid: fid,
          title: title,
          url: url,
          iconUrl: _resolve(icon?.attributes['src']),
        ),
      );
    }
    return output;
  }

  String _parseSubForumTitle(html_dom.Element anchor, html_dom.Element? icon) {
    final title = _cleanText(anchor.querySelector('.mtit')?.text ?? '');
    if (title.isNotEmpty) {
      return title;
    }
    final anchorText = _cleanText(anchor.text);
    if (anchorText.isNotEmpty) {
      return anchorText;
    }
    return _cleanText(icon?.attributes['alt'] ?? '');
  }

  List<ForumDisplayTopEntry> _parseTopEntries(html_dom.Document document) {
    final entries = <ForumDisplayTopEntry>[];
    for (final item in document.querySelectorAll('.threadlist li.list_top')) {
      final anchor = item.querySelector('a');
      final url = _resolve(anchor?.attributes['href']);
      if (anchor == null || url == null) {
        continue;
      }

      final badge = _cleanText(anchor.querySelector('.micon')?.text ?? '');
      final title = _parseTopEntryTitle(anchor, badge);
      if (title.isEmpty) {
        continue;
      }

      entries.add(
        ForumDisplayTopEntry(
          title: title,
          url: url,
          tid: _extractTid(url) ?? '',
          badgeLabel: badge,
          titleColorHex: _extractStyleColor(anchor.querySelector('em')),
          isAnnouncement: url.contains('mod=announcement') || badge == '公告',
        ),
      );
    }
    return entries;
  }

  String _parseTopEntryTitle(html_dom.Element anchor, String badge) {
    final emphasized = _cleanText(anchor.querySelector('em')?.text ?? '');
    if (emphasized.isNotEmpty) {
      return emphasized;
    }
    return _stripPrefix(_cleanText(anchor.text), badge);
  }

  List<ForumThreadSummary> _parseThreads(html_dom.Document document) {
    final threads = <ForumThreadSummary>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll('.threadlist li.list')) {
      final titleBlock = item.querySelector('.threadlist_tit');
      final titleAnchor = _findThreadAnchor(item, titleBlock);
      final threadUrl = _resolve(titleAnchor?.attributes['href']);
      final tid = _extractTid(threadUrl);
      if (tid == null || tid.isEmpty || !seen.add(tid)) {
        continue;
      }

      final badgeNode = titleBlock?.querySelector('.micon');
      final badgeLabel = _cleanText(badgeNode?.text ?? '');
      final sourceTagAnchor = item.querySelector('.threadlist_foot li.mr a');
      final sourceTagUrl = _resolve(sourceTagAnchor?.attributes['href']);
      final sourceTagName = _stripPrefix(
        _cleanText(sourceTagAnchor?.text ?? ''),
        '#',
      );

      threads.add(
        ForumThreadSummary(
          tid: tid,
          typeid: _extractQueryValue(sourceTagUrl, 'typeid') ?? '',
          sourceTagName: sourceTagName.isEmpty ? null : sourceTagName,
          sourceTagUrl: sourceTagUrl,
          subject: _parseThreadSubject(titleBlock, badgeLabel),
          author: _cleanText(item.querySelector('.mmc')?.text ?? ''),
          uid:
              _extractQueryValue(
                _resolve(item.querySelector('.mimg')?.attributes['href']),
                'uid',
              ) ??
              '',
          authorUrl: _resolve(item.querySelector('.mmc')?.attributes['href']),
          avatarUrl: _resolve(
            item.querySelector('.mimg img')?.attributes['src'],
          ),
          threadUrl: threadUrl,
          excerpt: _cleanText(
            item.querySelector('.threadlist_mes')?.text ?? '',
          ),
          dateline: _cleanText(item.querySelector('.mtime')?.text ?? ''),
          views: _parseThreadMetric(item, 'dm-eye-fill'),
          replies: _parseThreadMetric(item, 'dm-chat-s-fill'),
          badgeLabel: badgeLabel.isEmpty ? null : badgeLabel,
          titleColorHex: _extractStyleColor(titleBlock?.querySelector('em')),
          isLocked:
              badgeNode?.classes.contains('lock') == true ||
              badgeLabel.contains('关闭'),
        ),
      );
    }
    return threads;
  }

  html_dom.Element? _findThreadAnchor(
    html_dom.Element item,
    html_dom.Element? titleBlock,
  ) {
    final parent = titleBlock?.parent;
    if (parent is html_dom.Element &&
        parent.localName == 'a' &&
        (parent.attributes['href'] ?? '').contains('viewthread')) {
      return parent;
    }
    return item.querySelector('a[href*="mod=viewthread"], a[href*="thread-"]');
  }

  String _parseThreadSubject(html_dom.Element? titleBlock, String badgeLabel) {
    final emphasized = _cleanText(titleBlock?.querySelector('em')?.text ?? '');
    if (emphasized.isNotEmpty) {
      return emphasized;
    }
    return _stripPrefix(_cleanText(titleBlock?.text ?? ''), badgeLabel);
  }

  int _parseThreadMetric(html_dom.Element item, String iconClass) {
    for (final footItem in item.querySelectorAll('.threadlist_foot li')) {
      final icon = footItem.querySelector('i');
      if (icon?.classes.contains(iconClass) != true) {
        continue;
      }
      return _parseFirstInt(footItem.text);
    }
    return 0;
  }

  int _parseCurrentPage(html_dom.Document document, {required int fallback}) {
    final strong = document.querySelector('.pg strong');
    final parsed = _parseFirstInt(strong?.text ?? '');
    return parsed > 0 ? parsed : fallback;
  }

  int? _parseLastPage(html_dom.Document document) {
    final last = _parseFirstInt(
      document.querySelector('.pg a.last')?.text ?? '',
    );
    if (last > 0) {
      return last;
    }

    var maxPage = 0;
    for (final anchor in document.querySelectorAll('.pg a')) {
      final page = _extractQueryValue(
        _resolve(anchor.attributes['href']),
        'page',
      );
      final parsed = int.tryParse(page ?? '') ?? 0;
      if (parsed > maxPage) {
        maxPage = parsed;
      }
    }
    return maxPage > 0 ? maxPage : null;
  }

  String? _extractFidFromDocument(html_dom.Document document) {
    for (final anchor in document.querySelectorAll('a[href*="forumdisplay"]')) {
      final fid = _extractQueryValue(
        _resolve(anchor.attributes['href']),
        'fid',
      );
      if (fid != null && fid.isNotEmpty) {
        return fid;
      }
    }
    return null;
  }

  String? _extractTid(String? resolvedUrl) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    final queryTid = _extractQueryValue(resolvedUrl, 'tid');
    if (queryTid != null && queryTid.isNotEmpty) {
      return queryTid;
    }
    final path = Uri.tryParse(resolvedUrl)?.path ?? '';
    return RegExp(r'thread-(\d+)-').firstMatch(path)?.group(1);
  }

  String? _extractQueryValue(String? resolvedUrl, String key) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(resolvedUrl);
    final value = uri?.queryParameters[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(value);
  }

  String _cleanText(String source) {
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stripPrefix(String source, String prefix) {
    final trimmed = source.trim();
    if (prefix.isEmpty || !trimmed.startsWith(prefix)) {
      return trimmed;
    }
    return trimmed.substring(prefix.length).trim();
  }

  int _parseFirstInt(String source) {
    final match = RegExp(r'\d+').firstMatch(source);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  String? _extractStyleColor(html_dom.Element? element) {
    final style = element?.attributes['style'];
    if (style == null || style.trim().isEmpty) {
      return null;
    }
    final match = RegExp(
      r'color\s*:\s*(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)',
    ).firstMatch(style);
    return match?.group(1);
  }
}
