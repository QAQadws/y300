import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
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
