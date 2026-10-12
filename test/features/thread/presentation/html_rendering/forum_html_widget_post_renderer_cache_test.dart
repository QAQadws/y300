import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('fallback reuses preparation while layout and callbacks update', (
    tester,
  ) async {
    var preferences = ForumHtmlReaderPreferences.defaults();
    var html = '<p>First paragraph</p><p>Second paragraph</p>';
    var sourceId = 'fallback';
    String? threadId;
    String? ownerId;
    var theme = forumHtmlTestTheme;
    var callbackRevision = 0;
    int? invokedRevision;
    Widget host() {
      final revision = callbackRevision;
      return _host(
        html: html,
        preferences: preferences,
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        ownerId: ownerId,
        callbacks: ForumHtmlRenderCallbacks(
          onTapUrl: (_) {
            invokedRevision = revision;
            return true;
          },
        ),
      );
    }

    Future<void> rebuild() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    ForumHtmlRenderer renderer() =>
        tester.widget(find.byType(ForumHtmlRenderer));
    await rebuild();
    var document = renderer().preparedDocument;
    var lastHeight = tester
        .getSize(find.byKey(const Key('forum-html-renderer-fallback')))
        .height;
    callbackRevision++;
    await rebuild();
    expect(renderer().preparedDocument, same(document));
    await renderer().callbacks.onTapUrl!('https://example.invalid/');
    expect(invokedRevision, callbackRevision);
    // Each layout-only preference must relayout even when preparation is reused.
    for (final typography in [
      preferences.typography.copyWith(fontScale: 1.8),
      preferences.typography.copyWith(fontScale: 1.8, lineHeightScale: 2.0),
      preferences.typography.copyWith(
        fontScale: 1.8,
        lineHeightScale: 2.0,
        paragraphSpacing: 28,
      ),
    ]) {
      preferences = preferences.copyWith(typography: typography);
      await rebuild();
      expect(renderer().preparedDocument, same(document));
      final height = tester
          .getSize(find.byKey(const Key('forum-html-renderer-fallback')))
          .height;
      expect(height, greaterThan(lastHeight));
      lastHeight = height;
    }
    expect(renderer().options.fontScale, 1.8);
    expect(renderer().options.paragraphSpacing, 28);

    Future<void> expectInvalidation() async {
      await rebuild();
      expect(renderer().preparedDocument, isNot(same(document)));
      document = renderer().preparedDocument;
    }

    preferences = preferences.copyWith(preserveAuthorFontSize: false);
    await expectInvalidation();
    theme = _darkTheme;
    await expectInvalidation();
    expect(document.themeSignature, _darkTheme.signature);
    sourceId = 'new-source';
    await expectInvalidation();
    expect(document.sequence.sourceId, sourceId);
    threadId = '123';
    await expectInvalidation();
    ownerId = 'new-owner';
    await expectInvalidation();
    html = '<p>Edited body</p>';
    await expectInvalidation();
    expect(find.text('Edited body', findRichText: true), findsOneWidget);
    expect(find.text('First paragraph', findRichText: true), findsNothing);
  });

  testWidgets('supplied documents, empty HTML and unmount release fallback', (
    tester,
  ) async {
    final preferences = ForumHtmlReaderPreferences.defaults();
    const html = '<p>Fallback body</p>';
    final supplied = const DefaultForumHtmlRenderPreparer().prepare(
      html: '<p>Supplied body</p>',
      preferences: preferences,
      theme: forumHtmlTestTheme,
      sourceId: 'fallback',
      threadId: null,
      imageCacheOwnerId: null,
    );
    Future<void> show(
      String html, [
      ForumHtmlPreparedRenderDocument? document,
    ]) async {
      await tester.pumpWidget(
        _host(html: html, preferences: preferences, preparedDocument: document),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    ForumHtmlPreparedRenderDocument document() => tester
        .widget<ForumHtmlRenderer>(find.byType(ForumHtmlRenderer))
        .preparedDocument;
    await show(html);
    final first = document();
    await show(html, supplied);
    expect(document(), same(supplied));
    expect(find.text('Supplied body', findRichText: true), findsOneWidget);
    expect(find.text('Fallback body', findRichText: true), findsNothing);
    await show(html);
    final afterSupplied = document();
    expect(afterSupplied, isNot(same(first)));
    await show('');
    expect(document().preparedHtml, isEmpty);
    expect(find.text('Fallback body', findRichText: true), findsNothing);
    await show(html);
    final afterEmpty = document();
    expect(afterEmpty, isNot(same(afterSupplied)));
    await tester.pumpWidget(const SizedBox.shrink());
    await show(html);
    expect(document(), isNot(same(afterEmpty)));
  });
}

Widget _host({
  required String html,
  required ForumHtmlReaderPreferences preferences,
  ForumHtmlThemeContext theme = forumHtmlTestTheme,
  String sourceId = 'fallback',
  String? threadId,
  String? ownerId,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
  ForumHtmlPreparedRenderDocument? preparedDocument,
}) => LocalizedTestApp(
  theme: ThemeData.light(),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        child: ForumHtmlWidgetPostRenderer(
          html: html,
          theme: theme,
          sourceId: sourceId,
          threadId: threadId,
          imageCacheOwnerId: ownerId,
          preferences: preferences,
          callbacks: callbacks,
          preparedDocument: preparedDocument,
          buildAsync: false,
          // Compact layout uses the renderer-supported four-value CSS margin.
          contentLayout: ForumHtmlContentLayout.compact,
        ),
      ),
    ),
  ),
);

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
