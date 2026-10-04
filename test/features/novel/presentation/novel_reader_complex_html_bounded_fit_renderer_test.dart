import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_search_budget.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  final cases = <_LayoutCase>[
    (
      id: 'short buffered whole',
      theme: _lightTheme,
      preferences: _preferences(fontScale: 0.7, lineHeight: 1),
      width: 240,
      height: 200,
      textScale: 1,
      bufferedHtml: '<p>已读前文。</p>',
      html: '<span>复杂短标题。</span>',
      isShort: true,
    ),
    (
      id: 'sepia fresh fragment',
      theme: _sepiaTheme,
      preferences: _preferences(fontScale: 18.5 / 14, lineHeight: 1.6),
      width: 320,
      height: 200,
      textScale: 1,
      bufferedHtml: '',
      html: _longHtml(),
      isShort: false,
    ),
    (
      id: 'dark buffered fragment',
      theme: _darkTheme,
      preferences: _preferences(fontScale: 2, lineHeight: 2.5),
      width: 600,
      height: 260,
      textScale: 1,
      bufferedHtml: '<p>已读前文。</p>',
      html: _longHtml(),
      isShort: false,
    ),
    (
      id: 'scaled fresh ruby fragment',
      theme: _lightTheme,
      preferences: _preferences(fontScale: 1.15, lineHeight: 1.5),
      width: 420,
      height: 220,
      textScale: 1.4,
      bufferedHtml: '',
      html: _longHtml(withRuby: true),
      isShort: false,
    ),
  ];

  for (final testCase in cases) {
    testWidgets('bounded fit matches the real renderer: ${testCase.id}', (
      tester,
    ) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _app(
          testCase,
          Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final chapter = _prepare(testCase);
      final sourceText = _text(chapter.html);
      final startAnchor = NovelReaderTextAnchor(
        episodeId: chapter.episodeId,
        nodeId: 'bounded-node',
        formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
        textIdentity: NovelReaderAnchorFormat.textIdentity(sourceText),
      );
      final sliceSession = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
          .prepare(
            html: chapter.html,
            startAnchor: startAnchor,
            sourceAnchorProjection: NovelReaderSourceAnchorProjection(
              baseAnchor: startAnchor,
              semanticOffsetsBySourceRuneBoundary: List<int>.generate(
                sourceText.runes.length + 1,
                (index) => index,
              ),
            ),
          );
      final key = NovelReaderPaginationKey(
        episodeId: chapter.episodeId,
        contentHash: chapter.contentHash,
        viewportWidthPx: testCase.width,
        viewportHeightPx: testCase.height,
        typographySignature: testCase.id,
        themeSignature: chapter.themeSignature,
        imageDimensionRevision: chapter.imageDimensionRevision,
        rendererRevision: 18,
      );
      final session = _RecordingSession(
        NovelReaderHtmlPaginationMeasureAdapter(
          hostContext: hostContext,
          theme: testCase.theme,
          preferences: testCase.preferences,
          sourceId: chapter.episodeId,
          threadId: '100',
          imageCacheOwnerId: '100',
        ).create(chapter: chapter, key: key),
      );
      final cancellation = NovelReaderPaginationCancellationToken();
      const budget = NovelReaderComplexHtmlSearchBudget(
        initialWindowGraphemes: 64,
        maxWindowGraphemes: 1024,
        maxCandidateHtmlCodeUnits: 8192,
        maxCandidateDomNodes: 256,
      );
      const searcher = DefaultNovelReaderComplexHtmlFitSearcher(budget: budget);
      final context = NovelReaderPaginationMeasureContext(
        session: session,
        chapter: chapter,
        key: key,
        atomId: 'bounded-atom',
      );
      late NovelReaderComplexHtmlFitResult accepted;
      late String composedHtml;
      try {
        accepted = await _pumpUntilComplete(
          tester,
          searcher.findLargestFittingPrefix(
            session: sliceSession,
            startOffset: 0,
            bufferedPageHtml: testCase.bufferedHtml,
            availableHeight: testCase.height.toDouble(),
            context: context,
            cancellationToken: cancellation,
            preferredWindowGraphemes: 64,
          ),
        );
        _expectAccepted(accepted, sliceSession, testCase.height);
        expect(accepted.slice.startAnchor.textOffset, 0);
        expect(
          _text(accepted.slice.html),
          String.fromCharCodes(
            sourceText.runes.take(accepted.slice.endAnchor.textOffset),
          ),
        );
        composedHtml =
            '${accepted.requiresFreshPage ? '' : testCase.bufferedHtml}'
            '${accepted.slice.html}';
        expect(
          session.requests.any((request) => request.html == composedHtml),
          isTrue,
        );
        if (testCase.isShort) {
          expect(accepted.exhaustedAtom, isTrue);
          expect(accepted.requiresFreshPage, isFalse);
          expect(accepted.probeCount, 1);
          expect(session.requests, hasLength(1));
        } else {
          expect(accepted.exhaustedAtom, isFalse);
          expect(
            session.requests.first.endOffset,
            lessThan(sliceSession.textLength),
          );
          final next = await _pumpUntilComplete(
            tester,
            searcher.findLargestFittingPrefix(
              session: sliceSession,
              startOffset: accepted.slice.endOffset,
              bufferedPageHtml: '',
              availableHeight: testCase.height.toDouble(),
              context: context,
              cancellationToken: cancellation,
              preferredWindowGraphemes: 64,
            ),
          );
          _expectAccepted(next, sliceSession, testCase.height);
          expect(next.slice.startOffset, accepted.slice.endOffset);
          expect(
            next.slice.startAnchor.textOffset,
            accepted.slice.endAnchor.textOffset,
          );
          expect(
            next.slice.startAnchor.textIdentity,
            accepted.slice.endAnchor.textIdentity,
          );
          expect(
            next.slice.startAnchor.nodeId,
            accepted.slice.endAnchor.nodeId,
          );
          final remaining = sliceSession.slice(
            startOffset: next.slice.endOffset,
            endOffset: sliceSession.textLength,
          );
          final joinedHtml =
              '${accepted.slice.html}${next.slice.html}${remaining.html}';
          expect(_text(joinedHtml), sourceText);
          if (sliceSession.protectedRanges.isNotEmpty) {
            expect(
              html_parser
                  .parseFragment(accepted.slice.html)
                  .querySelectorAll('ruby'),
              hasLength(1),
              reason: 'The displayed accepted slice must exercise ruby layout.',
            );
            final ruby = html_parser
                .parseFragment(joinedHtml)
                .querySelectorAll('ruby');
            expect(ruby, hasLength(1));
            expect(ruby.single.querySelectorAll('rt'), hasLength(1));
            expect(ruby.single.querySelectorAll('rp'), hasLength(2));
          }
        }
        for (final request in session.requests) {
          expect(
            request.endOffset! - request.startOffset!,
            lessThanOrEqualTo(budget.maxWindowGraphemes),
          );
          expect(
            request.html.length,
            lessThanOrEqualTo(budget.maxCandidateHtmlCodeUnits),
          );
          expect(
            _nodeCount(request.html),
            lessThanOrEqualTo(budget.maxCandidateDomNodes),
          );
        }
      } finally {
        cancellation.cancel();
        await session.dispose();
        await tester.pump();
      }

      final rendererKey = GlobalKey();
      await tester.pumpWidget(
        _app(
          testCase,
          Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: testCase.width.toDouble(),
                  child: ForumHtmlWidgetPostRenderer(
                    key: rendererKey,
                    html: composedHtml,
                    theme: testCase.theme,
                    preparedDocument: chapter.renderDocument.copyWith(
                      preparedHtml: composedHtml,
                    ),
                    preferences: testCase.preferences,
                    sourceId: chapter.episodeId,
                    threadId: '100',
                    imageCacheOwnerId: '100',
                    buildAsync: false,
                    enableCaching: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(rendererKey)).height,
        closeTo(accepted.measuredHeight, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

typedef _LayoutCase = ({
  String id,
  ForumHtmlThemeContext theme,
  ForumHtmlReaderPreferences preferences,
  int width,
  int height,
  double textScale,
  String bufferedHtml,
  String html,
  bool isShort,
});

Widget _app(_LayoutCase testCase, Widget home) {
  return LocalizedTestApp(
    theme: ThemeData(
      brightness: testCase.theme.brightness == ForumHtmlBrightness.dark
          ? Brightness.dark
          : Brightness.light,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(testCase.textScale)),
      child: child!,
    ),
    home: home,
  );
}

Future<T> _pumpUntilComplete<T>(
  WidgetTester tester,
  Future<T> operation,
) async {
  var completed = false;
  unawaited(
    operation.then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace stack) => completed = true,
    ),
  );
  for (var frame = 0; frame < 100 && !completed; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    completed,
    isTrue,
    reason: 'The bounded search did not settle after frames.',
  );
  return operation;
}

void _expectAccepted(
  NovelReaderComplexHtmlFitResult fit,
  NovelReaderComplexHtmlSliceSession session,
  int height,
) {
  expect(fit.fits, isTrue);
  expect(fit.measuredHeight, lessThanOrEqualTo(height + 0.5));
  expect(fit.slice.endOffset, greaterThan(fit.slice.startOffset));
  expect(session.isLegalBoundary(fit.slice.startOffset), isTrue);
  expect(session.isLegalBoundary(fit.slice.endOffset), isTrue);
  for (final range in session.protectedRanges) {
    expect(range.containsInteriorOffset(fit.slice.startOffset), isFalse);
    expect(range.containsInteriorOffset(fit.slice.endOffset), isFalse);
  }
}

NovelReaderPreparedChapter _prepare(_LayoutCase testCase) {
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: testCase.html,
    preferences: testCase.preferences,
    theme: testCase.theme,
    sourceId: 'bounded-episode',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
  return NovelReaderPreparedChapter(
    episodeId: 'bounded-episode',
    contentHash: testCase.id,
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: document.themeSignature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

String _longHtml({bool withRuby = false}) {
  final ruby = withRuby ? '<ruby>鬼魂<rt>おに</rt><rp>(</rp><rp>)</rp></ruby>' : '';
  final body = List<String>.filled(24, '甲乙丙丁正文 mixed 123。').join();
  return '<font face="Fantasy Novel Font"><span>开始 é👩‍👩‍👧‍👦$ruby$body</span></font>';
}

String _text(String html) => html_parser.parseFragment(html).text ?? '';

int _nodeCount(String html) {
  final pending = html_parser.parseFragment(html).nodes.toList();
  var count = 0;
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    count += 1;
    pending.addAll(node.nodes);
  }
  return count;
}

ForumHtmlReaderPreferences _preferences({
  required double fontScale,
  required double lineHeight,
}) => ForumHtmlReaderPreferences.defaults().copyWith(
  typography: RichTextTypography(
    fontScale: fontScale,
    lineHeightScale: lineHeight,
    paragraphSpacing: ForumHtmlReaderPreferences.defaultParagraphSpacing,
  ),
);

final class _RecordingSession implements NovelReaderPaginationMeasureSession {
  _RecordingSession(this.delegate);

  final NovelReaderPaginationMeasureSession delegate;
  final requests = <NovelReaderPaginationMeasureRequest>[];

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) {
    requests.add(request);
    return delegate.measure(request);
  }

  @override
  Future<void> dispose() => delegate.dispose();
}

const _lightTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFAFAFA),
  foreground: Color(0xFF202020),
  link: Color(0xFF6550A0),
  quoteSurface: Color(0xFFEEEEEE),
  quoteForeground: Color(0xFF444444),
  codeSurface: Color(0xFFEEEEEE),
  codeForeground: Color(0xFF202020),
);

const _sepiaTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF171717),
  foreground: Color(0xFFE7E7E7),
  link: Color(0xFFB9A7FF),
  quoteSurface: Color(0xFF2A2A2A),
  quoteForeground: Color(0xFFD0D0D0),
  codeSurface: Color(0xFF242424),
  codeForeground: Color(0xFFF0F0F0),
);
