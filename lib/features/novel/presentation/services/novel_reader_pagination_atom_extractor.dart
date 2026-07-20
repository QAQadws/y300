import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';

/// Converts existing prepared flow units into pagination atoms.
///
/// Ordinary readable images are split out of mixed text/image blocks so the
/// page planner can isolate them without changing HTML preparation or the
/// whole-chapter image sequence. Stickers remain inside text atoms.
final class NovelReaderPaginationAtomExtractor {
  const NovelReaderPaginationAtomExtractor();

  List<NovelReaderPaginationAtom> extract(NovelReaderPreparedChapter chapter) {
    final atoms = <NovelReaderPaginationAtom>[];
    for (final unit in chapter.flowUnits) {
      if (unit.html.trim().isEmpty) {
        continue;
      }
      final parts =
          unit.breakability == NovelReaderFlowUnitBreakability.atomicWidget
          ? <_AtomPart>[
              _AtomPart(html: unit.html, imageIndices: unit.imageIndices),
            ]
          : _splitFragment(
              html: unit.html,
              sequence: chapter.renderDocument.sequence,
            );
      var textOffset = unit.startAnchor.textOffset;
      for (var index = 0; index < parts.length; index += 1) {
        final part = parts[index];
        if (!part.isolatedImage && !_isMeaningfulPart(part.html)) {
          continue;
        }
        final textLength = _textLength(part.html);
        final imageNodeId = part.isolatedImage
            ? '${unit.startAnchor.nodeId ?? unit.unitId}:image-'
                  '${part.imageIndices.single}'
            : null;
        final startAnchor = unit.startAnchor.copyWith(
          nodeId: imageNodeId,
          textOffset: part.isolatedImage ? 0 : textOffset,
        );
        final endAnchor = unit.endAnchor.copyWith(
          nodeId: imageNodeId,
          textOffset: part.isolatedImage ? 0 : textOffset + textLength,
        );
        final kind = _kindFor(
          part.html,
          unit.breakability,
          isIsolatedImage: part.isolatedImage,
        );
        atoms.add(
          NovelReaderPaginationAtom(
            atomId: '${unit.unitId}:atom-$index',
            kind: kind,
            html: part.html,
            startAnchor: startAnchor,
            endAnchor: endAnchor,
            textLength: textLength,
            imageIndices: part.imageIndices,
            breakability: part.isolatedImage
                ? NovelReaderFlowUnitBreakability.blockImage
                : unit.breakability,
            imagePagePolicy: part.isolatedImage
                ? NovelReaderImagePagePolicy.isolated
                : NovelReaderImagePagePolicy.inline,
          ),
        );
        textOffset += textLength;
      }
    }
    return List<NovelReaderPaginationAtom>.unmodifiable(atoms);
  }

  NovelReaderPaginationAtomKind _kindFor(
    String html,
    NovelReaderFlowUnitBreakability breakability, {
    required bool isIsolatedImage,
  }) {
    if (isIsolatedImage) {
      return NovelReaderPaginationAtomKind.image;
    }
    final fragment = html_parser.parseFragment(html);
    final firstElement = fragment.children.isEmpty
        ? null
        : fragment.children.first;
    final tag = firstElement?.localName?.toLowerCase();
    if (tag != null && RegExp(r'^h[1-6]$').hasMatch(tag)) {
      return NovelReaderPaginationAtomKind.heading;
    }
    if (tag == 'blockquote') {
      return NovelReaderPaginationAtomKind.quote;
    }
    if (breakability == NovelReaderFlowUnitBreakability.atomicWidget) {
      return NovelReaderPaginationAtomKind.atomicWidget;
    }
    if (html.contains('<img')) {
      return NovelReaderPaginationAtomKind.inlineImage;
    }
    return NovelReaderPaginationAtomKind.text;
  }

  List<_AtomPart> _splitFragment({
    required String html,
    required ForumHtmlReadableImageSequence sequence,
  }) {
    final fragment = html_parser.parseFragment(html);
    final parts = <_AtomPart>[];
    for (final node in fragment.nodes) {
      parts.addAll(_splitNode(node, sequence));
    }
    return parts.isEmpty
        ? <_AtomPart>[_AtomPart(html: html)]
        : List<_AtomPart>.unmodifiable(parts);
  }

  List<_AtomPart> _splitNode(
    html_dom.Node node,
    ForumHtmlReadableImageSequence sequence,
  ) {
    final imageIndex = _readableImageIndex(node, sequence);
    if (imageIndex != null) {
      return <_AtomPart>[
        _AtomPart(
          html: _serialize(node),
          imageIndices: <int>[imageIndex],
          isolatedImage: true,
        ),
      ];
    }
    if (node is html_dom.Text || node is! html_dom.Element) {
      return <_AtomPart>[_AtomPart(html: _serialize(node))];
    }
    if (!_containsReadableImage(node, sequence)) {
      return <_AtomPart>[_AtomPart(html: _serialize(node))];
    }

    final parts = <_AtomPart>[];
    var current = node.clone(false);
    for (final child in node.nodes) {
      final childParts = _splitNode(child, sequence);
      for (final childPart in childParts) {
        if (childPart.isolatedImage) {
          if (current.nodes.isNotEmpty) {
            parts.add(_AtomPart(html: _serialize(current)));
          }
          parts.add(_wrapIsolatedImage(node, childPart));
          current = node.clone(false);
        } else {
          _appendHtml(current, childPart.html);
        }
      }
    }
    if (current.nodes.isNotEmpty) {
      parts.add(_AtomPart(html: _serialize(current)));
    }
    return parts;
  }

  _AtomPart _wrapIsolatedImage(html_dom.Element parent, _AtomPart image) {
    final wrapper = parent.clone(false);
    _appendHtml(wrapper, image.html);
    return _AtomPart(
      html: _serialize(wrapper),
      imageIndices: image.imageIndices,
      isolatedImage: true,
    );
  }

  void _appendHtml(html_dom.Element parent, String html) {
    final fragment = html_parser.parseFragment(html);
    for (final node in fragment.nodes) {
      parent.append(node.clone(true));
    }
  }

  bool _containsReadableImage(
    html_dom.Element node,
    ForumHtmlReadableImageSequence sequence,
  ) {
    if (_readableImageIndex(node, sequence) != null) {
      return true;
    }
    return node
        .querySelectorAll('img')
        .any((image) => _readableImageIndex(image, sequence) != null);
  }

  int? _readableImageIndex(
    html_dom.Node node,
    ForumHtmlReadableImageSequence sequence,
  ) {
    if (node is! html_dom.Element || node.localName?.toLowerCase() != 'img') {
      return null;
    }
    final value = int.tryParse(
      node.attributes[forumHtmlReadableImageIndexAttribute] ?? '',
    );
    return value != null && sequence.entryAt(value) != null ? value : null;
  }

  int _textLength(String html) {
    return (html_parser.parseFragment(html).text ?? '').runes.length;
  }

  bool _isMeaningfulPart(String html) {
    final fragment = html_parser.parseFragment(html);
    if ((fragment.text ?? '').trim().isNotEmpty) {
      return true;
    }
    return fragment.querySelector(
          'img,br,hr,table,details,iframe,video,audio,object,canvas',
        ) !=
        null;
  }

  String _serialize(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }
}

final class _AtomPart {
  const _AtomPart({
    required this.html,
    this.imageIndices = const <int>[],
    this.isolatedImage = false,
  });

  final String html;
  final List<int> imageIndices;
  final bool isolatedImage;
}
