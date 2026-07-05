import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_fragment_extractor.dart';

void main() {
  const extractor = DefaultForumHtmlFragmentExtractor();

  test('extracts .t_f content first', () {
    final input = extractor.extract(
      sourceId: 'sample',
      rawHtml:
          '<html><body><div class="message">wrong</div>'
          '<div class="t_f"><p>正文</p></div></body></html>',
    );

    expect(input.sourceId, 'sample');
    expect(input.rawHtml, contains('class="t_f"'));
    expect(input.fragmentHtml, contains('<p>正文</p>'));
    expect(input.fragmentHtml, isNot(contains('wrong')));
  });

  test('extracts .message when .t_f is unavailable', () {
    final input = extractor.extract(
      sourceId: 'message',
      rawHtml: '<html><body><div class="message"><b>正文</b></div></body></html>',
    );

    expect(input.fragmentHtml, contains('<b>正文</b>'));
  });

  test('falls back to body content', () {
    final input = extractor.extract(
      sourceId: 'body',
      rawHtml: '<html><body><main>正文</main></body></html>',
    );

    expect(input.fragmentHtml, contains('<main>正文</main>'));
  });

  test('removes script and noscript but keeps style', () {
    final input = extractor.extract(
      sourceId: 'cleanup',
      rawHtml:
          '<html><body><style>.a{color:red}</style>'
          '<script>alert(1)</script><noscript>hidden</noscript>'
          '<div class="message">正文</div></body></html>',
    );

    expect(input.fragmentHtml, contains('<style>.a{color:red}</style>'));
    expect(input.fragmentHtml, isNot(contains('<script')));
    expect(input.fragmentHtml, isNot(contains('<noscript')));
    expect(input.fragmentHtml, contains('正文'));
  });
}
