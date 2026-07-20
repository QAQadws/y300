import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_text_run.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_text_pagination.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_text_range_slicer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_text_run_extractor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_text_pagination_engine.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const classifier = NovelReaderPaginationAtomClassifier();

  test('lays out CJK and mixed text once and emits valid HTML chunks', () {
    final source = List<String>.filled(
      24,
      '中文段落 mixed 123 punctuation，。！？ ',
    ).join();
    final prepared = _safeAtom('<p><strong>$source</strong></p>');
    final engine = DefaultNovelReaderTextPaginationEngine();

    final result = engine.paginate(
      atom: prepared.$1,
      runs: prepared.$2,
      width: 160,
      pageHeight: 120,
      paragraphSpacing: 12,
      typographySignature: 'font=18.5|line=1.6',
    );

    expect(result.layoutCount, 1);
    expect(result.metricsCacheHit, isFalse);
    expect(result.metrics.lineRanges, isNotEmpty);
    expect(result.chunks.length, greaterThan(1));
    expect(
      result.chunks
          .map((chunk) => html_parser.parseFragment(chunk.html).text ?? '')
          .join(),
      source,
    );
    for (final chunk in result.chunks) {
      expect(html_parser.parseFragment(chunk.html).nodes, isNotEmpty);
      expect(chunk.usedHeight, greaterThan(0));
      expect(chunk.sourceEnd, greaterThan(chunk.sourceStart));
    }
    for (var index = 1; index < result.chunks.length; index += 1) {
      expect(
        result.chunks[index - 1].endAnchor.textOffset,
        result.chunks[index].startAnchor.textOffset,
      );
    }
  });

  test('preserves nbsp, explicit breaks and styled run boundaries', () {
    final prepared = _safeAtom(
      '<p>第一行&nbsp;A<br><span style="color:#123456">第二行B</span><br><br>末行</p>',
    );
    final result = DefaultNovelReaderTextPaginationEngine().paginate(
      atom: prepared.$1,
      runs: prepared.$2,
      width: 120,
      pageHeight: 90,
      paragraphSpacing: 8,
      typographySignature: 'nbsp-breaks',
    );

    expect(prepared.$2.any((run) => run.text.contains('\u00a0')), isTrue);
    expect(prepared.$2.where((run) => run.isParagraphBreak), hasLength(3));
    expect(result.metrics.lineRanges.length, greaterThanOrEqualTo(3));
    expect(
      result.chunks.map((chunk) => chunk.html).join(),
      contains('<span style="color:#123456">'),
    );
  });

  test('reuses metrics and invalidates on width or style changes', () {
    final cache = NovelReaderTextMetricsCache(capacity: 4);
    final engine = DefaultNovelReaderTextPaginationEngine(metricsCache: cache);
    final prepared = _safeAtom('<p>${List.filled(12, '缓存正文').join()}</p>');

    final first = _paginate(engine, prepared, width: 180);
    final second = _paginate(engine, prepared, width: 180);
    final changedWidth = _paginate(engine, prepared, width: 181);
    final changedStylePrepared = _safeAtom(
      '<p><strong>${List.filled(12, '缓存正文').join()}</strong></p>',
    );
    final changedStyle = _paginate(engine, changedStylePrepared, width: 180);

    expect(first.layoutCount, 1);
    expect(second.layoutCount, 0);
    expect(second.metricsCacheHit, isTrue);
    expect(changedWidth.layoutCount, 1);
    expect(changedStyle.layoutCount, 1);
    expect(cache.length, 3);
  });

  test('keeps headings whole even when their measured height is oversized', () {
    final prepared = _safeAtom(
      '<h2>${List.filled(12, '完整标题').join()}</h2>',
      kind: NovelReaderPaginationAtomKind.heading,
    );
    final result = DefaultNovelReaderTextPaginationEngine().paginate(
      atom: prepared.$1,
      runs: prepared.$2,
      width: 120,
      pageHeight: 20,
      paragraphSpacing: 12,
      typographySignature: 'heading',
    );

    expect(result.chunks, hasLength(1));
    expect(result.chunks.single.isOversized, isTrue);
    expect(result.chunks.single.sourceStart, 0);
    expect(result.chunks.single.sourceEnd, prepared.$1.atom.textLength);
  });

  test('rejects ruby and other non-safe routes before TextPainter layout', () {
    final atom = _atom('<p><ruby>字<rt>じ</rt></ruby></p>');
    final classified = classifier.classify(
      atom: atom,
      baseStyle: _baseStyle,
      preferences: _preferences,
      theme: _theme,
    );

    expect(classified.route, NovelReaderPaginationRoute.rubyInline);
    expect(
      () => DefaultNovelReaderTextPaginationEngine().paginate(
        atom: classified,
        runs: const [],
        width: 180,
        pageHeight: 200,
        paragraphSpacing: 12,
        typographySignature: 'ruby',
      ),
      throwsArgumentError,
    );
  });

  test('one indexed slice session preserves nested wrappers across pages', () {
    const slicer = NovelReaderHtmlTextRangeSlicer();
    final session = slicer.prepare(
      '<p><strong>甲乙</strong><br><span style="color:#123456">丙丁</span></p>',
    );

    final first = session.slice(start: 0, end: 2);
    final second = session.slice(start: 2, end: 4);

    expect(html_parser.parseFragment(first).text, '甲乙');
    expect(first, contains('<strong>甲乙</strong>'));
    expect(first, isNot(contains('<span')));
    expect(html_parser.parseFragment(second).text, '丙丁');
    expect(second, contains('<br>'));
    expect(second, contains('color:#123456'));
  });
}

NovelReaderTextPaginationResult _paginate(
  DefaultNovelReaderTextPaginationEngine engine,
  _PreparedTextAtom prepared, {
  required double width,
}) {
  return engine.paginate(
    atom: prepared.$1,
    runs: prepared.$2,
    width: width,
    pageHeight: 120,
    paragraphSpacing: 12,
    typographySignature: 'font=18.5|line=1.6',
  );
}

_PreparedTextAtom _safeAtom(
  String html, {
  NovelReaderPaginationAtomKind kind = NovelReaderPaginationAtomKind.text,
}) {
  final atom = _atom(html, kind: kind);
  final classified = classifierForTest.classify(
    atom: atom,
    baseStyle: _baseStyle,
    preferences: _preferences,
    theme: _theme,
  );
  expect(classified.route, NovelReaderPaginationRoute.safeText);
  final runs = extractorForTest.extract(
    classifiedAtom: classified,
    baseStyle: _baseStyle,
    preferences: _preferences,
    theme: _theme,
  );
  return (classified, runs);
}

const classifierForTest = NovelReaderPaginationAtomClassifier();
const extractorForTest = NovelReaderPaginationTextRunExtractor();

typedef _PreparedTextAtom = (
  NovelReaderClassifiedPaginationAtom,
  List<NovelReaderPaginationTextRun>,
);

NovelReaderPaginationAtom _atom(
  String html, {
  NovelReaderPaginationAtomKind kind = NovelReaderPaginationAtomKind.text,
}) {
  final length = (html_parser.parseFragment(html).text ?? '').runes.length;
  return NovelReaderPaginationAtom(
    atomId: 'text-engine:atom',
    kind: kind,
    html: html,
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'text-engine',
      nodeId: 'node-1',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'text-engine',
      nodeId: 'node-1',
      textOffset: length,
    ),
    textLength: length,
    imageIndices: const <int>[],
    breakability: NovelReaderFlowUnitBreakability.text,
    imagePagePolicy: NovelReaderImagePagePolicy.inline,
  );
}

const _preferences = ForumHtmlReaderPreferences(
  typography: RichTextTypography(
    fontScale: 18.5 / 14,
    lineHeightScale: 1.6,
    paragraphSpacing: 12,
  ),
  conversionMode: TextConversionMode.none,
);

const _baseStyle = TextStyle(
  color: Color(0xFF4C3A21),
  fontSize: 18.5,
  height: 1.6,
);

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
