import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_normalization.dart';

NovelReaderDocument _parse(
  String html, {
  bool capture = true,
  NovelReaderSourceProvenanceLimits limits =
      const NovelReaderSourceProvenanceLimits(),
  List<String> fallback = const [],
}) =>
    DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: capture,
      sourceProvenanceLimits: limits,
    ).parse(
      episodeId: 'origin-fixture',
      rawHtml: html,
      fallbackParagraphs: fallback,
    );

void _verifyEmittedOrigins(NovelReaderDocument document) {
  final texts = {
    for (final block in document.blocks) block.anchorId: block.novelPlainText,
  };
  for (final origin in document.sourceProvenance!.origins) {
    final node = texts[origin.nodeId]!.runes.toList();
    final emitted = origin.text.runes.toList();
    expect(
      node.sublist(
        origin.semanticCodePointStart,
        origin.semanticCodePointStart + emitted.length,
      ),
      emitted,
    );
    final normalized = switch (origin.policy) {
      NovelReaderSourceTextPolicy.trimmedTextNode ||
      NovelReaderSourceTextPolicy.trimmedElementText =>
        NovelReaderTextNormalization.project(
          origin.sourceText,
          trim: true,
        ).text,
      NovelReaderSourceTextPolicy.inlineTextNode =>
        NovelReaderTextNormalization.project(origin.sourceText).text,
      NovelReaderSourceTextPolicy.hardBreak => '\n',
    };
    expect(origin.text, normalized);
  }
}

void main() {
  test('origins retain real paths and node-local codepoints without changing semantics', () {
    const html =
        ' <!--kept index--><script>removed</script>'
        '<div>A🙂<b>重</b><p>重</p><br> 尾 </div><p>重</p> ';
    final document = _parse(html);
    final plain = _parse(html, capture: false);
    expect(plain.sourceProvenance, isNull);
    expect(document.rawHtmlHash, plain.rawHtmlHash);
    expect(document.plainText, plain.plainText);
    expect(document.wordCount, plain.wordCount);
    expect(
      document.blocks.map((b) => b.anchorId),
      plain.blocks.map((b) => b.anchorId),
    );
    final origins = document.sourceProvenance!.origins;
    expect(origins.map((o) => o.path), [
      '2/0',
      '2/1/0',
      '2/2/0',
      '2/3',
      '2/4',
      '3/0',
    ]);
    expect(origins.map((o) => o.nodeId), [
      'node-0',
      'node-0',
      'node-0',
      'node-0',
      'node-0',
      'node-1',
    ]);
    expect(origins.map((o) => o.semanticCodePointStart), [0, 2, 3, 4, 5, 0]);
    _verifyEmittedOrigins(document);

    final body = const ForumBodyParser().parse(
      html: html.trim(),
      sourceId: document.episodeId,
      conversionIdentity: document.textConversionIdentity!,
    );
    expect(document.sourceProvenance!.inputHash, body.identity.inputHash);
    for (final origin in origins) {
      final node = body.nodeAtPath(origin.path);
      if (node is ForumBodyText) expect(node.text, origin.sourceText);
    }
    expect(() => origins.clear(), throwsUnsupportedError);
  });

  test('trimmed parse input is exact, not an equal-text document identity', () {
    const html = ' \n<p data-owner="a">正文</p>\n ';
    final first = _parse(html);
    final other = _parse(html.replaceFirst('"a"', '"b"'));
    expect(first.plainText, other.plainText);
    expect(
      first.sourceProvenance!.inputHash,
      sha256.convert(utf8.encode(html.trim())).toString(),
    );
    expect(
      first.sourceProvenance!.inputHash,
      isNot(other.sourceProvenance!.inputHash),
    );
  });

  test('link textContent, BR and skipped content have explicit different policies', () {
    final document = _parse(
      '<span> 顶  层 </span><br><hr>'
      '<blockquote> \t<b>e\u0301🙂</b><a href="https://example.org">  链<br>接  </a>'
      '<script>hidden</script><img src="https://example.org/p.png">\n  尾</blockquote>',
    );
    _verifyEmittedOrigins(document);
    final origins = document.sourceProvenance!.origins;
    expect(origins.first.policy, NovelReaderSourceTextPolicy.trimmedTextNode);
    expect(origins.first.path, '0/0');
    final quote = document.blocks.whereType<RichQuoteBlock>().single;
    final quoteOrigins = origins
        .where((o) => o.nodeId == quote.anchorId)
        .toList();
    expect(quoteOrigins.first.semanticCodePointStart, 0);
    expect(quoteOrigins[1].semanticCodePointStart, 3);
    expect(
      quoteOrigins[1].policy,
      NovelReaderSourceTextPolicy.trimmedElementText,
    );
    expect(quoteOrigins[1].sourceText, '  链接  ');
    expect(origins.any((o) => o.sourceText.contains('hidden')), isFalse);
    // Element.text omits the BR. The future adapter must verify this actual
    // same-path source difference; the sidecar does not assert native coverage.
    expect(quoteOrigins[1].text, '链接');
  });

  test('DOM repair paths agree with the native parser, including comments', () {
    const html = '<p>一<p>二<!--comment--><b>三</b>';
    final document = _parse(html);
    final body = const ForumBodyParser().parse(
      html: html,
      sourceId: document.episodeId,
      conversionIdentity: 'none',
    );
    for (final origin in document.sourceProvenance!.origins) {
      expect(
        (body.nodeAtPath(origin.path) as ForumBodyText).text,
        origin.sourceText,
      );
    }
    _verifyEmittedOrigins(document);
  });

  test('empty or nonrendering HTML fallback cannot claim DOM provenance', () {
    for (final html in ['', '<script>ignored</script>']) {
      final document = _parse(html, fallback: ['fallback']);
      expect(document.plainText, 'fallback');
      expect(document.sourceProvenance, isNull);
      expect(document.storedParagraphSource, isNotNull);
    }
  });

  test('resource-only inputs do not manufacture textual origin coverage', () {
    final document = _parse('<img src="https://example.org/a.png"><br><hr>');
    expect(document.blocks, hasLength(3));
    expect(document.sourceProvenance!.origins, isEmpty);
  });

  test('a cap failure discards the entire sidecar and preserves every semantic block', () {
    const html = '<div><b>a</b><i>🙂</i><span>c</span></div><p>tail</p>';
    final plain = _parse(html, capture: false);
    for (final limits in [
      const NovelReaderSourceProvenanceLimits(maxEntries: 2),
      const NovelReaderSourceProvenanceLimits(maxSourceCodeUnits: 2),
      const NovelReaderSourceProvenanceLimits(maxEntries: 0),
      const NovelReaderSourceProvenanceLimits(maxPathCodeUnits: 3),
    ]) {
      final document = _parse(html, limits: limits);
      expect(document.sourceProvenance, isNull);
      expect(document.plainText, plain.plainText);
      expect(
        document.blocks.map((b) => b.anchorId),
        plain.blocks.map((b) => b.anchorId),
      );
    }
    final exact = _parse(
      html,
      limits: const NovelReaderSourceProvenanceLimits(
        maxEntries: 4,
        maxSourceCodeUnits: 8,
      ),
    );
    expect(exact.sourceProvenance!.origins, hasLength(4));
    _verifyEmittedOrigins(exact);
  });

  test('invalid capture budgets are rejected before recording', () {
    expect(
      () => _parse(
        '<p>x</p>',
        limits: const NovelReaderSourceProvenanceLimits(maxEntries: -1),
      ),
      throwsArgumentError,
    );
  });
}
