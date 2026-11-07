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

/// The Host owns signal lifetime and the exception used to report cancellation.
abstract interface class HtmlPaginationCancellation {
  void throwIfCancelled();
  Future<T> waitFor<T>(Future<T> operation);
  Future<void> yieldToEventLoop();
}
