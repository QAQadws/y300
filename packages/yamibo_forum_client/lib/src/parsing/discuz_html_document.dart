import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../network/forum_response.dart';

/// Pure HTML decoding shared only for the lifetime of one source response.
///
/// Consumers treat [document] as read-only and clone any subtree they change.
/// Account ownership, freshness and observation delivery remain request-local;
/// none of those decisions belongs to this reusable decoding context.
final class DiscuzHtmlDocument {
  /// Creates an independent context, including for cached source documents.
  DiscuzHtmlDocument.fromSource(this.source);

  /// Returns the context weakly attached to this exact text response.
  ///
  /// Equal source strings in different responses never share mutable DOM. The
  /// response and its body are retained unchanged, and no URL/body cache exists.
  static DiscuzHtmlDocument forResponse(ForumResponse<Object?> response) {
    final source = response.body;
    if (source is! String) {
      throw ArgumentError('discuz_html_response_text_expected');
    }
    return _responses[response] ??= DiscuzHtmlDocument.fromSource(source);
  }

  /// Original response text, without repairs or normalization.
  final String source;

  /// One lazily decoded DOM, shared by all readers of this context.
  Document get document => _parsed.document;

  /// Whether that same tokenizer run reported an unexpected end of input.
  bool get hasUnexpectedEof => _parsed.hasUnexpectedEof;

  /// Whether the source contains one complete, ordered HTML document shell.
  ///
  /// This lexical check does not parse HTML. A caller proving completeness must
  /// also reject [hasUnexpectedEof], since raw text can mimic closing tags.
  late final bool isCompleteDocument = _completeDocument(source);

  late final ({Document document, bool hasUnexpectedEof}) _parsed = _parse(
    source,
  );

  static final _responses = Expando<DiscuzHtmlDocument>('discuzHtmlDocument');

  static ({Document document, bool hasUnexpectedEof}) _parse(String source) {
    final parser = html.HtmlParser(source);
    final document = parser.parse();
    return (
      document: document,
      hasUnexpectedEof: parser.errors.any(
        (error) => error.errorCode.contains('eof'),
      ),
    );
  }

  static bool _completeDocument(String source) {
    // The parser repairs truncation. Source boundaries provide separate
    // evidence that an absent navigation indicator was actually sent.
    final markup = source
        .replaceAll(_rawTextElements, '')
        .replaceAll(_comments, '');
    if (!_documentStart.hasMatch(markup) || !_documentEnd.hasMatch(markup)) {
      return false;
    }
    var previous = -1;
    for (final boundary in _boundaries) {
      final matches = boundary.allMatches(markup).toList();
      if (matches.length != 1 || matches.single.start <= previous) return false;
      previous = matches.single.end - 1;
    }
    return true;
  }

  static final _comments = RegExp(r'<!--[\s\S]*?-->');
  static final _rawTextElements = RegExp(
    r'<(script|style|textarea|title|xmp|iframe|noembed|noframes)(?=[\s/>])[^>]*>[\s\S]*?</\1\s*>',
    caseSensitive: false,
  );
  static final _documentStart = RegExp(
    r'^\s*(?:<!doctype\s+html[^>]*>\s*)?<html(?=[\s/>])[^>]*>',
    caseSensitive: false,
  );
  static final _documentEnd = RegExp(r'</html\s*>\s*$', caseSensitive: false);
  static final _boundaries = [
    for (final tag in ['html', 'head', '/head', 'body', '/body', '/html'])
      RegExp('<$tag(?=[\\s/>])[^>]*>', caseSensitive: false),
  ];
}
