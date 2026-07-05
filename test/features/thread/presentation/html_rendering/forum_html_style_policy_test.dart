import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';

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
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 16)),
        ),
        home: Builder(
          builder: (context) {
            style = ForumHtmlStylePolicy(preferences).baseTextStyle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 24);
    expect(style.height, 2.0);
  });

  test('adds paragraph spacing styles to paragraph-like blocks', () {
    final policy = ForumHtmlStylePolicy(
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

  test('sanitizes selected author inline styles and font attributes', () {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      preserveAuthorFontSize: false,
      preserveAuthorColor: false,
      preserveAuthorBackground: false,
    );

    final result = ForumHtmlStylePolicy(preferences).prepareHtml(
      '<p class="keep" style="font-size: 24px; color: red; '
      'background-color: yellow; text-align: center">'
      '<a href="/颜色" style="color: blue; text-decoration: underline">链接</a>'
      '<font size="5" color="#f00" face="serif">字体</font>'
      '</p>',
    );

    expect(result, contains('class="keep"'));
    expect(result, contains('href="/颜色"'));
    expect(result, contains('style="text-align: center"'));
    expect(result, contains('style="text-decoration: underline"'));
    expect(result, isNot(contains('font-size')));
    expect(result, isNot(contains('color:')));
    expect(result, isNot(contains('background-color')));
    expect(result, contains('<font face="serif">字体</font>'));
  });

  test('keeps enabled author styles', () {
    final result = ForumHtmlStylePolicy(ForumHtmlReaderPreferences.defaults())
        .prepareHtml(
          '<font size="5" color="#f00">字体</font>'
          '<span style="font-size: 20px; color: red; background: yellow">文本</span>',
        );

    expect(result, contains('size="5"'));
    expect(result, contains('color="#f00"'));
    expect(result, contains('font-size: 20px'));
    expect(result, contains('color: red'));
    expect(result, contains('background: yellow'));
  });
}
