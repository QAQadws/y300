import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const adapter = DefaultForumHtmlThemeAdapter();
  const colorParser = CsslibAuthorColorParser();

  test('adapts the Phase 0 fixture without leaking concealed text', () {
    const source =
        '<font id="highlight" '
        'style="background-color: rgb(252, 244, 207)">浅色强调</font>'
        '<font id="black" color="black">深色主题不可读正文</font>'
        '<font id="blue" color="#99BBF1">可能可保留的标题</font>'
        '<span id="concealed" '
        'style="color: white; background-color: white">隐藏文字</span>';
    final fragment = html_parser.parseFragment(source);

    final result = adapter.adapt(
      fragment: fragment,
      theme: _darkTheme,
      policy: ForumHtmlColorAdaptationPolicy.standard,
    );
    final black = colorParser.parseOwn(fragment.querySelector('#black')!);
    final blue = colorParser.parseOwn(fragment.querySelector('#blue')!);
    final highlight = colorParser.parseOwn(
      fragment.querySelector('#highlight')!,
    );
    final concealed = colorParser.parseOwn(
      fragment.querySelector('#concealed')!,
    );

    expect(
      _visibleContrast(black.foreground!, _darkTheme.surface),
      atLeast(4.5),
    );
    expect(black.foreground?.toARGB32(), isNot(0xFF000000));
    expect(blue.foreground?.toARGB32(), 0xFF99BBF1);
    expect(highlight.background, isNotNull);
    expect(highlight.background?.toARGB32(), isNot(0xFFFcf4cf));
    expect(concealed.foreground, concealed.background);
    expect(result.stats.concealedTextRangeCount, 1);
    expect(result.stats.explicitForegroundCount, 3);
    expect(result.stats.explicitBackgroundCount, 2);
    expect(result.stats.minimumResultContrast, greaterThanOrEqualTo(4.5));
    expect(source, contains('color="black"'));
  });

  test(
    'injects a local foreground only when a child background requires it',
    () {
      final fragment = html_parser.parseFragment(
        '<div id="parent" style="color: #777777">'
        '<span id="highlight" style="background-color: #777777">高亮</span>'
        '<span id="sibling">兄弟</span>'
        '</div>',
      );

      adapter.adapt(
        fragment: fragment,
        theme: _blackTheme,
        policy: ForumHtmlColorAdaptationPolicy.standard,
      );
      final parent = colorParser.parseOwn(fragment.querySelector('#parent')!);
      final highlight = colorParser.parseOwn(
        fragment.querySelector('#highlight')!,
      );
      final sibling = colorParser.parseOwn(fragment.querySelector('#sibling')!);

      expect(parent.foreground?.toARGB32(), 0xFF777777);
      expect(highlight.foreground, isNotNull);
      expect(
        _visibleContrast(highlight.foreground!, highlight.background!),
        atLeast(4.5),
      );
      expect(sibling.foreground, isNull);
    },
  );

  test(
    'removes unsupported colors without damaging unrelated declarations',
    () {
      final fragment = html_parser.parseFragment(
        '<span id="unsupported" '
        'style="font-size: 20px; color: var(--author); '
        'background: linear-gradient(red, blue); '
        'text-align: center; text-decoration: underline">正文</span>',
      );

      final result = adapter.adapt(
        fragment: fragment,
        theme: _darkTheme,
        policy: ForumHtmlColorAdaptationPolicy.standard,
      );
      final style = fragment
          .querySelector('#unsupported')!
          .attributes['style']!;

      expect(style, contains('font-size: 20px'));
      expect(style, contains('text-align: center'));
      expect(style, contains('text-decoration: underline'));
      expect(style, isNot(contains('var(')));
      expect(style, isNot(contains('linear-gradient')));
      expect(result.stats.unsupportedColorCount, 2);
    },
  );

  test(
    'keeps only the concealed range hidden when a child overrides colors',
    () {
      final fragment = html_parser.parseFragment(
        '<span id="hidden" style="color: white; background-color: white">'
        '隐藏'
        '<span id="visible" style="color: black; background-color: yellow">'
        '可见'
        '</span>'
        '</span>',
      );

      adapter.adapt(
        fragment: fragment,
        theme: _darkTheme,
        policy: ForumHtmlColorAdaptationPolicy.standard,
      );
      final hidden = colorParser.parseOwn(fragment.querySelector('#hidden')!);
      final visible = colorParser.parseOwn(fragment.querySelector('#visible')!);

      expect(hidden.foreground, hidden.background);
      expect(visible.foreground, isNot(visible.background));
      expect(
        _visibleContrast(visible.foreground!, visible.background!),
        atLeast(4.5),
      );
    },
  );

  test('application-owned quote and code surfaces override author chrome', () {
    final fragment = html_parser.parseFragment(
      '<div id="quote" class="quote" '
      'style="color: red; background-color: yellow">引用</div>'
      '<pre id="code" style="color: red; background-color: yellow">代码</pre>',
    );

    adapter.adapt(
      fragment: fragment,
      theme: _darkTheme,
      policy: ForumHtmlColorAdaptationPolicy.standard,
    );

    expect(fragment.querySelector('#quote')!.attributes['style'], isNull);
    expect(fragment.querySelector('#code')!.attributes['style'], isNull);
  });
}

Matcher atLeast(double value) => greaterThanOrEqualTo(value - 0.000001);

double _visibleContrast(Color foreground, Color background) {
  const contrast = FlutterRichTextColorContrast();
  return contrast.contrastRatio(
    contrast.composite(foreground, background),
    background,
  );
}

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF241916),
  foreground: Color(0xFFF6E8DD),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF30231F),
  quoteForeground: Color(0xFFF6E8DD),
  codeSurface: Color(0xFF332622),
  codeForeground: Color(0xFFF6E8DD),
);

const _blackTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  link: Color(0xFF90CAF9),
  quoteSurface: Color(0xFF202020),
  quoteForeground: Color(0xFFFFFFFF),
  codeSurface: Color(0xFF181818),
  codeForeground: Color(0xFFFFFFFF),
);
