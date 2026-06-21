import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/config/app_config.dart';

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
    r'thread-(\d+)-\d+-\d+\.html',
    caseSensitive: false,
  );

  const YamiboTagPageParsing();

  String normalizeCatalogEntryUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) {
      return rawUrl;
    }
    final resolved = parsed.hasScheme
        ? parsed
        : Uri.parse('${AppConfig.siteBaseUrl}/').resolveUri(parsed);
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
    final uri = Uri.tryParse(url);
    final queryTid = uri?.queryParameters['tid']?.trim();
    if (queryTid != null && queryTid.isNotEmpty) {
      return queryTid;
    }
    final match = _threadPathPattern.firstMatch(url);
    return match?.group(1);
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
