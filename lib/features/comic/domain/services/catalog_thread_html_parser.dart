import 'package:html/parser.dart' as html_parser;

class CatalogThreadEntry {
  const CatalogThreadEntry({
    required this.tid,
    required this.url,
    required this.subject,
  });

  final String tid;
  final String url;
  final String subject;
}

class CatalogThreadParseResult {
  const CatalogThreadParseResult({
    required this.entries,
    this.nextPageUrl,
    this.currentPage,
    this.totalPages,
  });

  final List<CatalogThreadEntry> entries;
  final String? nextPageUrl;
  final int? currentPage;
  final int? totalPages;
}

/// Parse Discuz tag catalog HTML pages and extract thread entries.
///
/// The parser is intentionally reusable:
/// - input: raw page html + page url
/// - output: normalized thread entries + next-page url
class CatalogThreadHtmlParser {
  static final RegExp _threadPathPattern = RegExp(
    r'thread-(\d+)-\d+-\d+\.html',
    caseSensitive: false,
  );

  CatalogThreadParseResult parse({
    required String html,
    required String pageUrl,
  }) {
    final document = html_parser.parse(html);
    final candidates = <String, _EntryCandidate>{};

    for (final row in document.querySelectorAll('tr')) {
      for (final anchor in row.querySelectorAll('a')) {
        final href = (anchor.attributes['href'] ?? '').trim();
        if (href.isEmpty) {
          continue;
        }

        final normalizedUrl = _normalizeUrlWithBase(href, pageUrl);
        if (normalizedUrl == null) {
          continue;
        }
        final tid = _extractTidFromUrl(normalizedUrl);
        if (tid == null) {
          continue;
        }

        final subject = anchor.text.trim();
        final score = _scoreAnchor(anchorText: subject, isInsideTh: anchor.parent?.localName == 'th');
        final current = candidates[tid];
        if (current == null || score > current.score || (score == current.score && subject.length > current.subject.length)) {
          candidates[tid] = _EntryCandidate(
            tid: tid,
            url: normalizedUrl,
            subject: subject,
            score: score,
          );
        }
      }
    }

    final entries = candidates.values
        .map(
          (entry) => CatalogThreadEntry(
            tid: entry.tid,
            url: entry.url,
            subject: entry.subject,
          ),
        )
        .toList(growable: false);

    final nextPageUrl = _extractNextPageUrl(document, pageUrl);
    final paginationInfo = _extractPaginationInfo(document);
    return CatalogThreadParseResult(
      entries: entries,
      nextPageUrl: nextPageUrl,
      currentPage: paginationInfo.currentPage,
      totalPages: paginationInfo.totalPages,
    );
  }

  int _scoreAnchor({
    required String anchorText,
    required bool isInsideTh,
  }) {
    var score = 0;
    if (isInsideTh) {
      score += 2;
    }
    if (anchorText.isNotEmpty) {
      score += 1;
    }
    if (!_isLikelyCountText(anchorText)) {
      score += 1;
    }
    return score;
  }

  bool _isLikelyCountText(String text) {
    if (text.isEmpty) {
      return true;
    }
    return RegExp(r'^\d+$').hasMatch(text);
  }

  String? _extractNextPageUrl(dynamic document, String baseUrl) {
    for (final anchor in document.querySelectorAll('a')) {
      final cls = (anchor.attributes['class'] ?? '').toLowerCase();
      final text = anchor.text.trim().toLowerCase();
      final isNextByClass = cls.split(RegExp(r'\s+')).contains('nxt');
      final isNextByText = text == '下一页' || text == '下页' || text == 'next' || text == '>';
      if (!isNextByClass && !isNextByText) {
        continue;
      }
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) {
        continue;
      }
      return _normalizeUrlWithBase(href, baseUrl);
    }
    return null;
  }

  _PaginationInfo _extractPaginationInfo(dynamic document) {
    final currentText = document.querySelector('.pg strong')?.text.trim();
    final currentPage = int.tryParse(currentText ?? '');

    int? totalPages;
    final totalSpan = document.querySelector('.pg label span')?.text ?? '';
    final title = document.querySelector('.pg label span')?.attributes['title'] ?? '';
    final byVisibleText = RegExp(r'/\s*(\d+)\s*页').firstMatch(totalSpan)?.group(1);
    final byTitleText = RegExp(r'共\s*(\d+)\s*页').firstMatch(title)?.group(1);
    totalPages = int.tryParse(byVisibleText ?? byTitleText ?? '');

    return _PaginationInfo(
      currentPage: currentPage,
      totalPages: totalPages,
    );
  }

  String? _normalizeUrlWithBase(String href, String baseUrl) {
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

  String? _extractTidFromUrl(String url) {
    final match = _threadPathPattern.firstMatch(url);
    return match?.group(1);
  }
}

class _EntryCandidate {
  const _EntryCandidate({
    required this.tid,
    required this.url,
    required this.subject,
    required this.score,
  });

  final String tid;
  final String url;
  final String subject;
  final int score;
}

class _PaginationInfo {
  const _PaginationInfo({
    required this.currentPage,
    required this.totalPages,
  });

  final int? currentPage;
  final int? totalPages;
}
