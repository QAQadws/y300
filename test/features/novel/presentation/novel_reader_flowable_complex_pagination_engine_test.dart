import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_flowable_complex_pagination_engine.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_layout_policy_resolver.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  late NovelReaderPreparedChapter chapter;
  late NovelReaderPaginationKey key;

  setUp(() {
    chapter = _chapter();
    key = _key(chapter);
  });

  test('keeps a fitting whole atom on the current page', () async {
    final session = _RecordingSession((request) {
      return request.html.startsWith('<p>前文</p>') ? 60 : 40;
    });

    final result = await _paginate(
      text: '复杂标题',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '<p>前文</p>',
        hasBufferedContent: true,
        availableHeight: 100,
      ),
      chapter: chapter,
      key: key,
      session: session,
    );

    expect(result.requiresAtomicFallback, isFalse);
    expect(result.chunks, hasLength(1));
    expect(result.chunks.single.requiresFreshPage, isFalse);
    expect(result.chunks.single.flushAfterAppend, isFalse);
    expect(result.chunks.single.composedHeight, 60);
    expect(result.probeCount, 1);
  });

  test('splits a long atom into continuous page-sized chunks', () async {
    final session = _RecordingSession(_rangeHeight);

    final result = await _paginate(
      text: 'abcdefghijkl',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '',
        hasBufferedContent: false,
        availableHeight: 40,
      ),
      chapter: chapter,
      key: key,
      session: session,
    );

    expect(result.requiresAtomicFallback, isFalse);
    expect(result.chunks, hasLength(3));
    expect(result.chunks.map((chunk) => chunk.slice.startOffset), <int>[
      0,
      4,
      8,
    ]);
    expect(result.chunks.map((chunk) => chunk.slice.endOffset), <int>[
      4,
      8,
      12,
    ]);
    expect(result.chunks.map((chunk) => chunk.flushAfterAppend), <bool>[
      true,
      true,
      false,
    ]);
    for (var index = 1; index < result.chunks.length; index += 1) {
      expect(
        result.chunks[index - 1].slice.endAnchor.textOffset,
        result.chunks[index].slice.startAnchor.textOffset,
      );
    }
  });

  test(
    'retries a whole atom on a fresh page when minimum cannot fit',
    () async {
      final session = _RecordingSession((request) {
        final rangeHeight = _rangeHeight(request);
        return request.html.startsWith('<p>buffer</p>')
            ? rangeHeight + 95
            : rangeHeight;
      });

      final result = await _paginate(
        text: 'abcd',
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '<p>buffer</p>',
          hasBufferedContent: true,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        session: session,
      );

      expect(result.chunks, hasLength(1));
      expect(result.chunks.single.requiresFreshPage, isTrue);
      expect(result.chunks.single.flushAfterAppend, isFalse);
      expect(result.chunks.single.composedHeight, 40);
    },
  );

  test(
    'returns an explicit fallback when a minimum fragment overflows',
    () async {
      final result = await _paginate(
        text: 'abcd',
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '',
          hasBufferedContent: false,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        session: _RecordingSession((_) => 200),
      );

      expect(result.chunks, isEmpty);
      expect(
        result.fallbackReason,
        NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow,
      );
      expect(result.minimumFragmentCount, 1);
    },
  );

  test('maps non-monotonic measurements to an atomic fallback', () async {
    final result = await _paginate(
      text: 'abcdefghij',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '',
        hasBufferedContent: false,
        availableHeight: 80,
      ),
      chapter: chapter,
      key: key,
      session: _RecordingSession((request) {
        return switch (request.endOffset!) {
          10 => 100,
          5 => 70,
          7 => 60,
          final offset => offset * 10.0,
        };
      }),
    );

    expect(
      result.fallbackReason,
      NovelReaderFlowableComplexFallbackReason.nonMonotonicMeasurement,
    );
    expect(result.chunks, isEmpty);
  });

  test('rejects routes that are not flowable complex text', () async {
    final engine = const DefaultNovelReaderFlowableComplexPaginationEngine();
    final atom = _atom('ruby', route: NovelReaderPaginationRoute.rubyInline);

    await expectLater(
      engine.paginate(
        atom: atom,
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '',
          hasBufferedContent: false,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        measureSession: _RecordingSession(_rangeHeight),
        cancellationToken: NovelReaderPaginationCancellationToken(),
      ),
      throwsArgumentError,
    );
  });
}

Future<NovelReaderFlowableComplexPaginationResult> _paginate({
  required String text,
  required NovelReaderPaginationPageContext page,
  required NovelReaderPreparedChapter chapter,
  required NovelReaderPaginationKey key,
  required NovelReaderPaginationMeasureSession session,
}) {
  return const DefaultNovelReaderFlowableComplexPaginationEngine().paginate(
    atom: _atom(text),
    page: page,
    chapter: chapter,
    key: key,
    measureSession: session,
    cancellationToken: NovelReaderPaginationCancellationToken(),
  );
}

NovelReaderClassifiedPaginationAtom _atom(
  String text, {
  NovelReaderPaginationRoute route =
      NovelReaderPaginationRoute.flowableComplexText,
}) {
  final atom = NovelReaderPaginationAtom(
    atomId: 'complex:1',
    kind: NovelReaderPaginationAtomKind.text,
    html: '<font face="Fantasy Novel Font">$text</font>',
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'episode-1',
      nodeId: 'node-1',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'episode-1',
      nodeId: 'node-1',
      textOffset: text.length,
    ),
    textLength: text.length,
    imageIndices: const <int>[],
    breakability: NovelReaderFlowUnitBreakability.text,
    imagePagePolicy: NovelReaderImagePagePolicy.inline,
  );
  return NovelReaderClassifiedPaginationAtom(
    atom: atom,
    route: route,
    reason: route == NovelReaderPaginationRoute.flowableComplexText
        ? NovelReaderPaginationRouteReason.unsupportedFont
        : NovelReaderPaginationRouteReason.containsRuby,
    layoutPolicy: const DefaultNovelReaderPaginationLayoutPolicyResolver()
        .resolve(route),
  );
}

double _rangeHeight(NovelReaderPaginationMeasureRequest request) {
  return (request.endOffset! - request.startOffset!) * 10.0;
}

NovelReaderPreparedChapter _chapter() {
  const html = '<p>chapter</p>';
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: _theme,
    sourceId: 'episode-1',
    threadId: null,
    imageCacheOwnerId: null,
  );
  return NovelReaderPreparedChapter(
    episodeId: 'episode-1',
    contentHash: 'content-1',
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: document.themeSignature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

NovelReaderPaginationKey _key(NovelReaderPreparedChapter chapter) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: 100,
    typographySignature: 'font=18.5|line=1.6',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 13,
  );
}

typedef _HeightResolver =
    double Function(NovelReaderPaginationMeasureRequest request);

final class _RecordingSession implements NovelReaderPaginationMeasureSession {
  _RecordingSession(this.heightResolver);

  final _HeightResolver heightResolver;
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    requests.add(request);
    return NovelReaderPaginationMeasureResult(height: heightResolver(request));
  }

  @override
  Future<void> dispose() async {}
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
