import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  test(
    'cancellation listeners are scoped and cancelled yields leave no timer',
    () {
      fakeAsync((async) {
        final token = NovelReaderPaginationCancellationToken();
        var removedCalls = 0;
        var activeCalls = 0;
        token.onCancel(() => removedCalls += 1)();
        token.onCancel(() => activeCalls += 1);
        Object? error;
        unawaited(
          token.yieldToEventLoop().then<void>(
            (_) {},
            onError: (Object value) {
              error = value;
            },
          ),
        );
        expect(async.nonPeriodicTimerCount, 1);

        token.cancel();
        token.cancel();
        async.flushMicrotasks();
        expect(removedCalls, 0);
        expect(activeCalls, 1);
        expect(async.nonPeriodicTimerCount, 0);
        expect(error, _exceptionCode('paginationCancelled'));
        token.onCancel(() => activeCalls += 1);
        expect(activeCalls, 2);
      });
    },
  );

  test(
    'cancelled waits observe late success and errors without resettling',
    () async {
      for (final fail in <bool>[false, true]) {
        final token = NovelReaderPaginationCancellationToken();
        final gate = Completer<int>();
        final result = token.waitFor(gate.future);
        final cancelled = expectLater(
          result,
          throwsA(_exceptionCode('paginationCancelled')),
        );
        token.cancel();
        await cancelled;
        if (fail) {
          gate.completeError(StateError('late measurement'));
        } else {
          gate.complete(42);
        }
        await Future<void>.delayed(Duration.zero);
      }
    },
  );

  test('coalesces identical in-flight range measurements', () async {
    final delegate = _DelayedMeasureSession();
    final session = NovelReaderCachingPaginationMeasureSession(
      delegate: delegate,
    );
    final request = _request(html: '<p>same</p>');

    final first = session.measure(request);
    final second = session.measure(request);
    expect(delegate.calls, 1);

    delegate.complete(42);
    final firstResult = await first;
    final secondResult = await second;

    expect(firstResult.height, 42);
    expect(firstResult.fromCache, isFalse);
    expect(firstResult.frameWaitCount, 3);
    expect(secondResult.height, 42);
    expect(secondResult.fromCache, isTrue);
    expect(secondResult.frameWaitCount, 0);
    expect(session.cache.length, 1);

    final cached = await session.measure(request);
    expect(cached.height, 42);
    expect(cached.fromCache, isTrue);
    expect(cached.frameWaitCount, 0);
    expect(delegate.calls, 1);
    await session.dispose();
  });

  test('keeps different ranges and layouts isolated', () async {
    final delegate = _CountingMeasureSession();
    final session = NovelReaderCachingPaginationMeasureSession(
      delegate: delegate,
      cache: NovelReaderPaginationMeasureCache(capacity: 2),
    );
    final first = _request(html: '<p>one</p>', startOffset: 0, endOffset: 3);
    final second = _request(html: '<p>two</p>', startOffset: 3, endOffset: 6);
    final third = _request(
      html: '<p>one</p>',
      startOffset: 0,
      endOffset: 3,
      viewportHeight: 601,
    );

    expect((await session.measure(first)).fromCache, isFalse);
    expect((await session.measure(second)).fromCache, isFalse);
    expect((await session.measure(first)).fromCache, isTrue);
    expect((await session.measure(third)).fromCache, isFalse);
    expect((await session.measure(second)).fromCache, isFalse);
    expect(delegate.calls, 4);
    await session.dispose();
  });

  test('shares exact metrics across isolated measurement sessions', () async {
    final cache = NovelReaderPaginationMeasureCache(capacity: 4);
    final firstDelegate = _CountingMeasureSession();
    final firstSession = NovelReaderCachingPaginationMeasureSession(
      delegate: firstDelegate,
      cache: cache,
    );
    final request = _request(html: '<p>shared</p>');

    expect((await firstSession.measure(request)).fromCache, isFalse);
    await firstSession.dispose();

    final secondDelegate = _CountingMeasureSession();
    final secondSession = NovelReaderCachingPaginationMeasureSession(
      delegate: secondDelegate,
      cache: cache,
    );
    final result = await secondSession.measure(request);

    expect(result.fromCache, isTrue);
    expect(firstDelegate.calls, 1);
    expect(secondDelegate.calls, 0);
    await secondSession.dispose();
  });

  test('coalesces exact in-flight metrics across isolated sessions', () async {
    final cache = NovelReaderPaginationMeasureCache(capacity: 4);
    final firstDelegate = _DelayedMeasureSession();
    final secondDelegate = _CountingMeasureSession();
    final firstSession = NovelReaderCachingPaginationMeasureSession(
      delegate: firstDelegate,
      cache: cache,
    );
    final secondSession = NovelReaderCachingPaginationMeasureSession(
      delegate: secondDelegate,
      cache: cache,
    );
    final request = _request(html: '<p>shared in flight</p>');

    final first = firstSession.measure(request);
    final second = secondSession.measure(request);
    expect(firstDelegate.calls, 1);
    expect(secondDelegate.calls, 0);

    firstDelegate.complete(64);
    expect((await first).fromCache, isFalse);
    expect((await second).fromCache, isTrue);
    expect(secondDelegate.calls, 0);
    await firstSession.dispose();
    await secondSession.dispose();
  });

  test(
    'an active shared waiter remeasures when the metric owner exits',
    () async {
      final cache = NovelReaderPaginationMeasureCache();
      final ownerDelegate = _DisposingMeasureSession();
      final nextDelegate = _CountingMeasureSession();
      final owner = NovelReaderCachingPaginationMeasureSession(
        delegate: ownerDelegate,
        cache: cache,
      );
      final next = NovelReaderCachingPaginationMeasureSession(
        delegate: nextDelegate,
        cache: cache,
      );
      final request = _request(html: '<p>shared owner</p>');
      final old = owner.measure(request);
      final fresh = next.measure(request);
      final oldError = expectLater(
        old,
        throwsA(_exceptionCode('measurementSessionDisposed')),
      );
      expect(nextDelegate.calls, 0);

      await owner.dispose();
      await oldError;
      expect((await fresh).height, request.html.length.toDouble());
      expect(nextDelegate.calls, 1);
      expect(cache.length, 1);
      await next.dispose();
    },
  );

  test(
    'a disposed caching session cannot serve stale cached metrics',
    () async {
      final session = NovelReaderCachingPaginationMeasureSession(
        delegate: _CountingMeasureSession(),
      );
      final request = _request(html: '<p>disposed</p>');

      await session.measure(request);
      await session.dispose();

      await expectLater(
        session.measure(request),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'measurementSessionDisposed',
          ),
        ),
      );
    },
  );

  testWidgets('reuses one HTML probe for sequential candidates', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final chapter = await _prepare();
    final key = _key(chapter);
    final adapter = NovelReaderHtmlPaginationMeasureAdapter(
      hostContext: hostContext,
      theme: _theme,
      preferences: ForumHtmlReaderPreferences.defaults(),
      sourceId: chapter.episodeId,
      threadId: '100',
      imageCacheOwnerId: '100',
    );
    final session = adapter.create(chapter: chapter, key: key);

    final firstFuture = session.measure(
      NovelReaderPaginationMeasureRequest(
        html: '<p>第一段正文。</p>',
        chapter: chapter,
        key: key,
        atomId: 'text',
        startOffset: 0,
        endOffset: 6,
      ),
    );
    await tester.pump();
    await tester.pump();
    final first = await firstFuture;

    final secondFuture = session.measure(
      NovelReaderPaginationMeasureRequest(
        html: '<p>第二段正文，长度不同。<br/>第二行正文。<br/>第三行正文。</p>',
        chapter: chapter,
        key: key,
        atomId: 'text',
        startOffset: 6,
        endOffset: 15,
      ),
    );
    await tester.pump();
    await tester.pump();
    final second = await secondFuture;

    expect(first.height, greaterThan(0));
    expect(second.height, greaterThan(0));
    expect(second.height, isNot(first.height));
    expect(first.frameWaitCount, greaterThan(0));
    expect(second.frameWaitCount, greaterThan(0));
    await session.dispose();
    await tester.pump();
  });

  testWidgets('disposing a real session completes pending work', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final chapter = await _prepare();
    final key = _key(chapter);
    final session = NovelReaderHtmlPaginationMeasureAdapter(
      hostContext: hostContext,
      theme: _theme,
      preferences: ForumHtmlReaderPreferences.defaults(),
      sourceId: chapter.episodeId,
    ).create(chapter: chapter, key: key);
    final pending = session.measure(
      NovelReaderPaginationMeasureRequest(
        html: '<p>pending candidate</p>',
        chapter: chapter,
        key: key,
      ),
    );

    final dispose = session.dispose();
    await expectLater(
      pending,
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'measurementSessionDisposed',
        ),
      ),
    );
    await dispose;
  });

  testWidgets(
    'timeout includes initial frame wait and a new probe can recover',
    (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final chapter = _chapter();
      final key = _key(chapter);
      final session = _htmlSession(hostContext, chapter, key);
      addTearDown(session.dispose);
      final pending = session.measure(
        NovelReaderPaginationMeasureRequest(
          html: '<p>timed out old candidate</p>',
          chapter: chapter,
          key: key,
        ),
      );
      var timeoutSettled = false;
      final timedOut = expectLater(
        pending,
        throwsA(_exceptionCode('measurementTimeout')),
      ).then((_) => timeoutSettled = true);
      await tester.idle(); // Enter endOfFrame without delivering that frame.
      await tester.pump(const Duration(milliseconds: 801));
      await tester.idle();
      expect(
        timeoutSettled,
        isTrue,
        reason:
            'The initial host wait must settle at the single-probe deadline.',
      );
      await timedOut;
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);

      final fresh = session.measure(
        NovelReaderPaginationMeasureRequest(
          html: '<p>fresh candidate</p>',
          chapter: chapter,
          key: key,
        ),
      );
      NovelReaderPaginationMeasureResult? freshResult;
      Object? freshError;
      unawaited(
        fresh.then<void>(
          (result) {
            freshResult = result;
          },
          onError: (Object error, StackTrace stack) {
            freshError = error;
          },
        ),
      );
      // Timeout cleanup and the serial tail may finish after the first pump.
      // Drive host insertion and probe layout with a bounded frame count.
      for (
        var frame = 0;
        frame < 6 && freshResult == null && freshError == null;
        frame += 1
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(freshError, isNull);
      expect(
        freshResult,
        isNotNull,
        reason: 'The replacement probe must finish within the driven frames.',
      );
      expect(freshResult!.height, greaterThan(0));
      await session.dispose();
      await tester.pump();
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dispose releases started frame wait and queued requests without a frame',
    (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final chapter = _chapter();
      final key = _key(chapter);
      final session = _htmlSession(hostContext, chapter, key);
      final waits = <Future<void>>[];
      for (final html in <String>['<p>first</p>', '<p>queued</p>']) {
        waits.add(
          expectLater(
            session.measure(
              NovelReaderPaginationMeasureRequest(
                html: html,
                chapter: chapter,
                key: key,
              ),
            ),
            throwsA(_exceptionCode('measurementSessionDisposed')),
          ),
        );
      }
      await tester.idle();
      await session.dispose();
      await Future.wait(waits);
      await tester.pump(const Duration(milliseconds: 801));
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dispose removes an inserted probe host before its next frame', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final chapter = _chapter();
    final key = _key(chapter);
    final session = _htmlSession(hostContext, chapter, key);
    final error = expectLater(
      session.measure(
        NovelReaderPaginationMeasureRequest(
          html: '<p>old probe</p>',
          chapter: chapter,
          key: key,
        ),
      ),
      throwsA(_exceptionCode('measurementSessionDisposed')),
    );
    await tester.pump(); // Insert the overlay; the probe has not painted yet.
    await session.dispose();
    await error;
    await tester.pump();
    expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);

    final freshSession = _htmlSession(hostContext, chapter, key);
    addTearDown(freshSession.dispose);
    final fresh = freshSession.measure(
      NovelReaderPaginationMeasureRequest(
        html: '<p>replacement probe</p>',
        chapter: chapter,
        key: key,
      ),
    );
    NovelReaderPaginationMeasureResult? freshResult;
    Object? freshError;
    unawaited(
      fresh.then<void>(
        (result) {
          freshResult = result;
        },
        onError: (Object error, StackTrace stack) {
          freshError = error;
        },
      ),
    );
    for (
      var frame = 0;
      frame < 6 && freshResult == null && freshError == null;
      frame += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(freshError, isNull);
    expect(
      freshResult,
      isNotNull,
      reason: 'The new session probe must finish within the driven frames.',
    );
    expect(freshResult!.height, greaterThan(0));
    await freshSession.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('host setup errors settle once and leave no timeout behind', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final chapter = _chapter();
    final key = _key(chapter);
    final session = _htmlSession(hostContext, chapter, key);
    await expectLater(
      session.measure(
        NovelReaderPaginationMeasureRequest(
          html: '<p>no overlay</p>',
          chapter: chapter,
          key: key,
        ),
      ),
      throwsA(_exceptionCode('measurementHostUnavailable')),
    );
    await session.dispose();
    await tester.pump(const Duration(milliseconds: 801));
    expect(tester.takeException(), isNull);
  });
}

Matcher _exceptionCode(String code) => isA<NovelReaderPaginationException>()
    .having((error) => error.code, 'code', code);

NovelReaderPaginationMeasureSession _htmlSession(
  BuildContext context,
  NovelReaderPreparedChapter chapter,
  NovelReaderPaginationKey key,
) {
  return NovelReaderHtmlPaginationMeasureAdapter(
    hostContext: context,
    theme: _theme,
    preferences: ForumHtmlReaderPreferences.defaults(),
    sourceId: chapter.episodeId,
  ).create(chapter: chapter, key: key);
}

NovelReaderPaginationMeasureRequest _request({
  required String html,
  int startOffset = 0,
  int endOffset = 4,
  int viewportHeight = 600,
}) {
  final chapter = _chapter();
  return NovelReaderPaginationMeasureRequest(
    html: html,
    chapter: chapter,
    key: _key(chapter, viewportHeight: viewportHeight),
    atomId: 'atom',
    startOffset: startOffset,
    endOffset: endOffset,
  );
}

NovelReaderPreparedChapter _chapter() {
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: '<p>基础正文。</p>',
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: _theme,
    sourceId: 'measure-session-episode',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
  return NovelReaderPreparedChapter(
    episodeId: 'measure-session-episode',
    contentHash: 'measure-session-content',
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: document.themeSignature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

Future<NovelReaderPreparedChapter> _prepare() =>
    Future<NovelReaderPreparedChapter>.value(_chapter());

NovelReaderPaginationKey _key(
  NovelReaderPreparedChapter chapter, {
  int viewportHeight = 600,
}) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: viewportHeight,
    typographySignature: 'font=18.5|line=1.6',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 2,
  );
}

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);

class _DelayedMeasureSession implements NovelReaderPaginationMeasureSession {
  final Completer<NovelReaderPaginationMeasureResult> completer =
      Completer<NovelReaderPaginationMeasureResult>();
  int calls = 0;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) {
    calls += 1;
    return completer.future;
  }

  void complete(double height) {
    completer.complete(
      NovelReaderPaginationMeasureResult(height: height, frameWaitCount: 3),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _CountingMeasureSession implements NovelReaderPaginationMeasureSession {
  int calls = 0;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    calls += 1;
    return NovelReaderPaginationMeasureResult(
      height: request.html.length.toDouble(),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _DisposingMeasureSession extends _DelayedMeasureSession {
  @override
  Future<void> dispose() async {
    if (!completer.isCompleted) {
      completer.completeError(
        const NovelReaderPaginationException(
          code: 'measurementSessionDisposed',
          message: 'Controlled owner exit.',
        ),
      );
    }
  }
}
