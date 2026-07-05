import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/widgets/forum_collapse_block.dart';

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

  testWidgets('renders forum collapse blocks and expands nested content', (
    tester,
  ) async {
    final tappedUrls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            sourceId: 'collapse',
            html:
                '<div id="toc" class="showcollapse_box">'
                '<div class="showcollapse_title">目录</div>'
                '<div class="showcollapse_content">'
                '<a href="thread.html">内容链接</a>'
                '<div id="inner" class="showcollapse_box">'
                '<div class="showcollapse_title">内层目录</div>'
                '<div class="showcollapse_content">内层内容</div>'
                '</div>'
                '<div class="showcollapse_gather">收起</div>'
                '</div>'
                '</div>',
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

    expect(find.byType(ForumCollapseBlock), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-collapse-collapse-toc')),
      findsOneWidget,
    );
    expect(find.textContaining('目录', findRichText: true), findsOneWidget);
    expect(find.textContaining('内容链接', findRichText: true), findsNothing);
    expect(find.text('收起', findRichText: true), findsNothing);

    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-collapse-toc')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('内容链接', findRichText: true), findsOneWidget);
    expect(find.byType(ForumCollapseBlock), findsNWidgets(2));
    expect(
      find.byKey(const Key('forum-html-collapse-collapse-toc-content-inner')),
      findsOneWidget,
    );

    await tester.tap(find.text('内容链接', findRichText: true));
    await tester.pumpAndSettle();

    expect(tappedUrls, <String>['https://bbs.yamibo.com/thread.html']);
  });

  testWidgets('starts active forum collapse blocks expanded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            sourceId: 'active',
            html:
                '<div id="toc" class="showcollapse_box showcollapse_active">'
                '<div class="showcollapse_title">目录</div>'
                '<div class="showcollapse_content">已展开内容</div>'
                '</div>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已展开内容', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-collapse-content-active-toc')),
      findsOneWidget,
    );
  });

  testWidgets('keeps ruby rendering delegated to the html library', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            sourceId: 'ruby',
            html: '<p>冒险者<ruby>特莉丝<rt>トリス</rt></ruby></p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('特莉丝', findRichText: true), findsOneWidget);
    expect(find.textContaining('トリス', findRichText: true), findsOneWidget);
    expect(find.textContaining('<rt>', findRichText: true), findsNothing);
  });

  testWidgets('maps tapped images to forum image requests', (tester) async {
    ForumHtmlImageRequest? tappedImage;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            sourceId: 'image',
            html:
                '<img id="aimg_286401" '
                'src="data/attachment/forum/month_1110/pic.jpg" '
                'alt="预览图" title="图片标题" width="640" height="480">',
            callbacks: ForumHtmlRenderCallbacks(
              onTapImage: (request) => tappedImage = request,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-image')),
    );
    htmlWidget.onTapImage?.call(
      ImageMetadata(
        alt: '预览图',
        title: '图片标题',
        sources: const [
          ImageSource(
            'https://bbs.yamibo.com/data/attachment/forum/month_1110/pic.jpg',
            width: 640,
            height: 480,
          ),
        ],
      ),
    );

    expect(
      tappedImage?.url,
      endsWith('/data/attachment/forum/month_1110/pic.jpg'),
    );
    expect(tappedImage?.alt, '预览图');
    expect(tappedImage?.title, '图片标题');
    expect(tappedImage?.width, 640);
    expect(tappedImage?.height, 480);
    expect(tappedImage?.isSticker, isFalse);
    expect(tappedImage?.attachmentId, '286401');
  });

  testWidgets('marks forum smiley images as stickers', (tester) async {
    ForumHtmlImageRequest? tappedImage;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            sourceId: 'sticker',
            html: '<img src="static/image/smiley/gexing/008.gif" alt="">',
            callbacks: ForumHtmlRenderCallbacks(
              onTapImage: (request) => tappedImage = request,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-sticker')),
    );
    htmlWidget.onTapImage?.call(
      ImageMetadata(
        sources: const [
          ImageSource(
            'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
          ),
        ],
      ),
    );

    expect(tappedImage?.isSticker, isTrue);
    expect(tappedImage?.attachmentId, isNull);
  });
}

html_dom.Element _elementFrom(String html) {
  return html_parser
      .parseFragment(html)
      .nodes
      .whereType<html_dom.Element>()
      .first;
}
