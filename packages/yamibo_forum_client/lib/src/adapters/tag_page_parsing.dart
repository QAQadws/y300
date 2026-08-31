// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as html_dom;

class YamiboTagPagePagination {
  const YamiboTagPagePagination({
    this.currentPage,
    this.totalPages,
    this.nextPageUrl,
    this.previousPageUrl,
  });

  final int? currentPage;
  final int? totalPages;
  final String? nextPageUrl;
  final String? previousPageUrl;

  YamiboTagPagePagination copyWith({
    int? currentPage,
    int? totalPages,
    String? nextPageUrl,
    String? previousPageUrl,
  }) {
    return YamiboTagPagePagination(
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      previousPageUrl: previousPageUrl ?? this.previousPageUrl,
    );
  }
}

class YamiboTagPageParsing {
  static final RegExp _threadPathPattern = RegExp(
    r'(?:^|/)thread-(\d+)-\d+-\d+\.html$',
    caseSensitive: false,
  );
  static final RegExp _numericIdPattern = RegExp(r'^\d+$');

  const YamiboTagPageParsing({required this.siteOrigin});

  final Uri siteOrigin;

  bool isTagCatalogUrl(String url) {
    final normalized = resolveUrl(
      url,
      siteOrigin.replace(path: '/').toString(),
    );
    final uri = Uri.tryParse(normalized ?? '');
    if (uri == null || !_isYamiboHttpUri(uri)) {
      return false;
    }
    final id = _rawQueryValue(uri.query, 'id')?.trim();
    return uri.path.toLowerCase().endsWith('/misc.php') &&
        _rawQueryValue(uri.query, 'mod')?.toLowerCase() == 'tag' &&
        id != null &&
        _numericIdPattern.hasMatch(id);
  }

  String normalizeCatalogEntryUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) {
      return rawUrl;
    }
    final resolved = parsed.hasScheme
        ? parsed
        : Uri.parse(
            siteOrigin.replace(path: '/').toString(),
          ).resolveUri(parsed);
    final params = Map<String, String>.from(resolved.queryParameters);
    if ((params['mod'] ?? '').toLowerCase() == 'tag') {
      params['type'] = 'thread';
      params['page'] = params['page']?.trim().isNotEmpty == true
          ? params['page']!
          : '1';
      return resolved.replace(queryParameters: params).toString();
    }
    return resolved.toString();
  }

  Uri withPage(Uri uri, int page) {
    final params = Map<String, String>.from(uri.queryParameters);
    params['page'] = page.toString();
    if ((params['mod'] ?? '').toLowerCase() == 'tag') {
      params['type'] = 'thread';
    }
    return uri.replace(queryParameters: params);
  }

  String? resolveUrl(String href, String baseUrl) {
    var decoded = href.trim();
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    final base = Uri.tryParse(baseUrl);
    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }
    return (uri.hasScheme ? uri : (base?.resolveUri(uri) ?? uri)).toString();
  }

  String? extractTidFromThreadUrl(String url) {
    final normalized = resolveUrl(
      url,
      siteOrigin.replace(path: '/').toString(),
    );
    final uri = Uri.tryParse(normalized ?? '');
    if (uri == null || !_isYamiboHttpUri(uri)) {
      return null;
    }

    final threadMatch = _threadPathPattern.firstMatch(uri.path);
    if (threadMatch != null) {
      return threadMatch.group(1);
    }

    final queryTid = _rawQueryValue(uri.query, 'tid')?.trim();
    if (uri.path.toLowerCase().endsWith('/forum.php') &&
        _rawQueryValue(uri.query, 'mod')?.toLowerCase() == 'viewthread' &&
        queryTid != null &&
        _numericIdPattern.hasMatch(queryTid)) {
      return queryTid;
    }
    return null;
  }

  bool _isYamiboHttpUri(Uri uri) {
    final siteUri = siteOrigin;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.toLowerCase() == siteUri.host.toLowerCase();
  }

  String? _rawQueryValue(String rawQuery, String key) {
    if (rawQuery.isEmpty) {
      return null;
    }
    final lowerKey = key.toLowerCase();
    for (final part in rawQuery.split(RegExp(r'[&;]'))) {
      final separatorIndex = part.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      if (part.substring(0, separatorIndex).trim().toLowerCase() != lowerKey) {
        continue;
      }
      return part.substring(separatorIndex + 1);
    }
    return null;
  }

  YamiboTagPagePagination parsePagination({
    required html_dom.Document document,
    required String baseUrl,
  }) {
    final currentText = document.querySelector('.pg strong')?.text.trim();
    final currentPage = int.tryParse(currentText ?? '');
    final totalSpan = document.querySelector('.pg label span')?.text ?? '';
    final title = document.querySelector('.pg label span')?.attributes['title'];
    final byVisibleText = RegExp(
      r'/\s*(\d+)\s*页',
    ).firstMatch(totalSpan)?.group(1);
    final byTitleText = RegExp(
      r'共\s*(\d+)\s*页',
    ).firstMatch(title ?? '')?.group(1);

    return YamiboTagPagePagination(
      currentPage: currentPage,
      totalPages: int.tryParse(byVisibleText ?? byTitleText ?? ''),
      nextPageUrl: extractPageUrl(
        document: document,
        baseUrl: baseUrl,
        direction: YamiboTagPageDirection.next,
      ),
      previousPageUrl: extractPageUrl(
        document: document,
        baseUrl: baseUrl,
        direction: YamiboTagPageDirection.previous,
      ),
    );
  }

  String? extractPageUrl({
    required html_dom.Document document,
    required String baseUrl,
    required YamiboTagPageDirection direction,
  }) {
    for (final anchor in document.querySelectorAll('a')) {
      if (!_isPageDirectionAnchor(anchor, direction)) {
        continue;
      }
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) {
        continue;
      }
      return resolveUrl(href, baseUrl);
    }
    return null;
  }

  bool _isPageDirectionAnchor(
    html_dom.Element anchor,
    YamiboTagPageDirection direction,
  ) {
    final cls = (anchor.attributes['class'] ?? '').toLowerCase();
    final classes = cls.split(RegExp(r'\s+'));
    final text = anchor.text.trim().toLowerCase();
    return switch (direction) {
      YamiboTagPageDirection.next =>
        classes.contains('nxt') ||
            text == '下一页' ||
            text == '下页' ||
            text == 'next' ||
            text == '>',
      YamiboTagPageDirection.previous =>
        classes.contains('prev') ||
            text == '上一页' ||
            text == '上页' ||
            text == 'prev' ||
            text == '<',
    };
  }
}

enum YamiboTagPageDirection { next, previous }
