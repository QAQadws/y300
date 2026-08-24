import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import '../contracts/forum_tag_directory.dart';
import 'tag_page_parsing.dart';

final class DiscuzTagDirectoryHtmlParser {
  DiscuzTagDirectoryHtmlParser({
    required Uri siteOrigin,
    YamiboTagPageParsing? tagPageParsing,
  }) : _tagPageParsing =
           tagPageParsing ?? YamiboTagPageParsing(siteOrigin: siteOrigin);

  final YamiboTagPageParsing _tagPageParsing;

  ForumTagDirectoryData parse({
    required String html,
    required String pageUrl,
    required String expectedTagId,
    required int requestedPage,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.bm.tl');
    if (root == null) {
      throw const FormatException('Tag topic list root is missing.');
    }

    final tagId = _parseTagId(document, pageUrl, expectedTagId);
    if (tagId == null || tagId != expectedTagId) {
      throw const FormatException('Tag identity is missing or mismatched.');
    }

    final tagName = _parseTagName(document);
    final topics = <ForumTagTopicSummary>[];
    final topicIds = <String>{};
    for (final row in root.querySelectorAll('tr')) {
      final topic = _parseTopicRow(row, pageUrl);
      if (topic == null) {
        continue;
      }
      if (!topicIds.add(topic.tid)) {
        throw const FormatException('Tag topic identity is duplicated.');
      }
      topics.add(topic);
    }

    final pagination = _parsePagination(
      document: document,
      pageUrl: pageUrl,
      expectedTagId: expectedTagId,
      requestedPage: requestedPage,
    );
    return ForumTagDirectoryData(
      tag: ForumTagIdentity(id: tagId, name: tagName),
      topics: List<ForumTagTopicSummary>.unmodifiable(topics),
      pagination: pagination,
    );
  }

  String? _parseTagId(
    html_dom.Document document,
    String pageUrl,
    String expectedTagId,
  ) {
    String? firstId;
    for (final anchor in document.querySelectorAll(
      'a[href*="misc.php"][href*="mod=tag"][href*="id="]',
    )) {
      final href = anchor.attributes['href'];
      final resolved = href == null
          ? null
          : _tagPageParsing.resolveUrl(href, pageUrl);
      final uri = Uri.tryParse(resolved ?? '');
      if (uri == null || uri.queryParameters['mod']?.toLowerCase() != 'tag') {
        continue;
      }
      final id = uri.queryParameters['id']?.trim();
      if (id != null && id.isNotEmpty) {
        firstId ??= id;
        if (id == expectedTagId) {
          return id;
        }
      }
    }
    return firstId;
  }

  String? _parseTagName(html_dom.Document document) {
    final heading = _cleanText(document.querySelector('h1.mt')?.text ?? '');
    final headingMatch = RegExp(r'标签\s*[:：]\s*(.+)$').firstMatch(heading);
    final fromHeading = headingMatch?.group(1)?.trim();
    if (fromHeading != null && fromHeading.isNotEmpty) {
      return fromHeading;
    }
    final breadcrumb = document.querySelector(
      '#pt a[href*="misc.php"][href*="mod=tag"][href*="id="]',
    );
    final fromBreadcrumb = _emptyToNull(_cleanText(breadcrumb?.text ?? ''));
    if (fromBreadcrumb != null) {
      return fromBreadcrumb;
    }
    return null;
  }

  ForumTagTopicSummary? _parseTopicRow(html_dom.Element row, String pageUrl) {
    final subjectAnchor = _findSubjectAnchor(row, pageUrl);
    if (subjectAnchor == null) {
      return null;
    }
    final href = subjectAnchor.attributes['href']?.trim();
    final threadUrl = href == null || href.isEmpty
        ? null
        : _tagPageParsing.resolveUrl(href, pageUrl);
    final tid = threadUrl == null
        ? null
        : _tagPageParsing.extractTidFromThreadUrl(threadUrl);
    final title = _cleanText(subjectAnchor.text);
    if (tid == null || tid.trim().isEmpty) {
      throw const FormatException('Tag topic identity is empty.');
    }
    if (title.isEmpty) {
      throw const FormatException('Tag topic title is empty.');
    }

    final cells = row.querySelectorAll('td');
    final forumCell = _cellAt(cells, 1);
    final authorCell = _cellAt(cells, 2);
    final numberCell = _cellAt(cells, 3);
    final lastPostCell = _cellAt(cells, 4);
    final forumUrl = _resolveAnchor(forumCell, pageUrl);
    final authorUrl = _resolveAnchor(authorCell, pageUrl);
    final forumAnchor = forumCell?.querySelector('a[href]');
    final authorAnchor = authorCell?.querySelector(
      'a[href*="space-uid"], a[href*="home.php"][href*="uid="], '
      'a[href*="space-username"]',
    );
    final lastPosterAnchor = lastPostCell?.querySelector(
      'cite a[href], a[href*="space-uid"], a[href*="space-username"]',
    );
    final lastPostAnchor = lastPostCell?.querySelector(
      'em a[href], a[href*="goto=lastpost"], a[href*="mod=redirect"]',
    );
    final replyAnchor = numberCell?.querySelector('a[href]');
    final replyCount = _parseOptionalInt(replyAnchor?.text ?? '');
    final viewCount = _parseOptionalInt(
      numberCell?.querySelector('em')?.text ?? '',
    );

    return ForumTagTopicSummary(
      tid: tid,
      title: title,
      forumId: _extractForumId(forumUrl),
      forumName: _emptyToNull(_cleanText(forumAnchor?.text ?? '')),
      authorId: _extractUid(authorUrl),
      authorName: _emptyToNull(_cleanText(authorAnchor?.text ?? '')),
      createdAt: _emptyToNull(
        _cleanText(authorCell?.querySelector('em')?.text ?? ''),
      ),
      replyCount: replyCount,
      viewCount: viewCount,
      lastPosterName: _emptyToNull(_cleanText(lastPosterAnchor?.text ?? '')),
      lastPostAt: _emptyToNull(_cleanText(lastPostAnchor?.text ?? '')),
      hasImageAttachment:
          row.querySelector('[title*="图片"], .fico-image') != null ? true : null,
      hasAttachment:
          row.querySelector('[title*="附件"], .fico-attachment, .fico-attach') !=
              null
          ? true
          : null,
    );
  }

  html_dom.Element? _findSubjectAnchor(html_dom.Element row, String pageUrl) {
    for (final anchor in row.querySelectorAll('th a[href]')) {
      final href = anchor.attributes['href']?.trim();
      if (href == null || href.isEmpty) {
        continue;
      }
      final resolved = _tagPageParsing.resolveUrl(href, pageUrl);
      if (resolved == null) {
        throw const FormatException('Tag topic URL is invalid.');
      }
      final tid = _tagPageParsing.extractTidFromThreadUrl(resolved);
      if (tid != null) {
        return anchor;
      }
      final uri = Uri.tryParse(resolved);
      if (uri?.queryParameters.containsKey('tid') == true ||
          uri?.path.contains('thread-') == true) {
        throw const FormatException('Tag topic identity is empty.');
      }
    }
    return null;
  }

  ForumTagPagination _parsePagination({
    required html_dom.Document document,
    required String pageUrl,
    required String expectedTagId,
    required int requestedPage,
  }) {
    final currentText = _cleanText(
      document.querySelector('.pg strong')?.text ?? '',
    );
    final currentPage = currentText.isEmpty
        ? requestedPage
        : _parseRequiredInt(currentText, 'current page');
    if (currentPage < 1) {
      throw const FormatException('Current page is invalid.');
    }

    final totalSpan = document.querySelector('.pg label span');
    final visibleTotal = _extractTotalPages(totalSpan?.text ?? '');
    final titleTotal = _extractTotalPages(totalSpan?.attributes['title'] ?? '');
    if (visibleTotal != null &&
        titleTotal != null &&
        visibleTotal != titleTotal) {
      throw const FormatException('Pagination totals disagree.');
    }
    final totalPages = visibleTotal ?? titleTotal;
    if (totalPages != null && totalPages < 1) {
      throw const FormatException('Total page count is invalid.');
    }

    int? previousPage;
    int? nextPage;
    for (final anchor in document.querySelectorAll('.pg a[href]')) {
      final direction = _pageDirection(anchor);
      if (direction == null) {
        continue;
      }
      final page = _parsePageLink(
        anchor,
        pageUrl: pageUrl,
        expectedTagId: expectedTagId,
      );
      if (direction == _PageDirection.previous) {
        previousPage = page;
      } else {
        nextPage = page;
      }
    }

    for (final anchor in document.querySelectorAll('.ptm a[href]')) {
      if (!_cleanText(anchor.text).contains('更多')) {
        continue;
      }
      final page = _parseOptionalPageLink(
        anchor,
        pageUrl: pageUrl,
        expectedTagId: expectedTagId,
      );
      if (page != null && page > currentPage) {
        nextPage = page;
      }
    }

    final hasPrevious = previousPage != null
        ? true
        : currentPage > 1
        ? true
        : false;
    final hasNext = totalPages != null
        ? currentPage < totalPages
        : nextPage == null
        ? null
        : true;
    return ForumTagPagination(
      currentPage: currentPage,
      totalPages: totalPages,
      hasPrevious: hasPrevious,
      hasNext: hasNext,
    );
  }

  int? _extractTotalPages(String source) {
    final text = _cleanText(source);
    if (text.isEmpty) {
      return null;
    }
    final match = RegExp(r'(?:/\s*|共\s*)(\d+)\s*页').firstMatch(text);
    if (match == null) {
      throw const FormatException('Total page count is malformed.');
    }
    return int.tryParse(match.group(1)!) ??
        (throw const FormatException('Total page count is malformed.'));
  }

  _PageDirection? _pageDirection(html_dom.Element anchor) {
    final classes = (anchor.attributes['class'] ?? '').toLowerCase().split(
      RegExp(r'\s+'),
    );
    final text = _cleanText(anchor.text).toLowerCase();
    if (classes.contains('prev') ||
        text == '上一页' ||
        text == '上页' ||
        text == 'prev' ||
        text == '<') {
      return _PageDirection.previous;
    }
    if (classes.contains('nxt') ||
        text == '下一页' ||
        text == '下页' ||
        text == 'next' ||
        text == '>') {
      return _PageDirection.next;
    }
    return null;
  }

  int _parsePageLink(
    html_dom.Element anchor, {
    required String pageUrl,
    required String expectedTagId,
  }) {
    return _parseOptionalPageLink(
          anchor,
          pageUrl: pageUrl,
          expectedTagId: expectedTagId,
        ) ??
        (throw const FormatException('Pagination link is invalid.'));
  }

  int? _parseOptionalPageLink(
    html_dom.Element anchor, {
    required String pageUrl,
    required String expectedTagId,
  }) {
    final href = anchor.attributes['href']?.trim();
    if (href == null || href.isEmpty) {
      throw const FormatException('Pagination link is empty.');
    }
    final resolved = _tagPageParsing.resolveUrl(href, pageUrl);
    final uri = Uri.tryParse(resolved ?? '');
    if (uri == null || uri.queryParameters['mod']?.toLowerCase() != 'tag') {
      throw const FormatException('Pagination link target is invalid.');
    }
    final id = uri.queryParameters['id']?.trim();
    final type = uri.queryParameters['type']?.toLowerCase();
    if (id != expectedTagId || type != 'thread') {
      throw const FormatException('Pagination link identity is invalid.');
    }
    final page = int.tryParse(uri.queryParameters['page']?.trim() ?? '');
    if (page == null || page < 1) {
      return null;
    }
    return page;
  }

  int _parseRequiredInt(String source, String label) {
    final value = int.tryParse(source);
    if (value == null) {
      throw FormatException('$label is malformed.');
    }
    return value;
  }

  int? _parseOptionalInt(String source) {
    final text = _cleanText(source);
    if (text.isEmpty) {
      return null;
    }
    final normalized = text.replaceAll(',', '').replaceAll('，', '');
    final value = int.tryParse(normalized);
    if (value == null || value < 0) {
      throw const FormatException('Topic count is malformed.');
    }
    return value;
  }

  html_dom.Element? _cellAt(List<html_dom.Element> cells, int index) {
    return index >= 0 && index < cells.length ? cells[index] : null;
  }

  String? _resolveAnchor(html_dom.Element? cell, String baseUrl) {
    final href = cell?.querySelector('a[href]')?.attributes['href'];
    return href == null ? null : _tagPageParsing.resolveUrl(href, baseUrl);
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

enum _PageDirection { previous, next }
