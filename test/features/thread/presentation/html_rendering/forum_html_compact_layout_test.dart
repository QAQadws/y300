import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_layout.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/services/thread_post_body_presentation.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

const _bodyKey = Key('measured-html-body');
const _availableWidth = 240.0;

void main() {
  for (final html in [
    'Hi',
    '<p>Hi</p>',
    '<div><p>Hi</p></div>',
    '<p><strong>Hi</strong> <em>there</em></p>',
  ]) {
    testWidgets('compact HTML uses its actual short text width: $html', (
      tester,
    ) async {
      await _pump(tester, html);
      final width = tester.getSize(find.byKey(_bodyKey)).width;
      expect(width, greaterThan(0));
      expect(width, lessThan(_availableWidth));
      final text = find.descendant(
        of: find.byKey(_bodyKey),
        matching: find.byType(RichText),
      );
      expect(width, closeTo(tester.getSize(text).width, 0.01));
      expect(find.byType(IntrinsicWidth), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paragraphs keep interior spacing but no default outer margin', (
    tester,
  ) async {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: const RichTextTypography(
        fontScale: 1,
        lineHeightScale: 1.5,
        paragraphSpacing: 18,
      ),
    );
    await _pump(
      tester,
      '<div><p>First</p><p>Second</p></div>',
      preferences: preferences,
    );
    final body = tester.getRect(find.byKey(_bodyKey));
    final first = tester.getRect(find.text('First', findRichText: true));
    final second = tester.getRect(find.text('Second', findRichText: true));
    expect(first.top, closeTo(body.top, 0.01));
    expect(second.top - first.bottom, closeTo(18, 0.01));
    expect(second.bottom, closeTo(body.bottom, 0.01));
    expect(body.width, lessThan(_availableWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact sizing leaves explicit author width and margins intact',
    (tester) async {
      await _pump(
        tester,
        '<p style="width:180px;margin-bottom:27px">First</p><p>Second</p>',
      );
      final first = tester.getRect(find.text('First', findRichText: true));
      final second = tester.getRect(find.text('Second', findRichText: true));
      expect(tester.getSize(find.byKey(_bodyKey)).width, closeTo(180, 0.01));
      expect(second.top - first.bottom, closeTo(27, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing layout for the same source invalidates HTML layout', (
    tester,
  ) async {
    const html = '<p>Hi</p>';
    await _pump(tester, html, layout: ForumHtmlContentLayout.document);
    expect(tester.getSize(find.byKey(_bodyKey)).width, _availableWidth);
    await _pump(tester, html);
    expect(
      tester.getSize(find.byKey(_bodyKey)).width,
      lessThan(_availableWidth / 2),
    );
    await _pump(tester, html, layout: ForumHtmlContentLayout.document);
    expect(tester.getSize(find.byKey(_bodyKey)).width, _availableWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long rich text wraps at the bound and short links remain live', (
    tester,
  ) async {
    final urls = <String>[];
    final callbacks = ForumHtmlRenderCallbacks(
      onTapUrl: (url) {
        urls.add(url);
        return true;
      },
    );
    await _pump(
      tester,
      '<p><a href="forum.php?mod=viewthread&amp;tid=42">Link</a></p>',
      callbacks: callbacks,
    );
    expect(
      tester.getSize(find.byKey(_bodyKey)).width,
      lessThan(_availableWidth / 2),
    );
    await tester.tap(find.text('Link', findRichText: true));
    expect(
      urls.single,
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42',
    );
    await _pump(
      tester,
      '<p>${List.filled(30, '足够长的消息').join()} '
      '<a href="forum.php?mod=viewthread&amp;tid=42">'
      '${List.filled(10, 'VeryLongUnbrokenUrl').join()}</a></p>',
      callbacks: callbacks,
      textScale: 1.8,
    );
    final size = tester.getSize(find.byKey(_bodyKey));
    expect(size.width, lessThanOrEqualTo(_availableWidth));
    expect(size.height, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remembered body heights are isolated by content layout', (
    tester,
  ) async {
    final presentation = ThreadPostBodyPresentation();
    final preferences = ForumHtmlReaderPreferences.defaults();
    addTearDown(presentation.dispose);
    const sourceId = 'compact-layout';
    const html = '<p>Hi</p>';
    await _pump(
      tester,
      html,
      layout: ForumHtmlContentLayout.document,
      preferences: preferences,
      bodyPresentation: presentation,
    );
    final documentRevision = tester
        .widget<ThreadPostBodyLayout>(find.byType(ThreadPostBodyLayout))
        .revision;
    final documentMemoryKey = (
      documentRevision,
      _availableWidth,
      presentation.expansionRevision,
    );
    expect(
      presentation.heightFor(sourceId, documentMemoryKey),
      tester.getSize(find.byKey(_bodyKey)).height,
    );

    await _pump(
      tester,
      html,
      preferences: preferences,
      bodyPresentation: presentation,
    );
    final compactRevision = tester
        .widget<ThreadPostBodyLayout>(find.byType(ThreadPostBodyLayout))
        .revision;
    expect(compactRevision, isNot(documentRevision));
    expect(presentation.heightFor(sourceId, documentMemoryKey), isNull);
    expect(
      presentation.heightFor(sourceId, (
        compactRevision,
        _availableWidth,
        presentation.expansionRevision,
      )),
      tester.getSize(find.byKey(_bodyKey)).height,
    );
    expect(
      tester.getSize(find.byKey(_bodyKey)).width,
      lessThan(_availableWidth / 2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tables and code retain bounded layouts without intrinsic sizing',
    (tester) async {
      await _pump(
        tester,
        '<div><table><tr><td>First column</td><td>Second column</td></tr>'
        '<tr><td>Values</td><td>More values</td></tr></table>'
        '<pre>${List.filled(10, 'long_code_identifier').join('_')}</pre></div>',
        width: 160,
      );
      expect(
        tester.getSize(find.byKey(_bodyKey)).width,
        lessThanOrEqualTo(160),
      );
      expect(find.text('First column', findRichText: true), findsOneWidget);
      expect(find.byType(IntrinsicWidth), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded collapse content receives compact layout', (
    tester,
  ) async {
    await _pump(
      tester,
      '<div class="showcollapse_box showcollapse_active" id="compact-collapse">'
      '<div class="showcollapse_title"><p>Title</p></div>'
      '<div class="showcollapse_content"><p>Body</p></div></div>',
    );
    final nested = tester.widgetList<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(nested.length, greaterThan(1));
    expect(
      nested.every(
        (renderer) => renderer.contentLayout == ForumHtmlContentLayout.compact,
      ),
      isTrue,
    );
    expect(tester.getSize(find.byKey(_bodyKey)).width, lessThanOrEqualTo(240));
    expect(find.text('Body', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  String html, {
  ForumHtmlContentLayout layout = ForumHtmlContentLayout.compact,
  ForumHtmlReaderPreferences? preferences,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
  double width = _availableWidth,
  double textScale = 1,
  ThreadPostBodyPresentation? bodyPresentation,
}) async {
  await tester.pumpWidget(
    LocalizedTestApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              key: _bodyKey,
              constraints: BoxConstraints(maxWidth: width),
              child: ForumHtmlWidgetPostRenderer(
                html: html,
                theme: forumHtmlTestTheme,
                sourceId: 'compact-layout',
                contentLayout: layout,
                preferences: preferences,
                callbacks: callbacks,
                bodyPresentation: bodyPresentation,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
