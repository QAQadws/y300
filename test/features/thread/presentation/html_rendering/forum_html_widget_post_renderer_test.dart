import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
