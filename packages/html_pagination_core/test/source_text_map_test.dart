import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

void main() {
  test('source map shares the slicer BR/widget/opaque source convention', () {
    final map = HtmlSourceTextMap.parse(
      '<!--source--><p>A<br>😀<img src="x">Z</p>'
      '<script>not source</script><p>B</p>',
    );
    expect(map.runeLength, 5);
    expect(map.rangesByPath['1']!.runeStart, 0);
    expect(map.rangesByPath['1']!.runeEnd, 4);
    expect(map.rangesByPath['1/1']!.runeLength, 1);
    expect(map.rangesByPath['1/3']!.runeLength, 0);
    expect(map.rangesByPath['2']!.runeLength, 0);
    expect(map.rangesByPath['3/0']!.runeStart, 4);
    expect(map.rangesByPath['2/0'], isNull);
    expect(() => map.rangesByPath.clear(), throwsUnsupportedError);
    expect(() => map.sourceRuneAtGraphemeBoundary(-1), throwsRangeError);
  });

  test('styled nodes do not split a grapheme across element boundaries', () {
    final map = HtmlSourceTextMap.parse('<span>e</span><b>\u0301</b>X');
    expect(map.runeLength, 3);
    expect(map.graphemeLength, 2);
    expect(map.sourceRuneAtGraphemeBoundary(1), 2);
    expect(map.rangesByPath['0/0']!.graphemeStart, 0);
    expect(map.rangesByPath['1/0']!.graphemeStart, 0);
    expect(map.rangesByPath['1/0']!.graphemeEnd, 1);
  });

  test('snapshot reuses a supplied parsed fragment without leaking it', () {
    final fragment = parser.parseFragment('<p>original</p>');
    final source = _ExistingFragment(fragment);
    final map = HtmlSourceTextMap.parse('ignored', fragmentParser: source);
    expect(source.calls, 1);
    fragment.nodes.clear();
    expect(map.runeLength, 8);
    expect(map.rangesByPath['0/0']!.runeEnd, 8);
  });

  test('protected inline uses the existing index policy', () {
    final map = HtmlSourceTextMap.parse(
      'A<span data-widget="1"></span>B',
      protectedInlinePredicate: (element) =>
          element.attributes.containsKey('data-widget'),
    );
    expect(map.runeLength, 2);
    expect(map.graphemeLength, 3);
    expect(map.sourceRuneAtGraphemeBoundary(1), 1);
    expect(map.sourceRuneAtGraphemeBoundary(2), 1);
    expect(map.rangesByPath['1']!.runeLength, 0);
  });
}

final class _ExistingFragment implements HtmlFragmentParser {
  _ExistingFragment(this.fragment);
  final dom.DocumentFragment fragment;
  var calls = 0;
  @override
  dom.DocumentFragment parse(String _) {
    calls++;
    return fragment;
  }
}
