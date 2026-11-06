import 'package:forum_content_renderer/forum_content_renderer.dart';

/// The low-level layout fixtures can exercise authored levels directly.
/// Reader and PageSession tests go through the readable text flow instead.
ForumBodyRubyGroupContent readUnprojectedRubyGroup(
  ForumBodyStyledFlowCursor flow,
) {
  while (flow.moveNext()) {
    final event = flow.current!;
    if (event.phase != ForumBodyFlowPhase.open ||
        event.node is! ForumBodyElement ||
        (event.node as ForumBodyElement).kind != ForumBodyElementKind.ruby) {
      continue;
    }
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    try {
      while (!cursor.isComplete) {
        if (cursor.advance(maxEvents: 1).hasOutput) return cursor.current!;
      }
    } finally {
      cursor.close();
    }
  }
  throw StateError('Fixture has no ruby group');
}
