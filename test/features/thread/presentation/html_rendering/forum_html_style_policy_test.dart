import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  testWidgets('builds base text style from preferences', (tester) async {
    late TextStyle style;
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: const RichTextTypography(
        fontScale: 1.5,
        lineHeightScale: 2.0,
        paragraphSpacing: 20,
      ),
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 16)),
        ),
        home: Builder(
          builder: (context) {
            style = _policy(preferences).baseTextStyle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 24);
    expect(style.height, 2.0);
    expect(style.color, _theme.foreground);
  });

  test('adds paragraph spacing styles to paragraph-like blocks', () {
    final policy = _policy(
      ForumHtmlReaderPreferences.defaults().copyWith(
        typography: const RichTextTypography(
          fontScale: 1,
          lineHeightScale: 1.5,
          paragraphSpacing: 18,
        ),
      ),
    );
    final fragment = html_parser.parseFragment('<p>段落</p><span>文本</span>');

    expect(policy.customStylesFor(fragment.querySelector('p')!), {
      'margin': '0 0 18.0px',
    });
    expect(policy.customStylesFor(fragment.querySelector('span')!), isNull);
  });

  test('paged Discuz line mode keeps p spacing but removes div margins', () {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: const RichTextTypography(
        fontScale: 1,
        lineHeightScale: 1.6,
        paragraphSpacing: 12,
      ),
    );
    final policy = ForumHtmlStylePolicy(
      preferences,
      theme: _theme,
      blockSpacingMode: ForumHtmlBlockSpacingMode.discuzLineDivs,
    );
    final fragment = html_parser.parseFragment(
      '<div>Discuz 行</div><p>语义段落</p>',
    );

    expect(policy.customStylesFor(fragment.querySelector('div')!), isNull);
    expect(policy.customStylesFor(fragment.querySelector('p')!), {
      'margin': '0 0 12.0px',
    });
  });

  test('styles the outer quote surface without nesting duplicate chrome', () {
    final policy = _policy(
      ForumHtmlReaderPreferences.defaults().copyWith(
        typography: const RichTextTypography(
          fontScale: 1,
          lineHeightScale: 1.5,
          paragraphSpacing: 18,
        ),
      ),
    );
    final fragment = html_parser.parseFragment(
      '<div class="quote"><blockquote>嵌套引用</blockquote></div>'
      '<blockquote id="standalone">独立引用</blockquote>',
    );
    final quoteStyles = {
      'background-color': '#F1E8DC',
      'color': '#332211',
      'border-left': '3px solid #9A7654',
      'border-radius': '6px',
      'padding': '8px 10px',
      'margin': '0 0 18.0px',
    };

    expect(
      policy.customStylesFor(fragment.querySelector('.quote')!),
      quoteStyles,
    );
    expect(
      policy.customStylesFor(fragment.querySelector('.quote blockquote')!),
      {'margin': '0'},
    );
    expect(
      policy.customStylesFor(fragment.querySelector('#standalone')!),
      quoteStyles,
    );
  });

  test('adds code block whitespace and monospace styles', () {
    final policy = _policy(ForumHtmlReaderPreferences.defaults());
    final fragment = html_parser.parseFragment(
      '<pre>pre</pre><code>code</code><div class="blockcode">block</div>',
    );

    for (final selector in ['pre', 'code', '.blockcode']) {
      final styles = policy.customStylesFor(fragment.querySelector(selector)!);
      expect(styles, containsPair('font-family', 'monospace'));
      expect(styles, containsPair('white-space', 'pre-wrap'));
      expect(styles, containsPair('overflow-wrap', 'anywhere'));
    }
  });

  test('adds table and table cell safety styles', () {
    final policy = _policy(
      ForumHtmlReaderPreferences.defaults().copyWith(
        typography: const RichTextTypography(
          fontScale: 1,
          lineHeightScale: 1.5,
          paragraphSpacing: 12,
        ),
      ),
    );
    final fragment = html_parser.parseFragment(
      '<table><tr><th>头</th><td>格</td></tr></table>',
    );

    expect(policy.customStylesFor(fragment.querySelector('table')!), {
      'border-collapse': 'collapse',
      'border-spacing': '0',
      'margin': '0 0 12.0px',
      'max-width': '100%',
    });
    expect(policy.customStylesFor(fragment.querySelector('th')!), {
      'border': '1px solid #d0d0d0',
      'padding': '4px 6px',
      'vertical-align': 'top',
    });
    expect(policy.customStylesFor(fragment.querySelector('td')!), {
      'border': '1px solid #d0d0d0',
      'padding': '4px 6px',
      'vertical-align': 'top',
    });
  });

  test('renders content images and image-only links as block content', () {
    final policy = _policy(ForumHtmlReaderPreferences.defaults());
    final fragment = html_parser.parseFragment(
      '<a href="page.jpg" class="orange" />'
      '<img src="data/attachment/forum/page.jpg">'
      '</a>',
    );
    final anchor = fragment.querySelector('a')!;
    final image = fragment.querySelector('img')!;

    expect(policy.customStylesFor(anchor), {'display': 'block'});
    expect(policy.customStylesFor(image), {
      'display': 'block',
      'max-width': '100%',
    });
  });

  test('keeps smileys and mixed text links in inline flow', () {
    final policy = _policy(ForumHtmlReaderPreferences.defaults());
    final fragment = html_parser.parseFragment(
      '<span>正文<img src="static/image/smiley/gexing/008.gif"></span>'
      '<a href="page.jpg">图片说明'
      '<img src="data/attachment/forum/page.jpg">'
      '</a>',
    );

    expect(policy.customStylesFor(fragment.querySelector('span img')!), isNull);
    expect(policy.customStylesFor(fragment.querySelector('a')!), isNull);
  });

  test(
    'hides collapse wrappers as a fallback when custom widget is unavailable',
    () {
      final policy = _policy(ForumHtmlReaderPreferences.defaults());
      final fragment = html_parser.parseFragment(
        '<div class="showcollapse_box showcollapse_active">'
        '<div class="showcollapse_gather">收起</div>'
        '</div>',
      );
      final box = fragment.querySelector('.showcollapse_box')!;
      final gather = fragment.querySelector('.showcollapse_gather')!;

      expect(policy.isForumCollapseElement(box), isTrue);
      expect(policy.isForumCollapseGatherElement(gather), isTrue);
      expect(policy.isForumCollapseInitiallyExpanded(box), isTrue);
      expect(policy.customStylesFor(box), {'display': 'none'});
      expect(policy.customStylesFor(gather), {'display': 'none'});
    },
  );

  test('removes only disabled author font sizes', () {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      preserveAuthorFontSize: false,
    );

    final result = _prepareHtml(
      _policy(preferences),
      '<p class="keep" style="font-size: 24px; color: red; '
      'background-color: yellow; text-align: center">'
      '<a href="/颜色" style="color: blue; text-decoration: underline">链接</a>'
      '<font size="5" color="#f00" face="serif">字体</font>'
      '</p>',
    );

    expect(result, contains('class="keep"'));
    expect(result, contains('href="/颜色"'));
    expect(result, contains('text-align: center'));
    expect(result, contains('text-decoration: underline'));
    expect(result, isNot(contains('font-size')));
    expect(result, contains('color: red'));
    expect(result, contains('background-color: yellow'));
    expect(result, contains('<font color="#f00" face="serif">字体</font>'));
  });

  test('keeps enabled author styles', () {
    final result = _prepareHtml(
      _policy(ForumHtmlReaderPreferences.defaults()),
      '<font size="5" color="#f00">字体</font>'
      '<span style="font-size: 20px; color: red; background: yellow">文本</span>',
    );

    expect(result, isNot(contains('size="5"')));
    expect(result, contains('font-size: 125%'));
    expect(result, contains('color="#f00"'));
    expect(result, contains('font-size: 20px'));
    expect(result, contains('color: red'));
    expect(result, contains('background: yellow'));
  });

  test('normalizes Discuz font sizes to explicit percentages', () {
    final result = _prepareHtml(
      _policy(ForumHtmlReaderPreferences.defaults()),
      '<font size="1">一</font>'
      '<font size="2">二</font>'
      '<font size="3">三</font>'
      '<font size="4">四</font>'
      '<font size="5">五</font>'
      '<font size="6">六</font>'
      '<font size="7">七</font>'
      '<font size="9">九</font>',
    );

    expect(result, contains('font-size: 75%'));
    expect(result, contains('font-size: 87.5%'));
    expect(result, contains('font-size: 100%'));
    expect(result, contains('font-size: 112.5%'));
    expect(result, contains('font-size: 125%'));
    expect(result, contains('font-size: 150%'));
    expect(result, contains('font-size: 175%'));
    expect(result, isNot(contains('size=')));
  });

  test('font size normalization preserves unrelated inline styles', () {
    final result = _prepareHtml(
      _policy(ForumHtmlReaderPreferences.defaults()),
      '<font size="3" style="color: blue; font-size: 40px">正文</font>',
    );

    expect(result, contains('style="color: blue; font-size: 100%"'));
    expect(result, isNot(contains('size="3"')));
    expect(result, isNot(contains('font-size: 40px')));
  });

  test('normalizes structural breaks immediately after edit status', () {
    final result = _prepareHtml(
      _policy(ForumHtmlReaderPreferences.defaults()),
      '<i class="pstatus">本帖最后由作者编辑</i> \n<br> <br />'
      '正文第一行<br>正文第二行',
    );
    final fragment = html_parser.parseFragment(result);

    expect(fragment.querySelectorAll('br'), hasLength(1));
    expect(fragment.text, contains('本帖最后由作者编辑正文第一行正文第二行'));
  });

  test(
    'keeps whitespace after edit status when no structural break exists',
    () {
      final result = _prepareHtml(
        _policy(ForumHtmlReaderPreferences.defaults()),
        '<i class="pstatus">编辑提示</i> 正文',
      );

      expect(result, contains('</i> 正文'));
    },
  );
}

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFFFFFF),
  foreground: Color(0xFF332211),
  link: Color(0xFF9A7654),
  quoteSurface: Color(0xFFF1E8DC),
  quoteForeground: Color(0xFF332211),
  codeSurface: Color(0xFFF2F2F2),
  codeForeground: Color(0xFF332211),
);

ForumHtmlStylePolicy _policy(ForumHtmlReaderPreferences preferences) {
  return ForumHtmlStylePolicy(preferences, theme: _theme);
}

String _prepareHtml(ForumHtmlStylePolicy policy, String html) {
  const codec = HtmlPackageForumHtmlFragmentCodec();
  final fragment = codec.parse(html);
  policy.prepareFragment(fragment);
  return codec.serialize(fragment);
}
