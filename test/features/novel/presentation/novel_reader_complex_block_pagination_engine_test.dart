import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_block_inspectors.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_block_pagination_engine.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const classifier = NovelReaderPaginationAtomClassifier();

  test(
    'keeps ruby clusters paired and measures the containing block once',
    () async {
      final atom = _atom(
        '<p>前<ruby>字<rt>じ</rt></ruby>'
        '<ruby>鬼魂<rt>Ghost</rt></ruby>后</p>',
      );
      final classified = _classify(classifier, atom);
      final measurer = _FakeComplexBlockMeasurer(height: 180);
      final chapter = _chapter(atom.html);

      final page = await const NovelReaderComplexBlockPaginationEngine()
          .paginate(
            atom: classified,
            chapter: chapter,
            key: _key(chapter, height: 600),
            measurer: measurer,
          );

      expect(classified.route, NovelReaderPaginationRoute.rubyInline);
      expect(measurer.calls, 1);
      expect(measurer.lastHtml, atom.html);
      expect(page.html, atom.html);
      expect(page.metrics.ruby?.clusters, hasLength(2));
      expect(page.metrics.ruby?.allClustersPaired, isTrue);
      expect(page.metrics.ruby?.annotationElementCount, 2);
      expect(page.metrics.ruby?.fallbackElementCount, 0);
      final first = page.metrics.ruby!.clusters.first;
      expect(first.baseStart, 1);
      expect(first.baseEnd, 2);
      expect(first.annotationStart, 2);
      expect(first.annotationEnd, 3);
      expect(first.clusterStart, 1);
      expect(first.clusterEnd, 3);
      expect(page.metrics.requiresInnerScroll, isFalse);
    },
  );

  test('describes nested collapse blocks and their initial states', () async {
    const html = '''
      <div class="showcollapse_box showcollapse_active" id="outer">
        <div class="showcollapse_title">外层</div>
        <div class="showcollapse_content">
          <div class="showcollapse_box" id="inner">
            <div class="showcollapse_title">内层</div>
            <div class="showcollapse_content">正文</div>
          </div>
        </div>
      </div>
    ''';

    final descriptor = const NovelReaderCollapsePaginationAdapter().inspect(
      html,
    );

    expect(descriptor.blocks, hasLength(2));
    expect(descriptor.blocks[0].blockId, startsWith('id-outer'));
    expect(descriptor.blocks[0].depth, 0);
    expect(descriptor.blocks[0].initiallyExpanded, isTrue);
    expect(descriptor.blocks[1].blockId, startsWith('id-inner'));
    expect(descriptor.blocks[1].depth, 1);
    expect(descriptor.blocks[1].initiallyExpanded, isFalse);
    expect(descriptor.expandedCount, 1);
    expect(descriptor.nestedCount, 1);

    final atom = _atom(html);
    final classified = _classify(classifier, atom);
    final chapter = _chapter(html);
    final page = await const NovelReaderComplexBlockPaginationEngine().paginate(
      atom: classified,
      chapter: chapter,
      key: _key(chapter, height: 600),
      measurer: _FakeComplexBlockMeasurer(height: 120),
    );
    expect(page.metrics.requiresInnerScroll, isTrue);
  });

  test(
    'keeps a table whole and marks an oversized block for inner scroll',
    () async {
      const html =
          '<table><tbody><tr><th>标题</th><td>正文</td></tr>'
          '<tr><td colspan="2">尾行</td></tr></tbody></table>';
      final atom = _atom(html);
      final classified = _classify(classifier, atom);
      final chapter = _chapter(html);
      final page = await const NovelReaderComplexBlockPaginationEngine()
          .paginate(
            atom: classified,
            chapter: chapter,
            key: _key(chapter, height: 100),
            measurer: _FakeComplexBlockMeasurer(height: 320),
          );

      expect(classified.route, NovelReaderPaginationRoute.tableBlock);
      expect(page.metrics.table?.tableCount, 1);
      expect(page.metrics.table?.rowCount, 2);
      expect(page.metrics.table?.cellCount, 3);
      expect(page.metrics.requiresInnerScroll, isTrue);
      expect(page.html, html);
      expect(
        html_parser.parseFragment(page.html).querySelectorAll('tr'),
        hasLength(2),
      );
    },
  );

  test(
    'propagates measurement cache and frame metadata without reflowing',
    () async {
      final atom = _atom('<blockquote>复杂引用</blockquote>');
      final classified = _classify(classifier, atom);
      final chapter = _chapter(atom.html);
      final page = await const NovelReaderComplexBlockPaginationEngine()
          .paginate(
            atom: classified,
            chapter: chapter,
            key: _key(chapter, height: 600),
            measurer: _FakeComplexBlockMeasurer(
              height: 80,
              fromCache: true,
              frameWaitCount: 0,
            ),
          );

      expect(classified.route, NovelReaderPaginationRoute.flowableComplexText);
      expect(page.metrics.measurementCacheHit, isTrue);
      expect(page.metrics.frameWaitCount, 0);
    },
  );

  test('turns a renderer timeout into an explicit inner-scroll page', () async {
    final atom = _atom('<blockquote>超时后仍需显示的复杂正文</blockquote>');
    final classified = _classify(classifier, atom);
    final chapter = _chapter(atom.html);

    final page = await const NovelReaderComplexBlockPaginationEngine().paginate(
      atom: classified,
      chapter: chapter,
      key: _key(chapter, height: 600),
      measurer: const _TimeoutComplexBlockMeasurer(),
    );

    expect(page.html, atom.html);
    expect(page.metrics.measurementTimedOut, isTrue);
    expect(page.metrics.isOversized, isTrue);
    expect(page.metrics.requiresInnerScroll, isTrue);
  });

  test('rejects safe text and isolated image routes', () async {
    final safe = _classify(classifier, _atom('<p>正文</p>'));
    final image = _classify(
      classifier,
      _atom(
        '<img src="image.jpg">',
        kind: NovelReaderPaginationAtomKind.image,
        imagePolicy: NovelReaderImagePagePolicy.isolated,
      ),
    );
    final chapter = _chapter('<p>正文</p>');
    final engine = const NovelReaderComplexBlockPaginationEngine();

    for (final classified in <NovelReaderClassifiedPaginationAtom>[
      safe,
      image,
    ]) {
      await expectLater(
        engine.paginate(
          atom: classified,
          chapter: chapter,
          key: _key(chapter, height: 600),
          measurer: _FakeComplexBlockMeasurer(height: 20),
        ),
        throwsArgumentError,
      );
    }
  });
}

NovelReaderClassifiedPaginationAtom _classify(
  NovelReaderPaginationAtomClassifier classifier,
  NovelReaderPaginationAtom atom,
) {
  return classifier.classify(
    atom: atom,
    baseStyle: _baseStyle,
    preferences: _preferences,
    theme: _theme,
  );
}

NovelReaderPaginationAtom _atom(
  String html, {
  NovelReaderPaginationAtomKind kind = NovelReaderPaginationAtomKind.text,
  NovelReaderImagePagePolicy imagePolicy = NovelReaderImagePagePolicy.inline,
}) {
  final length = (html_parser.parseFragment(html).text ?? '').runes.length;
  return NovelReaderPaginationAtom(
    atomId: 'complex:atom',
    kind: kind,
    html: html,
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'complex',
      nodeId: 'node-1',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'complex',
      nodeId: 'node-1',
      textOffset: length,
    ),
    textLength: length,
    imageIndices: imagePolicy == NovelReaderImagePagePolicy.isolated
        ? const <int>[0]
        : const <int>[],
    breakability: imagePolicy == NovelReaderImagePagePolicy.isolated
        ? NovelReaderFlowUnitBreakability.blockImage
        : NovelReaderFlowUnitBreakability.text,
    imagePagePolicy: imagePolicy,
  );
}

NovelReaderPreparedChapter _chapter(String html) {
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: _preferences,
    theme: _theme,
    sourceId: 'complex',
    threadId: null,
    imageCacheOwnerId: null,
  );
  return NovelReaderPreparedChapter(
    episodeId: 'complex',
    contentHash: 'complex-content',
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: document.themeSignature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

NovelReaderPaginationKey _key(
  NovelReaderPreparedChapter chapter, {
  required int height,
}) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: height,
    typographySignature: 'font=18.5|line=1.6',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 3,
  );
}

final class _FakeComplexBlockMeasurer
    implements NovelReaderComplexBlockMeasurer {
  _FakeComplexBlockMeasurer({
    required this.height,
    this.fromCache = false,
    this.frameWaitCount = 1,
  });

  final double height;
  final bool fromCache;
  final int frameWaitCount;
  int calls = 0;
  String? lastHtml;

  @override
  Future<NovelReaderPaginationMeasureResult> measure({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) async {
    calls += 1;
    lastHtml = atom.atom.html;
    return NovelReaderPaginationMeasureResult(
      height: height,
      fromCache: fromCache,
      frameWaitCount: frameWaitCount,
    );
  }
}

final class _TimeoutComplexBlockMeasurer
    implements NovelReaderComplexBlockMeasurer {
  const _TimeoutComplexBlockMeasurer();

  @override
  Future<NovelReaderPaginationMeasureResult> measure({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    throw const NovelReaderPaginationException(
      code: 'measurementTimeout',
      message: 'synthetic timeout',
    );
  }
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
