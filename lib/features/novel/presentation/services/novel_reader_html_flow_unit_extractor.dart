import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_normalization.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_dom_source_text.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

abstract interface class NovelReaderHtmlFlowUnitExtractor {
  List<NovelReaderFlowUnit> extract({
    required String episodeId,
    required ForumHtmlPreparedRenderDocument renderDocument,
    NovelReaderDocument? semanticDocument,
  });
}

/// Extracts stable, top-level flow units from the already prepared HTML.
///
/// This is intentionally a structural pass. It does not calculate page
/// heights and it does not reinterpret raw chapter HTML. Page breaking belongs
/// to the next phase and can consume these units without duplicating the
/// current HTML preparation and image pipeline.
final class DefaultNovelReaderHtmlFlowUnitExtractor
    implements NovelReaderHtmlFlowUnitExtractor {
  const DefaultNovelReaderHtmlFlowUnitExtractor();

  static const Set<String> _inlineTags = <String>{
    'a',
    'abbr',
    'b',
    'em',
    'font',
    'i',
    'label',
    'mark',
    'small',
    'span',
    'strong',
    'sub',
    'sup',
    'u',
  };

  static const Set<String> _atomicTags = <String>{
    'audio',
    'canvas',
    'details',
    'embed',
    'fieldset',
    'iframe',
    'object',
    'table',
    'video',
  };

  @override
  List<NovelReaderFlowUnit> extract({
    required String episodeId,
    required ForumHtmlPreparedRenderDocument renderDocument,
    NovelReaderDocument? semanticDocument,
  }) {
    final fragment = html_parser.parseFragment(renderDocument.preparedHtml);
    _removeNonRenderingNodes(fragment);
    final occurrences = <String, int>{};
    final units = <NovelReaderFlowUnit>[];
    final displayIdentity = NovelReaderAnchorFormat.textIdentity(
      renderDocument.preparedHtml,
    );
    final semanticNodesByText = <String, List<String>>{};
    if (semanticDocument != null) {
      for (final block in semanticDocument.blocks) {
        (semanticNodesByText[block.novelPlainText] ??= <String>[]).add(
          block.anchorId,
        );
      }
    }

    for (final node in fragment.nodes) {
      // Filtering is complete; subsequent unit decisions only read this DOM.
      final facts = _FlowUnitFacts(node, renderDocument);
      if (!_isMeaningful(facts)) {
        continue;
      }
      final semanticMatch = _matchSemanticAnchor(
        facts,
        semanticDocument,
        semanticNodesByText,
      );
      final descriptor = _describeNode(
        facts,
        episodeId: episodeId,
        occurrences: occurrences,
        semanticProjection: semanticMatch,
        displayIdentity: displayIdentity,
      );
      if (descriptor != null) {
        units.add(descriptor);
      }
    }

    if (units.isNotEmpty) {
      return List<NovelReaderFlowUnit>.unmodifiable(units);
    }

    // The page breaker must receive one deterministic empty input instead of
    // manufacturing a second empty page for every rebuild.
    final anchor = NovelReaderTextAnchor(episodeId: episodeId);
    return <NovelReaderFlowUnit>[
      NovelReaderFlowUnit(
        unitId: '$episodeId:empty',
        html: '',
        startAnchor: anchor,
        endAnchor: anchor,
        breakability: NovelReaderFlowUnitBreakability.atomicWidget,
        imageIndices: const <int>[],
      ),
    ];
  }

  void _removeNonRenderingNodes(html_dom.Node parent) {
    // The HTML renderer hides style/script and ignores comments. Their source
    // text must not create pages or contribute to readable anchor offsets.
    // Only this parsed layout projection is changed; prepared HTML stays intact.
    for (final node in parent.nodes.toList(growable: false)) {
      if (node is html_dom.Comment ||
          (node is html_dom.Element &&
              (node.localName == 'style' || node.localName == 'script'))) {
        node.remove();
      } else if (node is html_dom.Element) {
        _removeNonRenderingNodes(node);
      }
    }
  }

  NovelReaderFlowUnit? _describeNode(
    _FlowUnitFacts facts, {
    required String episodeId,
    required Map<String, int> occurrences,
    required NovelReaderSourceAnchorProjection? semanticProjection,
    required String displayIdentity,
  }) {
    final node = facts.node;
    final html = _serializeNode(node);
    if (html.trim().isEmpty) {
      return null;
    }
    final element = node is html_dom.Element ? node : null;
    final identity = _identityFor(facts);
    final occurrence = occurrences.update(
      identity,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final anchorId = _anchorId(identity, occurrence);
    final isSpacer = element?.localName == 'br';
    // Ambiguous/multi-block/converted text has its own exact layout identity.
    // It can restore the same display projection, but cannot impersonate node-N.
    final projection =
        semanticProjection ??
        NovelReaderSourceAnchorProjection(
          baseAnchor: NovelReaderTextAnchor(
            episodeId: episodeId,
            nodeId: anchorId,
            formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
            textIdentity: NovelReaderAnchorFormat.layoutTextIdentity(
              isSpacer ? '' : facts.sourceText,
              displayIdentity,
            ),
            isProgressPercentValid: false,
          ),
          semanticOffsetsBySourceRuneBoundary: List<int>.generate(
            facts.sourceRuneLength + 1,
            (index) => isSpacer ? 0 : index,
          ),
        );

    return NovelReaderFlowUnit(
      unitId: '$episodeId:$anchorId',
      html: html,
      startAnchor: projection.anchorAtSourceRune(0),
      endAnchor: projection.anchorAtSourceRune(projection.sourceRuneLength),
      breakability: _breakability(element, facts),
      imageIndices: facts.readableImageIndices,
      sourceAnchorProjection: projection,
    );
  }

  NovelReaderSourceAnchorProjection? _matchSemanticAnchor(
    _FlowUnitFacts facts,
    NovelReaderDocument? semanticDocument,
    Map<String, List<String>> semanticNodesByText,
  ) {
    if (semanticDocument == null) {
      return null;
    }
    if (!facts.hasSourceText) {
      return null;
    }
    for (final candidate in _candidateProjections(facts)) {
      if (candidate.text.trim().isEmpty) continue;
      NovelReaderSourceAnchorProjection? match;
      final exactNodes = semanticNodesByText[candidate.text];
      if (exactNodes != null) {
        if (exactNodes.length != 1) return null;
        if (semanticNodesByText.keys.any(
          (text) => text != candidate.text && text.contains(candidate.text),
        )) {
          return null;
        }
        return _semanticProjection(
          semanticDocument.episodeId,
          exactNodes.single,
          candidate.text,
          0,
          candidate.offsets,
        );
      }
      for (final block in semanticDocument.blocks) {
        final text = block.novelPlainText;
        var cursor = 0;
        while (cursor <= text.length) {
          final offset = text.indexOf(candidate.text, cursor);
          if (offset < 0) break;
          if (match != null) return null;
          final base = text.substring(0, offset).runes.length;
          match = _semanticProjection(
            semanticDocument.episodeId,
            block.anchorId,
            text,
            base,
            candidate.offsets,
          );
          cursor = offset + 1;
        }
      }
      if (match != null) return match;
    }
    return null;
  }

  Iterable<_SourceTextProjection> _candidateProjections(
    _FlowUnitFacts facts,
  ) sync* {
    final source = facts.sourceText;
    yield _SourceTextProjection(
      source,
      List<int>.generate(facts.sourceRuneLength + 1, (index) => index),
    );
    yield _projectInlineSource(
      facts.node,
      sourceText: source,
      sourceRuneLength: facts.sourceRuneLength,
    );
    final plain = NovelReaderTextNormalization.project(source, trim: true);
    yield _SourceTextProjection(plain.text, plain.offsets);
  }

  NovelReaderSourceAnchorProjection _semanticProjection(
    String episodeId,
    String nodeId,
    String text,
    int base,
    List<int> offsets,
  ) => NovelReaderSourceAnchorProjection(
    baseAnchor: NovelReaderTextAnchor(
      episodeId: episodeId,
      nodeId: nodeId,
      formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
      textIdentity: NovelReaderAnchorFormat.textIdentity(text),
      isProgressPercentValid: false,
    ),
    semanticOffsetsBySourceRuneBoundary: offsets
        .map((value) => base + value)
        .toList(growable: false),
  );

  _SourceTextProjection _projectInlineSource(
    html_dom.Node node, {
    String? sourceText,
    int? sourceRuneLength,
  }) {
    if (node is html_dom.Text ||
        (node is html_dom.Element && node.localName == 'a')) {
      final source = sourceText ?? NovelReaderDomSourceText.read(node);
      final projected = NovelReaderTextNormalization.project(
        source,
        trim: node is html_dom.Element,
      );
      if (projected.text.trim().isEmpty) {
        return _SourceTextProjection(
          '',
          List<int>.filled((sourceRuneLength ?? source.runes.length) + 1, 0),
        );
      }
      return _SourceTextProjection(projected.text, projected.offsets);
    }
    if (node is html_dom.Element && node.localName == 'br') {
      return const _SourceTextProjection('\n', <int>[0, 1]);
    }
    final text = StringBuffer();
    final offsets = <int>[0];
    var semanticOffset = 0;
    for (final child in node.nodes) {
      final projected = _projectInlineSource(child);
      text.write(projected.text);
      offsets.addAll(
        projected.offsets.skip(1).map((value) => semanticOffset + value),
      );
      semanticOffset += projected.text.runes.length;
    }
    return _SourceTextProjection(text.toString(), offsets);
  }

  bool _isMeaningful(_FlowUnitFacts facts) {
    final node = facts.node;
    if (node is html_dom.Text) {
      return node.data.trim().isNotEmpty;
    }
    if (node is html_dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'br' || tag == 'hr' || tag == 'img') {
        return true;
      }
      return facts.hasDomText ||
          facts.hasAnyImage ||
          (tag != null && _atomicTags.contains(tag));
    }
    return facts.hasDomText;
  }

  NovelReaderFlowUnitBreakability _breakability(
    html_dom.Element? element,
    _FlowUnitFacts facts,
  ) {
    final tag = element?.localName?.toLowerCase();
    if (tag != null && _atomicTags.contains(tag)) {
      return NovelReaderFlowUnitBreakability.atomicWidget;
    }
    if (tag == 'img' ||
        (element != null && facts.hasAnyImage && !facts.hasSourceText)) {
      return NovelReaderFlowUnitBreakability.blockImage;
    }
    if (tag != null && _inlineTags.contains(tag)) {
      return NovelReaderFlowUnitBreakability.inlineText;
    }
    if (facts.hasSourceText) {
      return NovelReaderFlowUnitBreakability.text;
    }
    return NovelReaderFlowUnitBreakability.atomicWidget;
  }

  String _identityFor(_FlowUnitFacts facts) {
    final node = facts.node;
    if (node is html_dom.Element) {
      final explicitId = node.id.trim();
      if (explicitId.isNotEmpty) {
        return 'id:$explicitId';
      }
      final attributes = <String>[];
      for (final name in <String>[
        'href',
        'src',
        'data-y300-readable-image-index',
      ]) {
        final value = node.attributes[name]?.trim();
        if (value != null && value.isNotEmpty) {
          attributes.add('$name=$value');
        }
      }
      return 'element:${node.localName}:${_stableHash('${facts.domText}|${attributes.join('|')}')}';
    }
    return 'text:${_stableHash(facts.domText)}';
  }

  String _anchorId(String identity, int occurrence) {
    final normalizedIdentity = identity.replaceAll(':', '-');
    return 'novel-html-$normalizedIdentity-$occurrence';
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
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

// These lazy summaries belong to one fixed layout DOM, never a chapter
// cache. Identity text, slicing text and image presence have distinct semantics.
final class _FlowUnitFacts {
  _FlowUnitFacts(this.node, this.renderDocument);

  final html_dom.Node node;
  final ForumHtmlPreparedRenderDocument renderDocument;
  late final String domText = node.text ?? '';
  late final bool hasDomText = domText.trim().isNotEmpty;
  late final String sourceText = NovelReaderDomSourceText.read(node);
  late final bool hasSourceText = sourceText.trim().isNotEmpty;
  late final int sourceRuneLength = sourceText.runes.length;
  late final List<html_dom.Element> imageCandidates = _findImages();
  late final bool hasAnyImage = imageCandidates.isNotEmpty;
  late final List<int> readableImageIndices = _readableIndices();

  List<html_dom.Element> _findImages() {
    final current = node;
    if (current is! html_dom.Element) return const <html_dom.Element>[];
    return <html_dom.Element>[
      if (current.localName == 'img') current,
      ...current.querySelectorAll('img'),
    ];
  }

  List<int> _readableIndices() {
    final indices = <int>{};
    for (final image in imageCandidates) {
      final index = int.tryParse(
        image.attributes[forumHtmlReadableImageIndexAttribute] ?? '',
      );
      if (index != null && renderDocument.sequence.entryAt(index) != null) {
        indices.add(index);
      }
    }
    return List<int>.unmodifiable(indices.toList()..sort());
  }
}

final class _SourceTextProjection {
  const _SourceTextProjection(this.text, this.offsets);
  final String text;
  final List<int> offsets;
}
