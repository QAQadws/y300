import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'package:forum_content_renderer_example/main.dart';

void main() {
  testWidgets('standalone public API example expands its rendered body', (
    tester,
  ) async {
    await tester.pumpWidget(const ForumContentRendererExample());
    await tester.pumpAndSettle();

    const body =
        'This body uses the public renderer without an application provider.';
    expect(find.byType(ForumHtmlRenderer), findsWidgets);
    expect(
      find.text('A renderer with explicit Host inputs.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(body, findRichText: true), findsNothing);

    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-example-details')),
    );
    await tester.pumpAndSettle();

    expect(find.text(body, findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
