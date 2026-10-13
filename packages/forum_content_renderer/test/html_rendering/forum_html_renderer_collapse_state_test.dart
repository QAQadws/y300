import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

const _html =
    '<div class="showcollapse_box" id="closed">'
    '<div class="showcollapse_title">closed</div>'
    '<div class="showcollapse_content">closed text</div></div>'
    '<div class="showcollapse_box showcollapse_active" id="open">'
    '<div class="showcollapse_title">open</div>'
    '<div class="showcollapse_content">open text</div></div>';

void main() {
  testWidgets('the eager constructor still renders an author-expanded body', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumCollapseBlock(
            titleHtml: 'heading',
            contentHtml: 'eager body',
            labels: renderTestLabels,
            initiallyExpanded: true,
            sourceId: 'eager',
            nestedRendererBuilder: (html, {required sourceId}) => Text(html),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('eager body'), findsOneWidget);
    await tester.tap(find.byKey(const Key('forum-html-collapse-toggle-eager')));
    await tester.pumpAndSettle();
    expect(find.text('eager body'), findsNothing);
  });

  testWidgets('lazy content is not requested until the body is expanded', (
    tester,
  ) async {
    var contentReads = 0;
    String readContent() {
      contentReads++;
      return 'deferred body';
    }

    Widget scene(ForumHtmlCollapseLabels labels) => MaterialApp(
      home: Scaffold(
        body: ForumCollapseBlock.lazyContent(
          titleHtml: 'heading',
          labels: labels,
          contentHtmlBuilder: readContent,
          initiallyExpanded: false,
          sourceId: 'lazy',
          nestedRendererBuilder: (html, {required sourceId}) => Text(html),
        ),
      ),
    );
    await tester.pumpWidget(scene(renderTestLabels));
    await tester.pumpAndSettle();
    expect(contentReads, 0);
    expect(find.text('heading'), findsOneWidget);
    expect(find.text('deferred body'), findsNothing);

    await tester.pumpWidget(scene(_updatedLabels));
    await tester.pumpAndSettle();
    expect(contentReads, 0);
    expect(find.bySemanticsLabel(RegExp('Show details')), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-html-collapse-toggle-lazy')));
    await tester.pumpAndSettle();
    expect(contentReads, greaterThan(0));
    expect(find.text('deferred body'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Hide details')), findsOneWidget);

    final readsWhileOpen = contentReads;
    await tester.tap(find.byKey(const Key('forum-html-collapse-toggle-lazy')));
    await tester.pumpAndSettle();
    expect(contentReads, readsWhileOpen);
    expect(find.text('deferred body'), findsNothing);
  });

  testWidgets(
    'nested folds reuse extracted HTML on reopen and replace it for new HTML',
    (tester) async {
      final memory = <String, bool>{};
      var interactions = 0;
      Widget scene(String html, {bool updated = false}) => _scene(
        memory,
        html: html,
        labels: updated ? _updatedLabels : renderTestLabels,
        onInteraction: () => interactions += updated ? 10 : 1,
      );
      ForumCollapseBlock fold(String sourceId) => tester.widget(
        find.byWidgetPredicate(
          (widget) =>
              widget is ForumCollapseBlock && widget.sourceId == sourceId,
        ),
      );
      final outerToggle = find.byKey(
        const Key('forum-html-collapse-toggle-body-outer'),
      );
      final innerToggle = find.byKey(
        const Key('forum-html-collapse-toggle-body-outer-content-inner'),
      );
      final root = find.byKey(const Key('forum-html-renderer-body'));
      await tester.pumpWidget(scene(_nestedHtml));
      await tester.pumpAndSettle();
      final rootElement = tester.element(root);
      final contentSource = fold('body-outer').contentHtmlBuilder;
      expect(contentSource, isNotNull);
      expect(innerToggle, findsNothing);
      expect(find.textContaining('leaf old', findRichText: true), findsNothing);

      await tester.tap(outerToggle);
      await tester.pumpAndSettle();
      expect(innerToggle, findsOneWidget);
      expect(
        find.textContaining('directory text', findRichText: true),
        findsNothing,
      );
      final extractedHtml = fold('body-outer').contentHtmlBuilder!();
      expect(extractedHtml, contains('leaf old'));
      expect(extractedHtml, isNot(contains('showcollapse_gather')));
      await tester.tap(innerToggle);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('leaf old', findRichText: true),
        findsOneWidget,
      );
      expect(interactions, 2);

      await tester.pumpWidget(scene(_nestedHtml, updated: true));
      await tester.pumpAndSettle();
      expect(tester.element(root), same(rootElement));
      expect(fold('body-outer').contentHtmlBuilder, contentSource);
      expect(fold('body-outer').contentHtmlBuilder!(), same(extractedHtml));
      expect(find.bySemanticsLabel(RegExp('Hide details')), findsNWidgets(2));
      await tester.tap(outerToggle);
      await tester.pumpAndSettle();
      await tester.tap(outerToggle);
      await tester.pumpAndSettle();
      expect(fold('body-outer').contentHtmlBuilder!(), same(extractedHtml));
      expect(
        find.textContaining('leaf old', findRichText: true),
        findsOneWidget,
      );
      expect(interactions, 22);

      await tester.tap(outerToggle);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        scene(_nestedHtml.replaceAll('leaf old', 'leaf new'), updated: true),
      );
      await tester.pumpAndSettle();
      expect(fold('body-outer').contentHtmlBuilder, isNot(contentSource));
      expect(find.textContaining('leaf old', findRichText: true), findsNothing);
      await tester.tap(outerToggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('leaf old', findRichText: true), findsNothing);
      expect(
        find.textContaining('leaf new', findRichText: true),
        findsOneWidget,
      );
      expect(memory['body-outer-content-inner'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unopened content uses new HTML and updates the fallback title', (
    tester,
  ) async {
    String html(String text) =>
        '<div id="untitled" class="showcollapse_box">'
        '<div class="showcollapse_content">$text</div></div>';
    final expansion = <String, bool>{};
    await tester.pumpWidget(_scene(expansion, html: html('old body')));
    await tester.pumpAndSettle();
    expect(find.text('Content', findRichText: true), findsOneWidget);
    expect(find.text('old body', findRichText: true), findsNothing);
    final root = find.byKey(const Key('forum-html-renderer-body'));
    final rootElement = tester.element(root);
    await tester.pumpWidget(
      _scene(expansion, html: html('old body'), labels: _updatedLabels),
    );
    await tester.pumpAndSettle();
    expect(find.text('Details', findRichText: true), findsOneWidget);
    expect(tester.element(root), same(rootElement));
    await tester.pumpWidget(
      _scene(expansion, html: html('new body'), labels: _updatedLabels),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-body-untitled')),
    );
    await tester.pumpAndSettle();
    expect(find.text('old body', findRichText: true), findsNothing);
    expect(find.text('new body', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional expansion memory includes effective author defaults', (
    tester,
  ) async {
    final memory = <String, bool>{};
    await tester.pumpWidget(_scene(memory));
    await tester.pumpAndSettle();
    expect(memory, {'body-closed': false, 'body-open': true});
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-body-closed')),
    );
    await tester.pumpAndSettle();
    expect(memory['body-closed'], isTrue);
    await tester.pumpWidget(_scene(memory));
    await tester.pumpAndSettle();
    expect(memory['body-closed'], isTrue);
  });

  testWidgets(
    'preexisting expansion overrides and consumers without memory keep their behavior',
    (tester) async {
      final memory = <String, bool>{'body-open': false, 'body-closed': true};
      await tester.pumpWidget(_scene(memory));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('forum-html-collapse-content-body-open')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-collapse-content-body-closed')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_scene(null));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('forum-html-collapse-content-body-closed')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-collapse-content-body-open')),
        findsOneWidget,
      );
    },
  );
}

const _updatedLabels = ForumHtmlCollapseLabels(
  fallbackTitle: 'Details',
  expandedSemanticsLabel: 'Hide details',
  collapsedSemanticsLabel: 'Show details',
);

const _nestedHtml =
    '<div class="showcollapse_box" id="outer">'
    '<div class="showcollapse_title">outer title</div>'
    '<div class="showcollapse_content"><p>before &amp; after</p>'
    '<div class="showcollapse_gather">directory text</div>'
    '<div class="showcollapse_box" id="inner">'
    '<div class="showcollapse_title">inner title</div>'
    '<div class="showcollapse_content"><p>leaf old</p>'
    '<div class="showcollapse_gather">nested directory text</div>'
    '</div></div></div></div>';

Widget _scene(
  Map<String, bool>? expansion, {
  String html = _html,
  ForumHtmlCollapseLabels labels = renderTestLabels,
  VoidCallback? onInteraction,
}) => MaterialApp(
  home: Scaffold(
    body: ForumHtmlRenderer(
      preparedDocument: prepareRenderTestDocument(html, sourceId: 'body'),
      sourceId: 'body',
      theme: forumHtmlTestTheme,
      options: renderTestOptions,
      labels: labels,
      callbacks: ForumHtmlRenderCallbacks(onInteraction: onInteraction),
      collapseExpansion: expansion,
      buildAsync: false,
      enableCaching: true,
    ),
  ),
);
