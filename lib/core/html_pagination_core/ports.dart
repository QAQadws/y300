import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Parsing-only port; it does not override rendering or slice serialization.
abstract interface class HtmlFragmentParser {
  dom.DocumentFragment parse(String html);
}

final class DefaultHtmlFragmentParser implements HtmlFragmentParser {
  const DefaultHtmlFragmentParser();

  @override
  dom.DocumentFragment parse(String html) => html_parser.parseFragment(html);
}

/// A stable pure policy, also called on cloned nodes; do not capture UI state.
typedef HtmlProtectedInlinePredicate = bool Function(dom.Element element);

/// The complete HTML to measure, including any already buffered page content.
final class HtmlPaginationMeasureCandidate {
  const HtmlPaginationMeasureCandidate({
    required this.html,
    required this.startOffset,
    required this.endOffset,
  });

  final String html;

  /// DOM grapheme boundaries, distinct from semantic source code-point offsets.
  final int startOffset;
  final int endOffset;
}

final class HtmlPaginationMeasurement {
  const HtmlPaginationMeasurement({
    required this.height,
    this.fromCache = false,
  });

  final double height;
  final bool fromCache;
}

typedef HtmlPaginationMeasure =
    Future<HtmlPaginationMeasurement> Function(
      HtmlPaginationMeasureCandidate candidate,
    );

/// The Host owns signal lifetime and the exception used to report cancellation.
abstract interface class HtmlPaginationCancellation {
  void throwIfCancelled();
  Future<T> waitFor<T>(Future<T> operation);
  Future<void> yieldToEventLoop();
}

final class HtmlPaginationException implements Exception {
  const HtmlPaginationException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'HtmlPaginationException($code): $message';
}
