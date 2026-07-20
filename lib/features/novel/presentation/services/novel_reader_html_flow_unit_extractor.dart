import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';

abstract interface class NovelReaderHtmlFlowUnitExtractor {
  List<NovelReaderFlowUnit> extract({
    required String episodeId,
    required ForumHtmlPreparedRenderDocument renderDocument,
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
  }) {
    final fragment = html_parser.parseFragment(renderDocument.preparedHtml);
    final occurrences = <String, int>{};
    final units = <NovelReaderFlowUnit>[];

    for (final node in fragment.nodes) {
      if (!_isMeaningful(node)) {
        continue;
      }
      final descriptor = _describeNode(
        node,
        episodeId: episodeId,
        occurrences: occurrences,
        renderDocument: renderDocument,
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

  NovelReaderFlowUnit? _describeNode(
    html_dom.Node node, {
    required String episodeId,
    required Map<String, int> occurrences,
    required ForumHtmlPreparedRenderDocument renderDocument,
  }) {
    final html = _serializeNode(node);
    if (html.trim().isEmpty) {
      return null;
    }
    final element = node is html_dom.Element ? node : null;
    final identity = _identityFor(node);
    final occurrence = occurrences.update(
      identity,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final anchorId = _anchorId(identity, occurrence);
    final textLength = _readableText(node).runes.length;
    final startAnchor = NovelReaderTextAnchor(
      episodeId: episodeId,
      nodeId: anchorId,
      textOffset: 0,
    );
    final endAnchor = NovelReaderTextAnchor(
      episodeId: episodeId,
      nodeId: anchorId,
      textOffset: textLength,
    );

    return NovelReaderFlowUnit(
      unitId: '$episodeId:$anchorId',
      html: html,
      startAnchor: startAnchor,
      endAnchor: endAnchor,
      breakability: _breakability(element, node),
      imageIndices: _imageIndices(node, renderDocument),
    );
  }

  bool _isMeaningful(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.data.trim().isNotEmpty;
    }
    if (node is html_dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'br' || tag == 'hr' || tag == 'img') {
        return true;
      }
      return node.text.trim().isNotEmpty ||
          node.querySelector('img') != null ||
          (tag != null && _atomicTags.contains(tag));
    }
    return node.text?.trim().isNotEmpty == true;
  }

  NovelReaderFlowUnitBreakability _breakability(
    html_dom.Element? element,
    html_dom.Node node,
  ) {
    final tag = element?.localName?.toLowerCase();
    if (tag != null && _atomicTags.contains(tag)) {
      return NovelReaderFlowUnitBreakability.atomicWidget;
    }
    if (tag == 'img' ||
        (element != null &&
            element.querySelector('img') != null &&
            _readableText(node).trim().isEmpty)) {
      return NovelReaderFlowUnitBreakability.blockImage;
    }
    if (tag != null && _inlineTags.contains(tag)) {
      return NovelReaderFlowUnitBreakability.inlineText;
    }
    if (_readableText(node).trim().isNotEmpty) {
      return NovelReaderFlowUnitBreakability.text;
    }
    return NovelReaderFlowUnitBreakability.atomicWidget;
  }

  List<int> _imageIndices(
    html_dom.Node node,
    ForumHtmlPreparedRenderDocument renderDocument,
  ) {
    final elements = <html_dom.Element>[];
    if (node is html_dom.Element && node.localName == 'img') {
      elements.add(node);
    }
    if (node is html_dom.Element) {
      elements.addAll(node.querySelectorAll('img'));
    }
    final indices = <int>{};
    for (final image in elements) {
      final rawIndex = image.attributes[forumHtmlReadableImageIndexAttribute];
      final index = int.tryParse(rawIndex ?? '');
      if (index == null || renderDocument.sequence.entryAt(index) == null) {
        continue;
      }
      indices.add(index);
    }
    final result = indices.toList()..sort();
    return List<int>.unmodifiable(result);
  }

  String _identityFor(html_dom.Node node) {
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
      return 'element:${node.localName}:${_stableHash('${node.text}|${attributes.join('|')}')}';
    }
    return 'text:${_stableHash(node.text ?? '')}';
  }

  String _anchorId(String identity, int occurrence) {
    final normalizedIdentity = identity.replaceAll(':', '-');
    return 'novel-html-$normalizedIdentity-$occurrence';
  }

  String _readableText(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.data;
    }
    return node.text ?? '';
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
