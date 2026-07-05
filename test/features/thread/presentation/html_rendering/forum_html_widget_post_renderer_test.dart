import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

void main() {
  testWidgets('renders simple HTML text and inline formatting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            html: '<p>普通 <strong>加粗</strong></p>',
            sourceId: 'unit',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-html-renderer-unit')), findsOneWidget);
    expect(find.textContaining('普通', findRichText: true), findsOneWidget);
    expect(find.textContaining('加粗', findRichText: true), findsOneWidget);
  });

  testWidgets('forwards link taps to callbacks', (tester) async {
    final tappedUrls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            html: '<a href="forum.php?mod=viewthread&tid=1">链接</a>',
            sourceId: 'link',
            callbacks: ForumHtmlRenderCallbacks(
              onTapUrl: (url) async {
                tappedUrls.add(url);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('链接', findRichText: true));
    await tester.pumpAndSettle();

    expect(tappedUrls, <String>[
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
    ]);
  });

  testWidgets('passes reader preferences to HtmlWidget', (tester) async {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: const RichTextTypography(
        fontScale: 1.4,
        lineHeightScale: 1.9,
        paragraphSpacing: 22,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 10)),
        ),
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            html: '<p>段落</p>',
            sourceId: 'prefs',
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-prefs')),
    );
    expect(htmlWidget.textStyle?.fontSize, 14);
    expect(htmlWidget.textStyle?.height, 1.9);
    expect(htmlWidget.customStylesBuilder?.call(_elementFrom('<p>段落</p>')), {
      'margin': '0 0 22.0px',
    });
  });

  testWidgets('renders sanitized html when author styles are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            html:
                '<p style="font-size: 30px; color: red; '
                'background-color: yellow">正文</p>',
            sourceId: 'sanitized',
            preferences: ForumHtmlReaderPreferences.defaults().copyWith(
              preserveAuthorFontSize: false,
              preserveAuthorColor: false,
              preserveAuthorBackground: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('正文', findRichText: true), findsOneWidget);
  });
}

html_dom.Element _elementFrom(String html) {
  return html_parser
      .parseFragment(html)
      .nodes
      .whereType<html_dom.Element>()
      .first;
}
