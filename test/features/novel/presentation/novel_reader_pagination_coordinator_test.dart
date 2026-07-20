import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
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
