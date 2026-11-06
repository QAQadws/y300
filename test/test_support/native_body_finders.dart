import 'dart:ui' show TextBox;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

Finder findNativeBody(String sourceId) => find.byWidgetPredicate(
  (widget) =>
      widget is ForumNativeBodyFlow &&
      widget.prepared.sequence.sourceId == sourceId,
);

Finder findNativeBodyText(String text) => find.byWidgetPredicate(
  (widget) => switch (widget) {
    ForumBodyParagraphSurface() =>
      widget.lease.content.projection.text.contains(text),
    ForumBodyInlineParagraphSurface() =>
      widget.view.content.projection.display.text.contains(text),
    _ => false,
  },
  description: 'native body displaying "$text"',
);

Future<void> tapNativeBodyText(WidgetTester tester, String text) async {
  final finder = findNativeBodyText(text);
  final surface = tester.widget(finder);
  final (
    String visible,
    List<TextBox> Function(int, int) boxes,
  ) = switch (surface) {
    ForumBodyParagraphSurface() => (
      surface.lease.content.projection.text,
      surface.lease.layout.selectionBoxes,
    ),
    ForumBodyInlineParagraphSurface() => (
      surface.view.content.projection.display.text,
      surface.view.selectionBoxes,
    ),
    _ => throw StateError('Expected a native text surface'),
  };
  final start = visible.indexOf(text);
  final first = boxes(start, start + text.length).first.toRect();
  await tester.tapAt(tester.getTopLeft(finder) + first.center);
}
