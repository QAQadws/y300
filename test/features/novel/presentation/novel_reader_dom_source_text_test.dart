import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/services/novel_reader_dom_source_text.dart';

void main() {
  group('NovelReaderDomSourceText', () {
    test('preserves source text order while filtering non-text markup', () {
      final fragment = html_parser.parseFragment(
        '<p>前&amp;<span>文</span><br>後'
        '<script>排除脚本</script><style>排除样式</style>'
        '<!-- 排除注释 --><img alt="排除属性" src="cover.png">末</p>',
      );

      expect(NovelReaderDomSourceText.read(fragment), '前&文\n後末');
    });

    test(
      'retains text and explicit line breaks without invented boundaries',
      () {
        final fragment = html_parser.parseFragment(
          '<p>  正文&nbsp;</p><div><span>尾文</span><br><br>末文</div>',
        );

        expect(NovelReaderDomSourceText.read(fragment), '  正文\u00a0尾文\n\n末文');
        expect(NovelReaderDomSourceText.read(html_dom.Text('原文')), '原文');
        expect(NovelReaderDomSourceText.read(html_dom.Element.tag('br')), '\n');
        for (final tag in ['script', 'style']) {
          final node = html_dom.Element.tag(tag)..append(html_dom.Text('保密正文'));
          expect(NovelReaderDomSourceText.read(node), isEmpty);
        }
      },
    );

    test('retains source order through deeply wrapped forum markup', () {
      html_dom.Node nested = html_dom.Element.tag('span')
        ..append(html_dom.Text('正文'))
        ..append(html_dom.Element.tag('br'))
        ..append(html_dom.Text('尾文'));
      for (var depth = 0; depth < 4096; depth += 1) {
        nested = html_dom.Element.tag('span')..append(nested);
      }
      final fragment = html_dom.DocumentFragment()
        ..append(html_dom.Text('开头'))
        ..append(nested)
        ..append(html_dom.Text('结尾'));

      expect(NovelReaderDomSourceText.read(fragment), '开头正文\n尾文结尾');
    });
  });
}
