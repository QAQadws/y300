import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

class YamiboTagThreadPageHtmlParser {
  const YamiboTagThreadPageHtmlParser({
    YamiboTagPageParsing tagPageParsing = const YamiboTagPageParsing(),
  }) : _tagPageParsing = tagPageParsing;

  final YamiboTagPageParsing _tagPageParsing;

  YamiboTagThreadPageData parse({
    required String html,
    required String pageUrl,
  }) {
    final document = html_parser.parse(html);
    final resolvedUrl = _tagPageParsing.resolveUrl(pageUrl, pageUrl) ?? pageUrl;
    final tagName = _parseTagName(document);
    final tagId = _parseTagId(document, pageUrl);
    final parsedPagination = _tagPageParsing.parsePagination(
      document: document,
      baseUrl: pageUrl,
    );
    final pagination = parsedPagination.currentPage == null
        ? parsedPagination.copyWith(currentPage: _parsePageFromUrl(pageUrl))
        : parsedPagination;
    return YamiboTagThreadPageData(
      url: resolvedUrl,
      tagId: tagId,
      tagName: tagName.isEmpty ? '标签' : tagName,
      threads: List<YamiboTagThreadItem>.unmodifiable(
        _parseThreads(document, pageUrl),
      ),
      pagination: pagination,
      moreUrl: _parseMoreUrl(document, pageUrl),
    );
  }

  List<YamiboTagThreadItem> _parseThreads(
    html_dom.Document document,
    String pageUrl,
  ) {
    final output = <YamiboTagThreadItem>[];
    final seenTids = <String>{};
    final containers = document.querySelectorAll('.bm.tl .bm_c table');
    final tables = containers.isEmpty
        ? document.querySelectorAll('.bm_c table')
        : containers;
    for (final table in tables) {
      for (final row in table.querySelectorAll('tr')) {
        final item = _parseThreadRow(row, pageUrl);
        if (item == null || !seenTids.add(item.tid)) {
          continue;
        }
        output.add(item);
      }
    }
    return output;
  }

  YamiboTagThreadItem? _parseThreadRow(html_dom.Element row, String pageUrl) {
    final subjectAnchor = _findSubjectAnchor(row, pageUrl);
    if (subjectAnchor == null) {
      return null;
    }
    final threadUrl = _resolve(subjectAnchor.attributes['href'], pageUrl);
    if (threadUrl == null) {
      return null;
    }
    final tid = _tagPageParsing.extractTidFromThreadUrl(threadUrl);
    final subject = _cleanText(subjectAnchor.text);
    if (tid == null || subject.isEmpty) {
      return null;
    }

    final cells = row.querySelectorAll('td');
    final forumCell = _cellAt(cells, 1);
    final authorCell = _cellAt(cells, 2);
    final numCell = _cellAt(cells, 3);
    final lastPostCell = _cellAt(cells, 4);
    final forumAnchor = forumCell?.querySelector('a[href]');
    final authorAnchor = authorCell?.querySelector(
      'a[href*="space-uid"], a[href*="home.php"][href*="uid="], a[href*="space-username"]',
    );
    final lastPosterAnchor = lastPostCell?.querySelector(
      'cite a[href], a[href*="space-uid"], a[href*="space-username"]',
    );
    final lastPostAnchor = lastPostCell?.querySelector(
      'em a[href], a[href*="goto=lastpost"], a[href*="mod=redirect"]',
    );
    final replyAnchor = numCell?.querySelector('a[href]');
    final replyCount = _parseInt(replyAnchor?.text ?? '');
    final viewText = _cleanText(numCell?.querySelector('em')?.text ?? '');

    return YamiboTagThreadItem(
      tid: tid,
      threadUrl: threadUrl,
      subject: subject,
      forumName: _emptyToNull(_cleanText(forumAnchor?.text ?? '')),
      forumUrl: _resolve(forumAnchor?.attributes['href'], pageUrl),
      forumId: _extractForumId(
        _resolve(forumAnchor?.attributes['href'], pageUrl),
      ),
      authorName: _emptyToNull(_cleanText(authorAnchor?.text ?? '')),
      authorUrl: _resolve(authorAnchor?.attributes['href'], pageUrl),
      authorId: _extractUid(
        _resolve(authorAnchor?.attributes['href'], pageUrl),
      ),
      createdAt: _emptyToNull(
        _cleanText(authorCell?.querySelector('em')?.text ?? ''),
      ),
      replyCount: replyCount,
      viewCount: _parseInt(viewText),
      lastPosterName: _emptyToNull(_cleanText(lastPosterAnchor?.text ?? '')),
      lastPostUrl: _resolve(lastPostAnchor?.attributes['href'], pageUrl),
      lastPostAt: _emptyToNull(_cleanText(lastPostAnchor?.text ?? '')),
      hasImageAttachment:
          row.querySelector('[title*="图片"], .fico-image') != null,
      hasAttachment: row.querySelector('[title*="附件"], .fico-attach') != null,
    );
  }

  html_dom.Element? _findSubjectAnchor(html_dom.Element row, String pageUrl) {
    final heading = row.querySelector('th');
    final anchors =
        heading?.querySelectorAll('a[href]') ?? const <html_dom.Element>[];
    for (final anchor in anchors) {
      final url = _resolve(anchor.attributes['href'], pageUrl);
      if (url == null) {
        continue;
      }
      final tid = _tagPageParsing.extractTidFromThreadUrl(url);
      if (tid != null && _cleanText(anchor.text).isNotEmpty) {
        return anchor;
      }
    }
    return null;
  }

  String _parseTagName(html_dom.Document document) {
    final heading = _cleanText(document.querySelector('h1.mt')?.text ?? '');
    final headingMatch = RegExp(r'标签\s*[:：]\s*(.+)$').firstMatch(heading);
    final fromHeading = headingMatch?.group(1)?.trim();
    if (fromHeading != null && fromHeading.isNotEmpty) {
      return fromHeading;
    }
    final breadcrumb = document.querySelector(
      '#pt a[href*="misc.php"][href*="mod=tag"][href*="id="]',
    );
    final fromBreadcrumb = _cleanText(breadcrumb?.text ?? '');
    if (fromBreadcrumb.isNotEmpty) {
      return fromBreadcrumb;
    }
    final title = _cleanText(document.querySelector('title')?.text ?? '');
    final titleMatch = RegExp(r'标签\s*-\s*([^-]+)').firstMatch(title);
    return titleMatch?.group(1)?.trim() ?? '';
  }

  String _parseTagId(html_dom.Document document, String pageUrl) {
    final pageUri = Uri.tryParse(pageUrl);
    final pageId = pageUri?.queryParameters['id']?.trim();
    if (pageId != null && pageId.isNotEmpty) {
      return pageId;
    }
    for (final anchor in document.querySelectorAll(
      'a[href*="misc.php"][href*="mod=tag"][href*="id="]',
    )) {
      final url = _resolve(anchor.attributes['href'], pageUrl);
      final id = Uri.tryParse(url ?? '')?.queryParameters['id']?.trim();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }
    return '';
  }

  int? _parsePageFromUrl(String url) {
    return int.tryParse(Uri.tryParse(url)?.queryParameters['page'] ?? '');
  }

  String? _parseMoreUrl(html_dom.Document document, String pageUrl) {
    for (final anchor in document.querySelectorAll('.ptm a[href]')) {
      if (!_cleanText(anchor.text).contains('更多')) {
        continue;
      }
      return _resolve(anchor.attributes['href'], pageUrl);
    }
    return null;
  }

  html_dom.Element? _cellAt(List<html_dom.Element> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return null;
    }
    return cells[index];
  }

  String? _resolve(String? href, String baseUrl) {
    final value = href?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _tagPageParsing.resolveUrl(value, baseUrl);
  }

  String? _extractForumId(String? url) {
    final uri = Uri.tryParse(url ?? '');
    final queryFid = uri?.queryParameters['fid']?.trim();
    if (queryFid != null && queryFid.isNotEmpty) {
      return queryFid;
    }
    return RegExp(r'forum-(\d+)-').firstMatch(uri?.path ?? '')?.group(1);
  }

  String? _extractUid(String? url) {
    final uri = Uri.tryParse(url ?? '');
    final queryUid = uri?.queryParameters['uid']?.trim();
    if (queryUid != null && queryUid.isNotEmpty) {
      return queryUid;
    }
    return RegExp(r'space-uid-(\d+)').firstMatch(uri?.path ?? '')?.group(1);
  }

  int? _parseInt(String source) {
    final normalized = _cleanText(source);
    if (normalized.isEmpty) {
      return null;
    }
    final match = RegExp(r'\d+').firstMatch(normalized);
    return int.tryParse(match?.group(0) ?? '');
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
