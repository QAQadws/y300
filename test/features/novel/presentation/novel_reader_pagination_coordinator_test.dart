import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_incremental_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  test('coalesces concurrent requests for the same key', () async {
    final breaker = _DelayedBreaker();
    final coordinator = DefaultNovelReaderPaginationCoordinator(
      pageBreaker: breaker,
    );
    final chapter = _prepared('episode');
    final key = _key('episode');

    final first = coordinator.paginate(chapter: chapter, key: key);
    final second = coordinator.paginate(chapter: chapter, key: key);
    expect(identical(first, second), isTrue);
    expect(breaker.calls, 1);

    breaker.complete(_plan('episode'));
    expect(await first, same(await second));
    expect(coordinator.cache.length, 1);
  });

  test('does not cache a result from an invalidated generation', () async {
    final breaker = _DelayedBreaker();
    final coordinator = DefaultNovelReaderPaginationCoordinator(
      pageBreaker: breaker,
    );
    final first = coordinator.paginate(
      chapter: _prepared('episode'),
      key: _key('episode'),
    );
    coordinator.clear();
    breaker.complete(_plan('episode'));

    await expectLater(
      first,
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'staleRequest',
        ),
      ),
    );
    expect(coordinator.cache.length, 0);
  });

  test(
    'cancels an active cancellable breaker when the generation is cleared',
    () async {
      final breaker = _CancellableDelayedBreaker();
      final coordinator = DefaultNovelReaderPaginationCoordinator(
        pageBreaker: breaker,
      );
      final future = coordinator.paginate(
        chapter: _prepared('episode'),
        key: _key('episode'),
      );

      expect(breaker.token, isNotNull);
      coordinator.clear();
      expect(breaker.token!.isCancelled, isTrue);
      breaker.complete(_plan('episode'));

      await expectLater(
        future,
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'paginationCancelled',
          ),
        ),
      );
      expect(coordinator.cache.length, 0);
    },
  );

  test('coalesces and replays incremental progress for the same key', () async {
    final breaker = _IncrementalDelayedBreaker();
    final coordinator = DefaultNovelReaderPaginationCoordinator(
      pageBreaker: breaker,
    );
    final chapter = _prepared('episode');
    final key = _key('episode');

    final first = coordinator.paginateIncrementally(chapter: chapter, key: key);
    final firstPartial = first.first;
    breaker.emit(_progress('episode', isComplete: false));
    expect((await firstPartial).isComplete, isFalse);

    final second = coordinator.paginateIncrementally(
      chapter: chapter,
      key: key,
    );
    expect((await second.first).isComplete, isFalse);
    expect(breaker.calls, 1);

    final completed = coordinator
        .paginateIncrementally(chapter: chapter, key: key)
        .firstWhere((progress) => progress.isComplete);
    breaker.emit(_progress('episode', isComplete: true));
    await breaker.close();

    expect((await completed).isComplete, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.cache.length, 1);
  });

  test('drops late incremental writes from a cancelled generation', () async {
    final breaker = _IncrementalDelayedBreaker();
    final coordinator = DefaultNovelReaderPaginationCoordinator(
      pageBreaker: breaker,
    );
    final events = <NovelReaderPaginationProgress>[];
    final cancelled = Completer<void>();

    coordinator
        .paginateIncrementally(
          chapter: _prepared('episode'),
          key: _key('episode'),
        )
        .listen(
          events.add,
          onError: (Object error, StackTrace stackTrace) {
            expect(
              error,
              isA<NovelReaderPaginationException>().having(
                (value) => value.code,
                'code',
                'paginationCancelled',
              ),
            );
            if (!cancelled.isCompleted) {
              cancelled.complete();
            }
          },
        );

    coordinator.cancelPending();
    await cancelled.future;
    expect(breaker.token?.isCancelled, isTrue);

    breaker.emit(_progress('episode', isComplete: true));
    await breaker.close();
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    expect(coordinator.cache.length, 0);
  });
}

NovelReaderPreparedChapter _prepared(String episodeId) {
  const theme = ForumHtmlThemeContext(
    brightness: ForumHtmlBrightness.light,
    surface: Color(0xFFF4EAD7),
    foreground: Color(0xFF4C3A21),
    link: Color(0xFF6A55A3),
    quoteSurface: Color(0xFFE8D8B8),
    quoteForeground: Color(0xFF8B7355),
    codeSurface: Color(0xFFEFE0C4),
    codeForeground: Color(0xFF4C3A21),
  );
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: '<p>测试</p>',
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: theme,
    sourceId: episodeId,
    threadId: '100',
    imageCacheOwnerId: '100',
  );
  return NovelReaderPreparedChapter(
    episodeId: episodeId,
    contentHash: 'content',
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: theme.signature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

NovelReaderPaginationKey _key(String episodeId) {
  return NovelReaderPaginationKey(
    episodeId: episodeId,
    contentHash: 'content',
    viewportWidthPx: 320,
    viewportHeightPx: 600,
    typographySignature: 'typography',
    themeSignature: 'theme',
    imageDimensionRevision: 1,
    rendererRevision: 1,
  );
}

NovelReaderPaginationPlan _plan(String episodeId) {
  return NovelReaderPaginationPlan(
    key: _key(episodeId),
    episodeId: episodeId,
    pages: const [],
  );
}

NovelReaderPaginationProgress _progress(
  String episodeId, {
  required bool isComplete,
}) {
  return NovelReaderPaginationProgress(
    plan: _plan(episodeId),
    isComplete: isComplete,
    processedAtomCount: isComplete ? 1 : 0,
    totalAtomCount: 1,
  );
}

class _DelayedBreaker implements NovelReaderPageBreaker {
  final Completer<NovelReaderPaginationPlan> completer =
      Completer<NovelReaderPaginationPlan>();
  int calls = 0;

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) {
    calls += 1;
    return completer.future;
  }

  void complete(NovelReaderPaginationPlan plan) => completer.complete(plan);
}

class _CancellableDelayedBreaker
    implements NovelReaderPageBreaker, NovelReaderCancellablePageBreaker {
  final Completer<NovelReaderPaginationPlan> completer =
      Completer<NovelReaderPaginationPlan>();
  NovelReaderPaginationCancellationToken? token;

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) => completer.future;

  @override
  Future<NovelReaderPaginationPlan> paginateCancellable(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
    NovelReaderPaginationCancellationToken cancellationToken,
  ) {
    token = cancellationToken;
    return completer.future;
  }

  void complete(NovelReaderPaginationPlan plan) => completer.complete(plan);
}

class _IncrementalDelayedBreaker
    implements NovelReaderPageBreaker, NovelReaderIncrementalPaginationPlanner {
  final StreamController<NovelReaderPaginationProgress> _controller =
      StreamController<NovelReaderPaginationProgress>();
  int calls = 0;
  NovelReaderPaginationCancellationToken? token;

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) async {
    return (await planIncrementally(
      chapter: chapter,
      key: key,
      cancellationToken: NovelReaderPaginationCancellationToken(),
    ).firstWhere((progress) => progress.isComplete)).plan;
  }

  @override
  Stream<NovelReaderPaginationProgress> planIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) {
    calls += 1;
    token = cancellationToken;
    return _controller.stream;
  }

  void emit(NovelReaderPaginationProgress progress) {
    _controller.add(progress);
  }

  Future<void> close() => _controller.close();
}
