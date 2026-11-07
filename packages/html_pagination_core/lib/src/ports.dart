export 'package:forum_content_renderer/forum_text.dart'
    show
        HtmlFragmentParser,
        DefaultHtmlFragmentParser,
        HtmlProtectedInlinePredicate,
        HtmlPaginationCancellation;

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

final class HtmlPaginationException implements Exception {
  const HtmlPaginationException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'HtmlPaginationException($code): $message';
}
