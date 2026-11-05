import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_anchor_map.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';

const _downstream = HtmlProjectionAffinity.downstream;
const _upstream = HtmlProjectionAffinity.upstream;

final class _Fixture {
  _Fixture(this.html) {
    semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    body = const ForumBodyParser().parse(
      html: html.trim(),
      sourceId: 'source',
      conversionIdentity: 'none',
    );
  }
  final String html;
  late final NovelReaderDocument semantic;
  late final ForumBodyDocument body;

  NovelReaderNativeAnchorMap bind({
    NovelReaderDocument? document,
    ForumBodyDocument? native,
    String episodeId = 'episode',
    String sourceId = 'source',
    NovelReaderNativeAnchorBindingLimits limits =
        const NovelReaderNativeAnchorBindingLimits(),
  }) => NovelReaderNativeAnchorBinder(limits: limits).bind(
    episodeId: episodeId,
    sourceId: sourceId,
    semanticDocument: document ?? semantic,
    bodyDocument: native ?? body,
  );

  ForumBodyParagraphContent content({String path = '0'}) {
    final styles = const ForumBodyStyleResolver().resolve(
      body,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 14),
        fontRevision: 'system',
        linkColor: const Color(0xFF0000FF),
      ),
    );
    return const ForumBodyParagraphContentBuilder().build(
      document: body,
      styles: styles,
      path: path,
    );
  }
}

NovelReaderDocument _copy(
  NovelReaderDocument document, {
  String? conversion = 'none',
  bool clearProvenance = false,
  List<NovelReaderTextSourceOrigin>? origins,
}) => NovelReaderDocument(
  episodeId: document.episodeId,
  rawHtmlHash: document.rawHtmlHash,
  body: document.body,
  plainText: document.plainText,
  wordCount: document.wordCount,
  textConversionIdentity: conversion,
  sourceProvenance: clearProvenance
      ? null
      : origins == null
      ? document.sourceProvenance
      : NovelReaderSourceProvenance(
          inputHash: document.sourceProvenance!.inputHash,
          origins: origins,
        ),
);

Matcher _failure(NovelReaderNativeAnchorBindingFailure failure) => throwsA(
  isA<NovelReaderNativeAnchorBindingException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  test(
    'search intervals keep source gaps and require the exact node identity',
    () {
      final fixture = _Fixture('<p><b>a</b>   <i>b</i></p><p>ab</p>');
      final map = fixture.bind();
      final hits = const NovelReaderSearchService().search(
        document: fixture.semantic,
        keyword: 'ab',
      );
      expect(hits, hasLength(2));
      expect(map.sourceRanges(hits[0].range), [
        ForumBodySourceRange(map.identity, 0, 1),
        ForumBodySourceRange(map.identity, 4, 5),
      ]);
      expect(map.sourceRanges(hits[1].range), [
        ForumBodySourceRange(map.identity, 5, 7),
      ]);
      expect(
        map.sourceRanges(
          NovelReaderTextRange(
            hits[0].anchor.copyWith(
              textIdentity: '${hits[0].anchor.textIdentity}old',
            ),
            2,
          ),
        ),
        isEmpty,
      );
      expect(
        map.sourceRanges(NovelReaderTextRange(hits[0].anchor, 3)),
        isEmpty,
      );
    },
  );

  test('real origin paths disambiguate repeated and nested semantic text', () {
    final fixture = _Fixture('<div>重<b>重</b><p>重</p></div><p>重</p>');
    final map = fixture.bind();
    final before = map.anchorAtSourceRune(3, affinity: _upstream)!;
    final after = map.anchorAtSourceRune(3, affinity: _downstream)!;
    expect(before.nodeId, 'node-0');
    expect(before.textOffset, 3);
    expect(before.textIdentity, NovelReaderAnchorFormat.textIdentity('重重重'));
    expect(after.nodeId, 'node-1');
    expect(after.textOffset, 0);
    expect(after.textIdentity, NovelReaderAnchorFormat.textIdentity('重'));
    expect(after.formatVersion, NovelReaderAnchorFormat.semanticCodePoints);
    expect(after.isProgressPercentValid, isFalse);
    expect(map.unmappedPaths, isEmpty);
    expect(map.segments, hasLength(4));
    expect(() => map.segments.clear(), throwsUnsupportedError);
    expect(() => map.unmappedPaths.clear(), throwsUnsupportedError);
  });

  test(
    'whitespace and source gaps never clamp to a nearby semantic position',
    () {
      final fixture = _Fixture('<p><b>a</b>   <i>b</i></p>');
      final map = fixture.bind();
      expect(map.anchorAtSourceRune(2, affinity: _downstream), isNull);
      expect(map.anchorAtSourceRune(3, affinity: _upstream), isNull);
      expect(map.anchorAtSourceRune(4, affinity: _downstream)!.textOffset, 1);
      expect(map.anchorAtSourceRune(5, affinity: _upstream)!.textOffset, 2);
      expect(
        () => map.anchorAtSourceRune(-1, affinity: _downstream),
        throwsRangeError,
      );
      expect(
        () => map.anchorAtSourceRune(6, affinity: _downstream),
        throwsRangeError,
      );
    },
  );

  test(
    'inline BR and normalized whitespace map to actual semantic codepoints',
    () {
      final fixture = _Fixture('<p> \tA🙂<br> \t尾 </p>');
      final map = fixture.bind();
      expect(fixture.semantic.blocks.single.novelPlainText, ' A🙂\n 尾 ');
      final content = fixture.content();
      expect(content.projection.text, 'A🙂\n尾');
      final end = map.projectDisplayPosition(
        content: content,
        displayUtf16: content.projection.text.length,
        affinity: _upstream,
      )!;
      expect(end.anchor.textOffset, 6);
      expect(
        end.anchor.textIdentity,
        NovelReaderAnchorFormat.textIdentity(' A🙂\n 尾 '),
      );
      expect(end.isExact, isTrue);
    },
  );

  test('element.text omissions at BR are structurally projected, not counted as text', () {
    final fixture = _Fixture(
      '<p><a href="https://example.org"> a<br><b>b</b> </a>尾</p>',
    );
    final map = fixture.bind();
    expect(fixture.semantic.blocks.single.novelPlainText, 'ab尾');
    expect(map.unmappedPaths, isEmpty);
    expect(map.anchorAtSourceRune(2, affinity: _upstream)!.textOffset, 1);
    expect(map.anchorAtSourceRune(3, affinity: _downstream)!.textOffset, 1);
    expect(map.anchorAtSourceRune(5, affinity: _downstream)!.textOffset, 2);
  });

  test('native-removed fallback inside a link stays unmapped without poisoning other origins', () {
    final fixture = _Fixture(
      '<p><a href="https://example.org">a<script>x</script>b</a>尾</p>',
    );
    final map = fixture.bind();
    expect(fixture.semantic.blocks.single.novelPlainText, 'axb尾');
    expect(map.unmappedPaths, ['0/0']);
    expect(map.anchorAtSourceRune(1, affinity: _downstream), isNull);
    expect(map.anchorAtSourceRune(2, affinity: _downstream)!.textOffset, 3);
  });

  test(
    'protected textless image inside a link does not manufacture source runes',
    () {
      final fixture = _Fixture(
        '<p><a href="https://example.org">a<img src="https://example.org/i.png">b</a></p>',
      );
      final map = fixture.bind();
      expect(map.unmappedPaths, isEmpty);
      expect(map.sourceRuneLength, 2);
      expect(map.anchorAtSourceRune(1, affinity: _downstream)!.textOffset, 1);
    },
  );

  test('display grapheme snaps and hidden-source discontinuities remain approximate', () {
    final fixture = _Fixture('<p>e<span>\u0301🙂</span></p>');
    final map = fixture.bind();
    final content = fixture.content();
    final inside = map.projectDisplayPosition(
      content: content,
      displayUtf16: 1,
      affinity: _downstream,
    )!;
    expect(inside.anchor.textOffset, 2);
    expect(inside.displayUtf16, 2);
    expect(inside.isExact, isFalse);
    final hidden = _Fixture(
      '<p>a<span style="display:none">secret</span>b</p>',
    );
    final hiddenMap = hidden.bind();
    final point = hiddenMap.projectDisplayPosition(
      content: hidden.content(),
      displayUtf16: 1,
      affinity: _downstream,
    )!;
    expect(point.anchor.textOffset, 7);
    expect(point.isExact, isFalse);
  });

  test('identity includes exact markup, actual conversion, owner source and parser revision', () {
    final fixture = _Fixture('<p data-label="a">同文</p>');
    final changed = _Fixture('<p data-label="b">同文</p>');
    expect(
      () => fixture.bind(native: changed.body),
      _failure(NovelReaderNativeAnchorBindingFailure.identity),
    );
    expect(
      () => fixture.bind(episodeId: 'another'),
      _failure(NovelReaderNativeAnchorBindingFailure.identity),
    );
    expect(
      () => fixture.bind(sourceId: 'another'),
      _failure(NovelReaderNativeAnchorBindingFailure.identity),
    );
    expect(
      () => fixture.bind(
        document: _copy(fixture.semantic, conversion: 'toTraditional'),
      ),
      _failure(NovelReaderNativeAnchorBindingFailure.conversion),
    );
    expect(
      () => fixture.bind(document: _copy(fixture.semantic, conversion: null)),
      _failure(NovelReaderNativeAnchorBindingFailure.conversion),
    );
    final future = ForumBodyDocument(
      identity: ForumBodyIdentity(
        sourceId: 'source',
        inputHash: fixture.body.identity.inputHash,
        conversionIdentity: 'none',
        parserRevision: 999,
      ),
      sourceMap: fixture.body.sourceMap,
      nodes: fixture.body.nodes,
      issues: fixture.body.issues,
      parsedNodeCount: fixture.body.parsedNodeCount,
      uniqueStyleCount: fixture.body.uniqueStyleCount,
    );
    expect(
      () => fixture.bind(native: future),
      _failure(NovelReaderNativeAnchorBindingFailure.identity),
    );
    expect(
      () => fixture.bind(
        document: _copy(fixture.semantic, clearProvenance: true),
      ),
      _failure(NovelReaderNativeAnchorBindingFailure.provenance),
    );
  });

  test('same text cannot repair invalid or reordered origin metadata', () {
    final fixture = _Fixture('<p>x<b>x</b></p><p>x</p>');
    final origins = fixture.semantic.sourceProvenance!.origins;
    for (final bad in [
      [origins[1], origins[0], origins[2]],
      [origins[0], origins[2]],
      [origins[0], origins[0], origins[1], origins[2]],
      [
        const NovelReaderTextSourceOrigin(
          path: '99',
          sourceText: 'x',
          text: 'x',
          nodeId: 'node-0',
          semanticCodePointStart: 0,
          policy: NovelReaderSourceTextPolicy.inlineTextNode,
        ),
      ],
    ]) {
      expect(
        () => fixture.bind(document: _copy(fixture.semantic, origins: bad)),
        _failure(NovelReaderNativeAnchorBindingFailure.origin),
      );
    }
  });

  test('projection rejects content from a different exact input', () {
    final fixture = _Fixture('<p>text</p>');
    final map = fixture.bind();
    expect(
      () => map.projectDisplayPosition(
        content: _Fixture('<p>other</p>').content(),
        displayUtf16: 0,
        affinity: _downstream,
      ),
      throwsStateError,
    );
    expect(
      () => map.projectDisplayPosition(
        content: fixture.content(),
        displayUtf16: 99,
        affinity: _downstream,
      ),
      throwsRangeError,
    );
  });

  test('all retained projection inputs have explicit budgets', () {
    final fixture = _Fixture('<p>abc</p>');
    for (final limits in [
      const NovelReaderNativeAnchorBindingLimits(maxSourceBoundaries: 3),
      const NovelReaderNativeAnchorBindingLimits(maxSemanticCodeUnits: 2),
      const NovelReaderNativeAnchorBindingLimits(
        origins: NovelReaderSourceProvenanceLimits(maxEntries: 0),
      ),
      const NovelReaderNativeAnchorBindingLimits(
        origins: NovelReaderSourceProvenanceLimits(maxSourceCodeUnits: 2),
      ),
      const NovelReaderNativeAnchorBindingLimits(
        origins: NovelReaderSourceProvenanceLimits(maxPathCodeUnits: 2),
      ),
    ]) {
      expect(
        () => fixture.bind(limits: limits),
        _failure(NovelReaderNativeAnchorBindingFailure.budget),
      );
    }
    expect(
      fixture
          .bind(
            limits: const NovelReaderNativeAnchorBindingLimits(
              maxSourceBoundaries: 4,
              maxSemanticCodeUnits: 3,
            ),
          )
          .segments,
      hasLength(1),
    );
    expect(
      () => fixture.bind(
        limits: const NovelReaderNativeAnchorBindingLimits(
          maxSourceBoundaries: -1,
        ),
      ),
      throwsArgumentError,
    );
  });
}
