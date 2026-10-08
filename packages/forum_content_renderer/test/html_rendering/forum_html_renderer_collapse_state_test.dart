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

Widget _scene(Map<String, bool>? expansion) => MaterialApp(
  home: Scaffold(
    body: ForumHtmlRenderer(
      preparedDocument: prepareRenderTestDocument(_html, sourceId: 'body'),
      sourceId: 'body',
      theme: forumHtmlTestTheme,
      options: renderTestOptions,
      labels: renderTestLabels,
      collapseExpansion: expansion,
    ),
  ),
);
