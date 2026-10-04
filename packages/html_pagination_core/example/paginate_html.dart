import 'package:html/parser.dart' as parser;
import 'package:html_pagination_core/html_pagination_core.dart';

Future<void> main() async {
  const source =
      '<div>字素 e\u0301 😀 与中文。<strong>保留嵌套结构，逐片寻找合法边界。</strong>'
      '继续验证纯算法。</div>';
  final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
    html: source,
  );
  const searcher = DefaultHtmlComplexFitSearcher();
  final pages = <String>[];
  var offset = 0;
  while (offset < session.textLength) {
    final result = await searcher.findLargestFittingPrefix(
      session: session,
      startOffset: offset,
      bufferedPageHtml: '',
      availableHeight: 100,
      preferredWindowGraphemes: 12,
      cancellationToken: const _NoCancellation(),
      // Synthetic cost only; a Flutter Host measures the actual renderer.
      measure: (candidate) async => HtmlPaginationMeasurement(
        height: parser.parseFragment(candidate.html).text!.runes.length * 10.0,
      ),
    );
    if (!result.fits || result.slice.endOffset <= offset) {
      throw StateError('The example did not produce a fitting forward prefix.');
    }
    pages.add(result.slice.html);
    offset = result.slice.endOffset;
  }
  final reconstructed = pages
      .map((page) => parser.parseFragment(page).text)
      .join();
  if (reconstructed != parser.parseFragment(source).text) {
    throw StateError('Pagination lost or repeated source text.');
  }
  print(
    '${pages.length} pages; ${session.sourceRuneLength} source code points.',
  );
}

final class _NoCancellation implements HtmlPaginationCancellation {
  const _NoCancellation();

  @override
  void throwIfCancelled() {}

  @override
  Future<T> waitFor<T>(Future<T> operation) => operation;

  @override
  Future<void> yieldToEventLoop() => Future<void>.delayed(Duration.zero);
}
