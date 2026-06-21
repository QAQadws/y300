import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

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
  CatalogThreadHtmlParser({YamiboTagPageParsing? tagPageParsing})
    : _tagPageParsing = tagPageParsing ?? const YamiboTagPageParsing();

  final YamiboTagPageParsing _tagPageParsing;

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

        final normalizedUrl = _tagPageParsing.resolveUrl(href, pageUrl);
        if (normalizedUrl == null) {
          continue;
        }
        final tid = _tagPageParsing.extractTidFromThreadUrl(normalizedUrl);
        if (tid == null) {
          continue;
        }

        final subject = anchor.text.trim();
        final score = _scoreAnchor(
          anchorText: subject,
          isInsideTh: anchor.parent?.localName == 'th',
        );
        final current = candidates[tid];
        if (current == null ||
            score > current.score ||
            (score == current.score &&
                subject.length > current.subject.length)) {
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

    final paginationInfo = _tagPageParsing.parsePagination(
      document: document,
      baseUrl: pageUrl,
    );
    return CatalogThreadParseResult(
      entries: entries,
      nextPageUrl: paginationInfo.nextPageUrl,
      currentPage: paginationInfo.currentPage,
      totalPages: paginationInfo.totalPages,
    );
  }

  int _scoreAnchor({required String anchorText, required bool isInsideTh}) {
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
