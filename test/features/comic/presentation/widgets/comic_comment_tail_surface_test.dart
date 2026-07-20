import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';

void main() {
  testWidgets('vertical tail waits for an explicit load action', (
    tester,
  ) async {
    final loader = _TailFakeLoader();
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
    );
    final tail = ComicCommentTailSurface(
      session: session,
      imageHeaderBuilder: null,
    );
    addTearDown(tail.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: tail,
                builder: (context, _) => tail.buildVertical(
                  context,
                  ReaderTailActions(
                    onRetry: () => unawaited(tail.onRetry()),
                    onAdvance: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('comic-comment-tail-load-button')),
      findsOneWidget,
    );
    expect(loader.calls, 0);
    await tester.tap(find.byKey(const Key('comic-comment-tail-load-button')));
    await tester.pump();
    await tester.pump();

    expect(loader.calls, 1);
    expect(
      find.byKey(const ValueKey<String>('comic-comment-tail-item-p2')),
      findsOneWidget,
    );
    expect(tail.verticalItemCount, 2);
  });

  test('success results expose one lazy vertical item per comment', () async {
    final loader = _TailFakeLoader();
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
    );
    final tail = ComicCommentTailSurface(
      session: session,
      imageHeaderBuilder: null,
    );
    addTearDown(tail.dispose);
    addTearDown(session.dispose);

    await session.load();

    expect(tail.verticalItemCount, 2);
    expect(tail.hasAdvance, isFalse);
  });

  test(
    'exposes a swipe advance surface only when the next episode exists',
    () async {
      final loader = _TailFakeLoader();
      var advances = 0;
      final session = ComicCommentSessionController(
        key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
        loader: loader,
      );
      final tail = ComicCommentTailSurface(
        session: session,
        imageHeaderBuilder: null,
        hasNextEpisode: true,
        onAdvanceEpisode: () => advances++,
      );
      addTearDown(tail.dispose);
      addTearDown(session.dispose);

      expect(tail.hasAdvance, isFalse);
      await session.load();

      expect(tail.hasAdvance, isTrue);
      await tail.onAdvance();
      expect(advances, 1);
      expect(tail.isAdjacentPreloadReady, isTrue);
    },
  );

  testWidgets('advance is an invisible swipe sentinel', (tester) async {
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: _TailFakeLoader(),
    );
    final tail = ComicCommentTailSurface(
      session: session,
      imageHeaderBuilder: null,
      hasNextEpisode: true,
      onAdvanceEpisode: () {},
    );
    addTearDown(tail.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => tail.buildAdvance(
              context,
              ReaderTailActions(onRetry: () {}, onAdvance: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('comic-comment-tail-advance-sentinel')),
      findsOneWidget,
    );
    expect(find.byType(ComicCommentFeedbackSurface), findsNothing);
    expect(find.textContaining('继续滑动进入'), findsNothing);
  });
}

class _TailFakeLoader implements ComicCommentLoader {
  int calls = 0;

  @override
  Future<ComicCommentLoadResult> loadAll({
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  }) async {
    calls += 1;
    return const ComicCommentLoadResult(
      sourceTid: '573279',
      status: ComicCommentLoadStatus.success,
      items: <ComicCommentItem>[
        ComicCommentItem(
          pid: 'p2',
          authorId: '8',
          authorName: '回复者',
          dateline: '刚刚',
          floorNumber: 2,
          rawMessage: '<p>评论正文</p>',
          avatarUrl: null,
        ),
      ],
      loadedPages: <int>{1},
      expectedPages: 1,
    );
  }
}
