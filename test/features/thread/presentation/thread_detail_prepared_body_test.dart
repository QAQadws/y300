import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/thread_detail_prepared_body.dart';

void main() {
  test('bounds pure retained values without evicting an admitted floor', () {
    final first = _body('a');
    final second = _body('b');
    final store = ThreadDetailPreparedBodyStore(maxBodies: 1);
    expect(store.admit('a', first), isTrue);
    expect(store.admit('b', second), isFalse);
    expect(store['a'], same(first));
    expect(store['b'], isNull);
    expect(store.retainedCodeUnits, first.retainedCodeUnits);
    expect(() => store.bodies.clear(), throwsUnsupportedError);
  });

  test(
    'input retirement releases its budget before another floor is admitted',
    () {
      final first = _body('a');
      final store = ThreadDetailPreparedBodyStore(
        maxRetainedCodeUnits: first.retainedCodeUnits,
      );
      expect(store.admit('a', first), isTrue);
      expect(store.admit('b', _body('b')), isFalse);
      store.retainWhere((pid, _) => pid != 'a');
      expect(store.retainedCodeUnits, 0);
      expect(store.admit('b', _body('b')), isTrue);
      store.clear();
      expect(store.bodies, isEmpty);
      expect(store.retainedCodeUnits, 0);
    },
  );
}

ThreadDetailPreparedBody _body(String pid) {
  final materialTheme = ThemeData.light();
  final request = ForumHtmlPreparationRequest(
    html: List.filled(6, 'line with text').join('<br>'),
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: materialTheme,
      surface: materialTheme.colorScheme.surface,
    ),
    sourceId: pid,
    threadId: 'thread',
    imageCacheOwnerId: 'thread',
    preparer: const DefaultForumHtmlRenderPreparer(),
  );
  final document = request.prepareSynchronously();
  return ThreadDetailPreparedBody(
    request: request,
    document: document.copyWith(
      safeDisplayPlan: const ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 1,
        targetChunkCodeUnits: 20,
        maxChunkCodeUnits: 1024,
      ).plan(document),
    ),
  );
}
