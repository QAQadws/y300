import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_author_color_style.dart';

void main() {
  const parser = CsslibAuthorColorParser();

  group('CsslibAuthorColorParser', () {
    test('parses rgba, percentage rgb, case, and multiple declarations', () {
      final element = _element(
        '<div style="FONT-SIZE: 18px; '
        'COLOR: RGBA(10, 20, 30, .5); '
        'BACKGROUND-COLOR: RGB(100%, 0%, 50%); '
        'text-align: center">正文</div>',
      );
      final sourceBeforeParse = element.outerHtml;

      final result = parser.parse(element);

      expect(result.foreground?.toARGB32(), 0x800A141E);
      expect(result.background?.toARGB32(), 0xFFFF0080);
      expect(result.foregroundSource, ForumHtmlColorSource.inlineStyle);
      expect(result.backgroundSource, ForumHtmlColorSource.inlineStyle);
      expect(result.backgroundRole, ForumHtmlBackgroundRole.blockSurface);
      expect(result.unsupportedForeground, isFalse);
      expect(result.unsupportedBackground, isFalse);
      expect(element.outerHtml, sourceBeforeParse);
    });

    test('supports named colors and modern short and long alpha hex', () {
      final fragment = html_parser.parseFragment(
        '<span id="named" style="color: blue; background: #0f08">一</span>'
        '<span id="long" style="color: #11223344">二</span>',
      );

      final named = parser.parse(fragment.querySelector('#named')!);
      final long = parser.parse(fragment.querySelector('#long')!);

      expect(named.foreground?.toARGB32(), 0xFF0000FF);
      expect(named.background?.toARGB32(), 0x8800FF00);
      expect(long.foreground?.toARGB32(), 0x44112233);
      expect(named.backgroundRole, ForumHtmlBackgroundRole.inlineHighlight);
    });

    test('treats fully transparent declarations as unspecified', () {
      final element = _element(
        '<span style="color: transparent; background: rgba(1, 2, 3, 0)">'
        '隐藏'
        '</span>',
      );

      final result = parser.parse(element);

      expect(result.foreground, isNull);
      expect(result.background, isNull);
      expect(result.transparentForeground, isTrue);
      expect(result.transparentBackground, isTrue);
      expect(result.unsupportedForeground, isFalse);
      expect(result.unsupportedBackground, isFalse);
    });

    test('prefers inline declarations over legacy attributes', () {
      final element = _element(
        '<font color="red" bgcolor="yellow" '
        'style="color: blue !important; color: green; '
        'background-color: #010203">正文</font>',
      );

      final result = parser.parse(element);

      expect(result.foreground?.toARGB32(), 0xFF0000FF);
      expect(result.background?.toARGB32(), 0xFF010203);
      expect(result.foregroundSource, ForumHtmlColorSource.inlineStyle);
      expect(result.backgroundSource, ForumHtmlColorSource.inlineStyle);
    });

    test(
      'parses legacy font color and bgcolor when inline values are absent',
      () {
        final result = parser.parse(
          _element('<font color="#abc" bgcolor="rgb(1, 2, 3)">正文</font>'),
        );

        expect(result.foreground?.toARGB32(), 0xFFAABBCC);
        expect(result.background?.toARGB32(), 0xFF010203);
        expect(
          result.foregroundSource,
          ForumHtmlColorSource.legacyFontAttribute,
        );
        expect(
          result.backgroundSource,
          ForumHtmlColorSource.legacyBgColorAttribute,
        );
      },
    );

    test(
      'does not fall back to legacy when inline color is explicit but invalid',
      () {
        final result = parser.parse(
          _element('<font color="red" style="color: var(--author)">正文</font>'),
        );

        expect(result.foreground, isNull);
        expect(result.foregroundSource, isNull);
        expect(result.unsupportedForeground, isTrue);
      },
    );

    test('accepts pure background color and rejects complex shorthand', () {
      final pure = parser.parse(
        _element('<span style="background: red">纯色</span>'),
      );
      final complex = parser.parse(
        _element(
          '<span style="background: linear-gradient(red, blue)">渐变</span>',
        ),
      );

      expect(pure.background?.toARGB32(), 0xFFFF0000);
      expect(pure.unsupportedBackground, isFalse);
      expect(complex.background, isNull);
      expect(complex.unsupportedBackground, isTrue);
    });

    test('resolves inherited foreground and nearest painted background', () {
      final fragment = html_parser.parseFragment(
        '<div style="color: #112233; background-color: #445566">'
        '<span id="middle" style="background-color: #778899">'
        '<em id="leaf">正文</em>'
        '</span>'
        '</div>',
      );

      final middle = parser.parse(fragment.querySelector('#middle')!);
      final leaf = parser.parse(fragment.querySelector('#leaf')!);

      expect(middle.foreground?.toARGB32(), 0xFF112233);
      expect(middle.foregroundSource, ForumHtmlColorSource.inherited);
      expect(middle.background?.toARGB32(), 0xFF778899);
      expect(middle.backgroundSource, ForumHtmlColorSource.inlineStyle);
      expect(leaf.foreground?.toARGB32(), 0xFF112233);
      expect(leaf.foregroundSource, ForumHtmlColorSource.inherited);
      expect(leaf.background?.toARGB32(), 0xFF778899);
      expect(leaf.backgroundSource, ForumHtmlColorSource.inherited);
    });

    test('parseOwn excludes ancestor colors for traversal adapters', () {
      final fragment = html_parser.parseFragment(
        '<div style="color: red; background-color: blue">'
        '<span id="child">正文</span>'
        '</div>',
      );

      final own = parser.parseOwn(fragment.querySelector('#child')!);

      expect(own.foreground, isNull);
      expect(own.background, isNull);
      expect(own.foregroundSource, isNull);
      expect(own.backgroundSource, isNull);
    });

    test('isolates malformed color declarations without throwing', () {
      final element = _element(
        '<span style="color: rgb(1, 2); background: url(image.png)">'
        '正文'
        '</span>',
      );

      final result = parser.parse(element);

      expect(result.foreground, isNull);
      expect(result.background, isNull);
      expect(result.unsupportedForeground, isTrue);
      expect(result.unsupportedBackground, isTrue);
    });
  });
}

html_dom.Element _element(String html) {
  return html_parser
      .parseFragment(html)
      .nodes
      .whereType<html_dom.Element>()
      .first;
}
