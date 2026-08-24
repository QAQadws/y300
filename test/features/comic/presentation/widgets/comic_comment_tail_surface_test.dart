import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_content_projection_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

void main() {
  testWidgets('vertical tail waits for an explicit load action', (
    tester,
  ) async {
    final loader = _TailFakeLoader();
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: loader,
    );
    final contentProjection = _projectionController(session);
    final tail = ComicCommentTailSurface(
      session: session,
      contentProjectionController: contentProjection,
      imageReferer: null,
    );
    addTearDown(tail.dispose);
    addTearDown(contentProjection.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
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
    final contentProjection = _projectionController(session);
    final tail = ComicCommentTailSurface(
      session: session,
      contentProjectionController: contentProjection,
      imageReferer: null,
    );
    addTearDown(tail.dispose);
    addTearDown(contentProjection.dispose);
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
      final contentProjection = _projectionController(session);
      final tail = ComicCommentTailSurface(
        session: session,
        contentProjectionController: contentProjection,
        imageReferer: null,
        hasNextEpisode: true,
        onAdvanceEpisode: () => advances++,
      );
      addTearDown(tail.dispose);
      addTearDown(contentProjection.dispose);
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
    final contentProjection = _projectionController(session);
    final tail = ComicCommentTailSurface(
      session: session,
      contentProjectionController: contentProjection,
      imageReferer: null,
      hasNextEpisode: true,
      onAdvanceEpisode: () {},
    );
    addTearDown(tail.dispose);
    addTearDown(contentProjection.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      LocalizedTestApp(
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

  testWidgets('vertical tail renders projected content with raw author', (
    tester,
  ) async {
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e1', sourceTid: '573279'),
      loader: _TailFakeLoader(),
    );
    final contentProjection = _projectionController(
      session,
      mode: TextConversionMode.toTraditional,
      converter: const _ReplacingConverter(),
    );
    final tail = ComicCommentTailSurface(
      session: session,
      contentProjectionController: contentProjection,
      imageReferer: null,
    );
    addTearDown(tail.dispose);
    addTearDown(contentProjection.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: tail,
                builder: (context, _) => tail.buildVerticalItem(
                  context,
                  ReaderTailActions(onRetry: () {}, onAdvance: () {}),
                  0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await session.load();
    await tester.pump();
    await tester.pump();

    expect(find.text('回复者'), findsOneWidget);
    expect(find.text('回覆者'), findsNothing);
    expect(find.text('剛剛'), findsOneWidget);
    final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(renderer.html, contains('評論正文'));
  });
}

ComicCommentContentProjectionController _projectionController(
  ComicCommentSessionController session, {
  TextConversionMode mode = TextConversionMode.none,
  TextConverter converter = const IdentityTextConverter(),
}) {
  final plainService = DefaultPlainTextBatchConversionService();
  return ComicCommentContentProjectionController(
    session: session,
    projector: ComicCommentContentProjector(
      plainTextBatchConversionService: plainService,
      htmlTextNodeConversionService: DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: plainService,
      ),
      diagnosticRecorder: const NoopTextConversionDiagnosticRecorder(),
    ),
    initialMode: mode,
    initialConverter: converter,
  );
}

final class _ReplacingConverter implements TextConverter {
  const _ReplacingConverter();

  @override
  String get id => 'test:traditional';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async {
    return html
        .replaceAll('刚刚', '剛剛')
        .replaceAll('评论', '評論')
        .replaceAll('回复', '回覆');
  }
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
