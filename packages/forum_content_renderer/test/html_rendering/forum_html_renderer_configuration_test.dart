import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

const _html =
    '<p>Root paragraph</p>'
    '<div id="fold" class="showcollapse_box showcollapse_active">'
    '<div class="showcollapse_content">'
    '<p><a href="https://example.invalid/nested">Nested link</a></p>'
    '<p>Another paragraph in the expanded body</p></div></div>';

void main() {
  testWidgets('clearing a nested URL handler also disables its interaction', (
    tester,
  ) async {
    final scene = _Scene();
    await tester.pumpWidget(scene.widget(recordInteractions: true));
    await tester.pumpAndSettle();
    final link = find.text('Nested link', findRichText: true);
    await tester.tapAt(tester.getRect(link).center);
    await tester.pump();
    expect(scene.events, ['0:interaction', '0:https://example.invalid/nested']);
    scene.events.clear();
    await tester.pumpWidget(
      scene.widget(handlesUrl: false, recordInteractions: true),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(link).center);
    await tester.pump();
    expect(scene.events, isEmpty);
    await tester.pumpWidget(
      scene.widget(callbackRevision: 2, recordInteractions: true),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(link).center);
    await tester.pump();
    expect(scene.events, ['2:interaction', '2:https://example.invalid/nested']);
  });

  testWidgets(
    'callback-only and equal-value updates retain folds and decoration',
    (tester) async {
      final scene = _Scene();
      await tester.pumpWidget(scene.widget());
      await tester.pumpAndSettle();
      final fold = tester.widget<ForumCollapseBlock>(
        find.byType(ForumCollapseBlock),
      );
      final nested = tester.element(
        find.text('Nested link', findRichText: true),
      );
      final decorations = scene.decorations;
      for (var revision = 1; revision <= 5; revision++) {
        await tester.pumpWidget(scene.widget(callbackRevision: revision));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ForumCollapseBlock>(find.byType(ForumCollapseBlock)),
          same(fold),
        );
        expect(
          tester.element(find.text('Nested link', findRichText: true)),
          same(nested),
        );
        expect(scene.decorations, decorations);
      }
      await tester.tapAt(
        tester.getRect(find.text('Nested link', findRichText: true)).center,
      );
      await tester.pump();
      expect(scene.events, ['5:https://example.invalid/nested']);
    },
  );

  testWidgets(
    'labels update fold chrome without repaint decorator notifications',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final scene = _Scene();
        await tester.pumpWidget(scene.widget());
        await tester.pumpAndSettle();
        final nested = tester.element(
          find.text('Nested link', findRichText: true),
        );
        final decorations = scene.decorations;
        const labels = ForumHtmlCollapseLabels(
          fallbackTitle: 'New title',
          expandedSemanticsLabel: 'Close details',
          collapsedSemanticsLabel: 'Open details',
        );
        await tester.pumpWidget(scene.widget(labels: labels));
        await tester.pumpAndSettle();
        expect(find.text('New title', findRichText: true), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Close details')), findsOneWidget);
        expect(
          tester.element(find.text('Nested link', findRichText: true)),
          same(nested),
        );
        expect(scene.decorations, decorations);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('decorator replacement retains the expanded fold widget', (
    tester,
  ) async {
    final scene = _Scene();
    await tester.pumpWidget(scene.widget());
    await tester.pumpAndSettle();
    final fold = tester.widget<ForumCollapseBlock>(
      find.byType(ForumCollapseBlock),
    );
    await tester.pumpWidget(
      scene.widget(
        decorator: (_, child) => _PaintMarker(revision: 2, child: child),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_PaintMarker), findsWidgets);
    expect(
      tester
          .widgetList<_PaintMarker>(find.byType(_PaintMarker))
          .every((marker) => marker.revision == 2),
      isTrue,
    );
    expect(
      tester.widget<ForumCollapseBlock>(find.byType(ForumCollapseBlock)),
      same(fold),
    );
    expect(find.text('Nested link', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'layout changes reach nested text and mutable expansion is observed',
    (tester) async {
      final scene = _Scene();
      final expansion = <String, bool>{'configuration-fold': true};
      await tester.pumpWidget(scene.widget(expansion: expansion));
      await tester.pumpAndSettle();
      final height = tester
          .getSize(find.byType(ForumHtmlRenderer).first)
          .height;
      final options = renderTestOptions.copyWith(fontScale: 1.8);
      await tester.pumpWidget(
        scene.widget(options: options, expansion: expansion),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ForumHtmlRenderer).first).height,
        greaterThan(height),
      );
      expansion['configuration-fold'] = false;
      await tester.pumpWidget(
        scene.widget(options: options, expansion: expansion),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nested link', findRichText: true), findsNothing);
    },
  );
}

final class _Scene {
  final document = prepareRenderTestDocument(_html, sourceId: 'configuration');
  final appTheme = ThemeData.light();
  final events = <String>[];
  int decorations = 0;
  Widget decorate(BuildContext context, Widget child) {
    decorations++;
    return _PaintMarker(revision: 1, child: child);
  }

  Widget widget({
    int callbackRevision = 0,
    ForumHtmlCollapseLabels? labels,
    ForumHtmlBlockDecorator? decorator,
    ForumHtmlRenderOptions options = renderTestOptions,
    Map<String, bool>? expansion,
    bool handlesUrl = true,
    bool recordInteractions = false,
  }) => MaterialApp(
    theme: appTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 300,
          child: ForumHtmlRenderer(
            preparedDocument: document,
            theme: _equalTheme(),
            options: options,
            sourceId: 'configuration',
            labels:
                labels ??
                ForumHtmlCollapseLabels(
                  fallbackTitle: renderTestLabels.fallbackTitle,
                  expandedSemanticsLabel:
                      renderTestLabels.expandedSemanticsLabel,
                  collapsedSemanticsLabel:
                      renderTestLabels.collapsedSemanticsLabel,
                ),
            callbacks: ForumHtmlRenderCallbacks(
              onInteraction: recordInteractions
                  ? () => events.add('$callbackRevision:interaction')
                  : null,
              onTapUrl: !handlesUrl
                  ? null
                  : (url) {
                      events.add('$callbackRevision:$url');
                      return true;
                    },
            ),
            collapseExpansion: expansion,
            blockDecorator: decorator ?? decorate,
            buildAsync: false,
            enableCaching: true,
          ),
        ),
      ),
    ),
  );
}

ForumHtmlThemeContext _equalTheme() => ForumHtmlThemeContext(
  brightness: forumHtmlTestTheme.brightness,
  surface: forumHtmlTestTheme.surface,
  foreground: forumHtmlTestTheme.foreground,
  link: forumHtmlTestTheme.link,
  quoteSurface: forumHtmlTestTheme.quoteSurface,
  quoteForeground: forumHtmlTestTheme.quoteForeground,
  codeSurface: forumHtmlTestTheme.codeSurface,
  codeForeground: forumHtmlTestTheme.codeForeground,
);

class _PaintMarker extends StatelessWidget {
  const _PaintMarker({required this.revision, required this.child});
  final int revision;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
