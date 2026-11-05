import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/novel/domain/services/novel_reader_text_normalization.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

abstract class NovelReaderDocumentParser {
  NovelReaderDocument parse({
    required String episodeId,
    required String rawHtml,
    required List<String> fallbackParagraphs,
  });
}

/// Parses Discuz novel-chapter HTML into the shared [RichDocument] block tree
/// wrapped with novel metadata. Mirrors the thread body parser's image handling
/// (aid + original dimensions are preserved) while keeping the novel-specific
/// block grouping the paginator/search/progress layers rely on.
class DiscuzNovelReaderDocumentParser implements NovelReaderDocumentParser {
  const DiscuzNovelReaderDocumentParser({
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
    this.captureSourceProvenance = false,
    this.sourceProvenanceLimits = const NovelReaderSourceProvenanceLimits(),
  }) : _domExtractor = domExtractor;

  final ForumPostDomExtractor _domExtractor;
  final bool captureSourceProvenance;
  final NovelReaderSourceProvenanceLimits sourceProvenanceLimits;

  static const Set<String> _skipTags = <String>{
    'script',
    'style',
    'form',
    'input',
    'button',
    'select',
    'textarea',
    'iframe',
    'noscript',
  };

  static const Set<String> _blockTags = <String>{
    'p',
    'div',
    'section',
    'article',
    'li',
  };

  static const Set<String> _headingTags = <String>{
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };

  @override
  NovelReaderDocument parse({
    required String episodeId,
    required String rawHtml,
    required List<String> fallbackParagraphs,
  }) {
    final normalizedHtml = rawHtml.trim();
    if (normalizedHtml.isEmpty) {
      return _fallbackDocument(episodeId, rawHtml, fallbackParagraphs);
    }

    final fragment = html_parser.parseFragment(normalizedHtml);
    final origins = captureSourceProvenance
        ? _SourceOriginRecorder(sourceProvenanceLimits)
        : null;
    final builder = _BlockBuilder(this, origins);
    for (var i = 0; i < fragment.nodes.length; i++) {
      builder.appendNode(
        fragment.nodes[i],
        const _InlineStyle(),
        origins?.isRecording == true ? '$i' : null,
      );
    }

    if (builder.blocks.isEmpty) {
      return _fallbackDocument(
        episodeId,
        rawHtml,
        fallbackParagraphs,
        emptyProvenance: origins?.finish(normalizedHtml),
      );
    }
    return _documentFromBlocks(
      episodeId,
      rawHtml,
      builder.blocks,
      sourceProvenance: origins?.finish(normalizedHtml),
    );
  }

  NovelReaderDocument _fallbackDocument(
    String episodeId,
    String rawHtml,
    List<String> fallbackParagraphs, {
    NovelReaderSourceProvenance? emptyProvenance,
  }) {
    final blocks = <RichBlock>[];
    var index = 0;
    for (final paragraph in fallbackParagraphs) {
      final text = _normalizeText(paragraph);
      if (text.isEmpty) {
        continue;
      }
      blocks.add(
        RichTextBlock(
          anchorId: _nodeId(index),
          runs: <RichRun>[RichRun(text: text)],
        ),
      );
      index += 1;
    }
    // Resource-only HTML can prove its parse input without inventing a block.
    // Any fallback text still has no DOM provenance.
    return _documentFromBlocks(
      episodeId,
      rawHtml,
      blocks,
      sourceProvenance: blocks.isEmpty ? emptyProvenance : null,
    );
  }

  NovelReaderDocument _documentFromBlocks(
    String episodeId,
    String rawHtml,
    List<RichBlock> blocks, {
    NovelReaderSourceProvenance? sourceProvenance,
  }) {
    final plainText = blocks
        .map((block) => block.novelPlainText.trim())
        .where((text) => text.isNotEmpty)
        .join('\n')
        .trim();
    return NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: _stableHash(rawHtml),
      body: RichDocument(blocks: List<RichBlock>.unmodifiable(blocks)),
      plainText: plainText,
      wordCount: plainText.runes
          .where((rune) => !_isWhitespaceRune(rune))
          .length,
      textConversionIdentity: 'none',
      sourceProvenance: sourceProvenance,
    );
  }

  RichImageBlock? _imageBlock(html_dom.Element element, int index, String id) {
    final raw = DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      // Match the renderer/preparation original-source policy; src may be a
      // thumbnail while zoomfile/file names the actual protected attachment.
      domAttributes: const [
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
        'data',
      ],
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final normalized = _domExtractor.normalizeImageSource(raw);
    if (normalized == null ||
        !DefaultForumImageSourcePipeline.isHttpImageUrl(normalized) ||
        DefaultForumImageSourcePipeline.isForumChromeImage(normalized)) {
      return null;
    }
    final alt = _normalizeText(element.attributes['alt'] ?? '');
    return RichImageBlock(
      anchorId: id,
      url: normalized,
      rawUrl: raw,
      index: index,
      aid: _nonEmpty(element.attributes['aid']),
      altText: alt.isEmpty ? null : alt,
      originalWidth: _parseDimension(element.attributes['width']),
      originalHeight: _parseDimension(element.attributes['height']),
    );
  }

  _LinkInfo? _linkFromElement(html_dom.Element element) {
    final text = _normalizeText(element.text);
    final rawHref = (element.attributes['href'] ?? '').trim();
    if (text.isEmpty || rawHref.isEmpty) {
      return null;
    }
    final normalized = _domExtractor
        .extractAnchors(element.outerHtml)
        .firstOrNull;
    if (normalized == null) {
      return null;
    }
    final uri = Uri.tryParse(normalized.normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return _LinkInfo(
      url: normalized.normalizedUrl,
      text: text,
      tid: normalized.tid,
    );
  }

  _InlineStyle _styleForElement(
    html_dom.Element element,
    _InlineStyle inherited,
  ) {
    final tag = element.localName?.toLowerCase();
    final style = element.attributes['style'] ?? '';
    final color = RegExp(
      r'color\s*:\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style)?.group(1)?.trim();
    final fontColor = element.attributes['color']?.trim();
    return inherited.merge(
      bold: tag == 'strong' || tag == 'b' ? true : null,
      italic: tag == 'em' || tag == 'i' ? true : null,
      underline: tag == 'u' ? true : null,
      color: color?.isNotEmpty == true
          ? color
          : (fontColor?.isNotEmpty == true ? fontColor : null),
    );
  }

  String _normalizeText(String text) {
    return NovelReaderTextNormalization.normalize(text, trim: true);
  }

  String _normalizeInlineText(String text) {
    return NovelReaderTextNormalization.normalize(text);
  }

  bool _isWhitespaceRune(int rune) {
    return String.fromCharCode(rune).trim().isEmpty;
  }

  String _nodeId(int index) => 'node-$index';

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  double? _parseDimension(String? raw) {
    final value = double.tryParse(raw?.trim() ?? '');
    return value == null || value <= 0 ? null : value;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// Accumulates blocks while walking the DOM. Block-level elements flush their
/// inline runs into a [RichTextBlock]; images, dividers and spacers become
/// their own blocks. Ids stay `node-N` so persisted progress anchors resolve.
class _BlockBuilder {
  _BlockBuilder(this._parser, this._origins);

  final DiscuzNovelReaderDocumentParser _parser;
  final _SourceOriginRecorder? _origins;
  final List<RichBlock> blocks = <RichBlock>[];
  var _nextId = 0;
  var _imageIndex = 0;

  String _takeId() => _parser._nodeId(_nextId++);

  void appendNode(html_dom.Node node, _InlineStyle style, String? path) {
    if (node is html_dom.Text) {
      final text = _parser._normalizeText(node.text);
      if (text.isNotEmpty) {
        _emitText(
          <RichRun>[style.run(text)],
          path,
          node.text,
          NovelReaderSourceTextPolicy.trimmedTextNode,
        );
      }
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }

    final tag = node.localName?.toLowerCase() ?? '';
    if (DiscuzNovelReaderDocumentParser._skipTags.contains(tag)) {
      return;
    }
    if (tag == 'br') {
      blocks.add(RichSpacerBlock(anchorId: _takeId()));
      return;
    }
    if (tag == 'hr') {
      blocks.add(RichDividerBlock(anchorId: _takeId()));
      return;
    }
    if (tag == 'img') {
      _emitImage(node, path);
      return;
    }
    if (tag == 'a') {
      final link = _parser._linkFromElement(node);
      if (link != null) {
        _emitText(
          <RichRun>[style.run(link.text, linkUrl: link.url, linkTid: link.tid)],
          path,
          path == null ? '' : node.text,
          NovelReaderSourceTextPolicy.trimmedElementText,
        );
        _emitLinkedImages(node, path);
        return;
      }
      final text = _parser._normalizeText(node.text);
      if (text.isNotEmpty) {
        _emitText(
          <RichRun>[style.run(text)],
          path,
          path == null ? '' : node.text,
          NovelReaderSourceTextPolicy.trimmedElementText,
        );
      }
      _emitLinkedImages(node, path);
      return;
    }

    final nextStyle = _parser._styleForElement(node, style);
    final isQuote = tag == 'blockquote' || node.classes.contains('quote');
    final isHeading = DiscuzNovelReaderDocumentParser._headingTags.contains(
      tag,
    );
    final isBlock = DiscuzNovelReaderDocumentParser._blockTags.contains(tag);
    if (isQuote || isHeading || isBlock) {
      _emitStructured(
        node,
        path: path,
        style: nextStyle,
        kind: isQuote
            ? _StructuredKind.quote
            : isHeading
            ? _StructuredKind.heading
            : _StructuredKind.paragraph,
      );
      return;
    }

    for (var i = 0; i < node.nodes.length; i++) {
      appendNode(node.nodes[i], nextStyle, _childSourcePath(_origins, path, i));
    }
  }

  void _emitStructured(
    html_dom.Element element, {
    required String? path,
    required _InlineStyle style,
    required _StructuredKind kind,
  }) {
    final collector = _InlineCollector(
      _parser,
      _origins,
      _origins?.isRecording == true ? _parser._nodeId(_nextId) : '',
    );
    for (var i = 0; i < element.nodes.length; i++) {
      collector.visit(
        element.nodes[i],
        style,
        _childSourcePath(_origins, path, i),
      );
    }
    final runs = collector.takeRuns();
    final imageElements = collector.imageElements;

    if (runs.isEmpty && imageElements.isEmpty) {
      return;
    }

    if (runs.isNotEmpty) {
      final id = _takeId();
      if (kind == _StructuredKind.quote) {
        blocks.add(
          RichQuoteBlock(
            anchorId: id,
            blocks: <RichBlock>[RichTextBlock(anchorId: id, runs: runs)],
          ),
        );
      } else {
        blocks.add(
          RichTextBlock(
            anchorId: id,
            runs: runs,
            headingLevel: kind == _StructuredKind.heading ? 1 : 0,
          ),
        );
      }
    }
    for (final image in imageElements) {
      _emitImage(image.element, image.path);
    }
  }

  void _emitText(
    List<RichRun> runs,
    String? path,
    String sourceText,
    NovelReaderSourceTextPolicy policy,
  ) {
    final merged = _mergeRuns(runs);
    if (merged.isEmpty) {
      return;
    }
    final id = _takeId();
    blocks.add(RichTextBlock(anchorId: id, runs: merged));
    if (path != null) {
      _origins?.record(
        path: path,
        sourceText: sourceText,
        run: merged.single,
        nodeId: id,
        semanticStart: 0,
        policy: policy,
      );
    }
  }

  void _emitLinkedImages(html_dom.Element element, String? path) {
    for (final image in _imageSources(element, path, _origins)) {
      _emitImage(image.element, image.path);
    }
  }

  void _emitImage(html_dom.Element element, String? path) {
    final image = _parser._imageBlock(
      element,
      _imageIndex,
      _parser._nodeId(_nextId),
    );
    if (image == null) {
      return;
    }
    _nextId += 1;
    _imageIndex += 1;
    blocks.add(image);
    if (path != null) {
      _origins?.recordImage(
        path: path,
        nodeId: image.anchorId,
        rawSource: image.rawUrl,
      );
    }
  }

  List<RichRun> _mergeRuns(List<RichRun> runs) {
    final cleaned = runs
        .where((run) => run.text.trim().isNotEmpty || run.text == '\n')
        .toList(growable: false);
    return cleaned;
  }
}

/// Collects inline runs (and any block images) inside a structured element.
class _InlineCollector {
  _InlineCollector(this._parser, this._origins, this._nodeId);

  final DiscuzNovelReaderDocumentParser _parser;
  final _SourceOriginRecorder? _origins;
  final String _nodeId;
  int _semanticStart = 0;
  final List<RichRun> _runs = <RichRun>[];
  final imageElements = <({html_dom.Element element, String? path})>[];

  void visit(html_dom.Node node, _InlineStyle style, String? path) {
    if (node is html_dom.Text) {
      final text = _parser._normalizeInlineText(node.text);
      if (text.trim().isNotEmpty) {
        _append(
          style.run(text),
          path,
          node.text,
          NovelReaderSourceTextPolicy.inlineTextNode,
        );
      }
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }
    final tag = node.localName?.toLowerCase() ?? '';
    if (DiscuzNovelReaderDocumentParser._skipTags.contains(tag)) {
      return;
    }
    if (tag == 'br') {
      _append(
        const RichRun(text: '\n'),
        path,
        '\n',
        NovelReaderSourceTextPolicy.hardBreak,
      );
      return;
    }
    if (tag == 'img') {
      imageElements.add((element: node, path: path));
      return;
    }
    if (tag == 'a') {
      imageElements.addAll(_imageSources(node, path, _origins));
      final link = _parser._linkFromElement(node);
      if (link != null) {
        _append(
          style.run(link.text, linkUrl: link.url, linkTid: link.tid),
          path,
          path == null ? '' : node.text,
          NovelReaderSourceTextPolicy.trimmedElementText,
        );
        return;
      }
      final text = _parser._normalizeText(node.text);
      if (text.isNotEmpty) {
        _append(
          style.run(text),
          path,
          path == null ? '' : node.text,
          NovelReaderSourceTextPolicy.trimmedElementText,
        );
      }
      return;
    }

    final nextStyle = _parser._styleForElement(node, style);
    for (var i = 0; i < node.nodes.length; i++) {
      visit(node.nodes[i], nextStyle, _childSourcePath(_origins, path, i));
    }
  }

  void _append(
    RichRun run,
    String? path,
    String sourceText,
    NovelReaderSourceTextPolicy policy,
  ) {
    _runs.add(run);
    if (path != null && _origins?.isRecording == true) {
      _origins!.record(
        path: path,
        sourceText: sourceText,
        run: run,
        nodeId: _nodeId,
        semanticStart: _semanticStart,
        policy: policy,
      );
      if (_origins.isRecording) {
        _semanticStart += run.text.runes.length;
      }
    }
  }

  List<RichRun> takeRuns() {
    final normalized = _normalizeText(_runs.map((run) => run.text).join());
    if (normalized.isEmpty && !_runs.any((run) => run.text == '\n')) {
      _runs.clear();
      return const <RichRun>[];
    }
    final result = _runs
        .where((run) => run.text.trim().isNotEmpty || run.text == '\n')
        .toList(growable: false);
    _runs.clear();
    return result;
  }

  String _normalizeText(String text) {
    return text
        .replaceAll(' ', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .trim();
  }
}

enum _StructuredKind { paragraph, heading, quote }

Iterable<({html_dom.Element element, String? path})> _imageSources(
  html_dom.Element element,
  String? path,
  _SourceOriginRecorder? recorder,
) sync* {
  final tag = element.localName?.toLowerCase() ?? '';
  if (DiscuzNovelReaderDocumentParser._skipTags.contains(tag)) return;
  if (tag == 'img') {
    yield (element: element, path: path);
    return;
  }
  for (var i = 0; i < element.nodes.length; i++) {
    final child = element.nodes[i];
    if (child is html_dom.Element) {
      yield* _imageSources(
        child,
        _childSourcePath(recorder, path, i),
        recorder,
      );
    }
  }
}

String? _childSourcePath(
  _SourceOriginRecorder? recorder,
  String? path,
  int i,
) => path != null && recorder?.isRecording == true ? '$path/$i' : null;

/// Source capture is opt-in and fails closed as a whole, without affecting the
/// historical semantic parse. Even one huge structured block cannot accumulate
/// unbounded pending origins while waiting for its semantic node to be emitted.
final class _SourceOriginRecorder {
  _SourceOriginRecorder(this.limits) {
    if (limits.maxEntries < 0 ||
        limits.maxSourceCodeUnits < 0 ||
        limits.maxPathCodeUnits < 0) {
      throw ArgumentError('Invalid semantic source provenance limits');
    }
  }
  final NovelReaderSourceProvenanceLimits limits;
  final _origins = <NovelReaderTextSourceOrigin>[];
  final _images = <NovelReaderImageSourceOrigin>[];
  int _sourceCodeUnits = 0;
  int _pathCodeUnits = 0;
  bool isRecording = true;

  bool _admit(String path, String source) {
    if (!isRecording) return false;
    if (_origins.length + _images.length >= limits.maxEntries ||
        source.length > limits.maxSourceCodeUnits - _sourceCodeUnits ||
        path.length > limits.maxPathCodeUnits - _pathCodeUnits) {
      isRecording = false;
      _origins.clear();
      _images.clear();
      _sourceCodeUnits = _pathCodeUnits = 0;
      return false;
    }
    _sourceCodeUnits += source.length;
    _pathCodeUnits += path.length;
    return true;
  }

  void recordImage({
    required String path,
    required String nodeId,
    required String rawSource,
  }) {
    if (_admit(path, rawSource)) {
      _images.add(
        NovelReaderImageSourceOrigin(
          path: path,
          nodeId: nodeId,
          rawSource: rawSource,
        ),
      );
    }
  }

  void record({
    required String path,
    required String sourceText,
    required RichRun run,
    required String nodeId,
    required int semanticStart,
    required NovelReaderSourceTextPolicy policy,
  }) {
    if (!_admit(path, sourceText)) return;
    _origins.add(
      NovelReaderTextSourceOrigin(
        path: path,
        sourceText: sourceText,
        text: run.text,
        nodeId: nodeId,
        semanticCodePointStart: semanticStart,
        policy: policy,
      ),
    );
  }

  NovelReaderSourceProvenance? finish(String input) => isRecording
      ? NovelReaderSourceProvenance(
          inputHash: sha256.convert(utf8.encode(input)).toString(),
          origins: _origins,
          images: _images,
        )
      : null;
}

class _LinkInfo {
  const _LinkInfo({required this.url, required this.text, this.tid});

  final String url;
  final String text;
  final String? tid;
}

/// Inline formatting carried down the DOM, projected onto [RichRun] fields.
class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final String? color;

  _InlineStyle merge({
    bool? bold,
    bool? italic,
    bool? underline,
    String? color,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      color: color ?? this.color,
    );
  }

  /// Builds a run carrying this style's formatting.
  RichRun run(String text, {String? linkUrl, String? linkTid}) {
    return RichRun(
      text: text,
      linkUrl: linkUrl,
      linkTid: linkTid,
      isBold: bold,
      isItalic: italic,
      isUnderline: underline,
      color: color,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
