import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

abstract class NovelReaderDocumentParser {
  NovelReaderDocument parse({
    required String episodeId,
    required String rawHtml,
    required List<String> fallbackParagraphs,
  });
}

class DiscuzNovelReaderDocumentParser implements NovelReaderDocumentParser {
  const DiscuzNovelReaderDocumentParser({
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
  }) : _domExtractor = domExtractor;

  final ForumPostDomExtractor _domExtractor;

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
    final nodes = <NovelReaderNode>[];
    var nextId = 0;
    for (final child in fragment.nodes) {
      nextId = _appendNode(
        child,
        nodes: nodes,
        nextId: nextId,
        inheritedStyle: const NovelReaderInlineStyle(),
      );
    }

    if (nodes.isEmpty) {
      return _fallbackDocument(episodeId, rawHtml, fallbackParagraphs);
    }
    return _documentFromNodes(episodeId, rawHtml, nodes);
  }

  int _appendNode(
    html_dom.Node node, {
    required List<NovelReaderNode> nodes,
    required int nextId,
    required NovelReaderInlineStyle inheritedStyle,
  }) {
    if (node is html_dom.Text) {
      final text = _normalizeText(node.text);
      if (text.isNotEmpty) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.paragraph,
            text: text,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      return nextId;
    }
    if (node is! html_dom.Element) {
      return nextId;
    }

    final tag = node.localName?.toLowerCase() ?? '';
    if (_skipTags.contains(tag)) {
      return nextId;
    }
    if (tag == 'br') {
      nodes.add(
        NovelReaderNode(
          id: _nodeId(nextId),
          type: NovelReaderNodeType.spacer,
        ),
      );
      return nextId + 1;
    }
    if (tag == 'hr') {
      nodes.add(
        NovelReaderNode(
          id: _nodeId(nextId),
          type: NovelReaderNodeType.divider,
        ),
      );
      return nextId + 1;
    }
    if (tag == 'img') {
      final image = _imageFromElement(node);
      if (image == null) {
        return nextId;
      }
      nodes.add(
        NovelReaderNode(
          id: _nodeId(nextId),
          type: NovelReaderNodeType.image,
          image: image,
        ),
      );
      return nextId + 1;
    }
    if (tag == 'a') {
      final link = _linkFromElement(node);
      if (link != null) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.link,
            text: link.text,
            link: link,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      final text = _normalizeText(node.text);
      if (text.isNotEmpty) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.paragraph,
            text: text,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      return nextId;
    }

    final nextStyle = _styleForElement(node, inheritedStyle);
    final isQuote = tag == 'blockquote' || node.classes.contains('quote');
    final isHeading = _headingTags.contains(tag);
    final isBlock = _blockTags.contains(tag);
    if (isQuote || isHeading || isBlock) {
      nextId = _appendStructuredElement(
        node,
        nodes: nodes,
        nextId: nextId,
        inheritedStyle: nextStyle,
        type: isQuote
            ? NovelReaderNodeType.quote
            : isHeading
                ? NovelReaderNodeType.heading
                : NovelReaderNodeType.paragraph,
      );
      return nextId;
    }

    for (final child in node.nodes) {
      nextId = _appendNode(
        child,
        nodes: nodes,
        nextId: nextId,
        inheritedStyle: nextStyle,
      );
    }
    return nextId;
  }

  int _appendStructuredElement(
    html_dom.Element element, {
    required List<NovelReaderNode> nodes,
    required int nextId,
    required NovelReaderInlineStyle inheritedStyle,
    required NovelReaderNodeType type,
  }) {
    final children = <NovelReaderNode>[];
    var childId = nextId;
    for (final child in element.nodes) {
      childId = _appendInlineChild(
        child,
        nodes: children,
        nextId: childId,
        inheritedStyle: inheritedStyle,
      );
    }

    final text = _textFromInlineChildren(children);
    if (children.isEmpty && text.isEmpty) {
      final images = <NovelReaderNode>[];
      for (final child in element.querySelectorAll('img')) {
        final image = _imageFromElement(child);
        if (image != null) {
          images.add(
            NovelReaderNode(
              id: _nodeId(childId),
              type: NovelReaderNodeType.image,
              image: image,
            ),
          );
          childId += 1;
        }
      }
      nodes.addAll(images);
      return childId;
    }

    final normalizedText = text.isNotEmpty ? text : _normalizeText(element.text);
    if (normalizedText.isNotEmpty || children.isNotEmpty) {
      final inlineChildren = children
          .where((child) => child.type != NovelReaderNodeType.image)
          .toList(growable: false);
      final imageChildren = children
          .where((child) => child.type == NovelReaderNodeType.image)
          .toList(growable: false);
      final singleInline = inlineChildren.length == 1 ? inlineChildren.single : null;
      if (type == NovelReaderNodeType.paragraph &&
          singleInline?.type == NovelReaderNodeType.link &&
          _normalizeText(singleInline?.text ?? singleInline?.link?.text ?? '') ==
              normalizedText) {
        nodes.add(singleInline!);
        nodes.addAll(imageChildren);
        return childId;
      }
      if (normalizedText.isNotEmpty || inlineChildren.isNotEmpty) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(childId),
            type: type,
            text: normalizedText,
            children: inlineChildren,
            style: inheritedStyle,
          ),
        );
        childId += 1;
      }
      nodes.addAll(imageChildren);
    }
    return childId;
  }

  int _appendInlineChild(
    html_dom.Node node, {
    required List<NovelReaderNode> nodes,
    required int nextId,
    required NovelReaderInlineStyle inheritedStyle,
  }) {
    if (node is html_dom.Text) {
      final text = _normalizeInlineText(node.text);
      if (text.trim().isNotEmpty) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.paragraph,
            text: text,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      return nextId;
    }
    if (node is! html_dom.Element) {
      return nextId;
    }
    final tag = node.localName?.toLowerCase() ?? '';
    if (_skipTags.contains(tag)) {
      return nextId;
    }
    if (tag == 'br') {
      nodes.add(
        NovelReaderNode(
          id: _nodeId(nextId),
          type: NovelReaderNodeType.spacer,
          text: '\n',
          style: inheritedStyle,
        ),
      );
      return nextId + 1;
    }
    if (tag == 'img') {
      final image = _imageFromElement(node);
      if (image == null) {
        return nextId;
      }
      nodes.add(
        NovelReaderNode(
          id: _nodeId(nextId),
          type: NovelReaderNodeType.image,
          image: image,
        ),
      );
      return nextId + 1;
    }
    if (tag == 'a') {
      final link = _linkFromElement(node);
      final text = _normalizeText(node.text);
      if (link != null) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.link,
            text: link.text,
            link: link,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      if (text.isNotEmpty) {
        nodes.add(
          NovelReaderNode(
            id: _nodeId(nextId),
            type: NovelReaderNodeType.paragraph,
            text: text,
            style: inheritedStyle,
          ),
        );
        return nextId + 1;
      }
      return nextId;
    }

    final nextStyle = _styleForElement(node, inheritedStyle);
    for (final child in node.nodes) {
      nextId = _appendInlineChild(
        child,
        nodes: nodes,
        nextId: nextId,
        inheritedStyle: nextStyle,
      );
    }
    return nextId;
  }

  NovelReaderImage? _imageFromElement(html_dom.Element element) {
    final raw = DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(element);
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
    return NovelReaderImage(
      url: normalized,
      altText: alt.isEmpty ? null : alt,
    );
  }

  NovelReaderLink? _linkFromElement(html_dom.Element element) {
    final text = _normalizeText(element.text);
    final rawHref = (element.attributes['href'] ?? '').trim();
    if (text.isEmpty || rawHref.isEmpty) {
      return null;
    }
    final normalized = _domExtractor.extractAnchors(element.outerHtml).firstOrNull;
    if (normalized == null) {
      return null;
    }
    final uri = Uri.tryParse(normalized.normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return NovelReaderLink(
      url: normalized.normalizedUrl,
      text: text,
      tid: normalized.tid,
    );
  }

  NovelReaderInlineStyle _styleForElement(
    html_dom.Element element,
    NovelReaderInlineStyle inherited,
  ) {
    final tag = element.localName?.toLowerCase();
    final style = element.attributes['style'] ?? '';
    final color = RegExp(
      r'color\s*:\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style)?.group(1)?.trim();
    final fontColor = element.attributes['color']?.trim();
    return NovelReaderInlineStyle(
      bold: inherited.bold || tag == 'strong' || tag == 'b',
      italic: inherited.italic || tag == 'em' || tag == 'i',
      color: color?.isNotEmpty == true
          ? color
          : (fontColor?.isNotEmpty == true ? fontColor : inherited.color),
    );
  }

  NovelReaderDocument _fallbackDocument(
    String episodeId,
    String rawHtml,
    List<String> fallbackParagraphs,
  ) {
    final nodes = <NovelReaderNode>[
      for (var index = 0; index < fallbackParagraphs.length; index++)
        if (_normalizeText(fallbackParagraphs[index]).isNotEmpty)
          NovelReaderNode(
            id: _nodeId(index),
            type: NovelReaderNodeType.paragraph,
            text: _normalizeText(fallbackParagraphs[index]),
          ),
    ];
    return _documentFromNodes(episodeId, rawHtml, nodes);
  }

  NovelReaderDocument _documentFromNodes(
    String episodeId,
    String rawHtml,
    List<NovelReaderNode> nodes,
  ) {
    final plainText = nodes
        .map(_plainTextForNode)
        .where((text) => text.isNotEmpty)
        .join('\n')
        .trim();
    return NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: _stableHash(rawHtml),
      nodes: nodes,
      plainText: plainText,
      wordCount: plainText.runes.where((rune) => !_isWhitespaceRune(rune)).length,
    );
  }

  String _plainTextForNode(NovelReaderNode node) {
    if (node.text != null && node.text!.trim().isNotEmpty) {
      return node.text!.trim();
    }
    if (node.link != null) {
      return node.link!.text.trim();
    }
    return node.children
        .map(_plainTextForNode)
        .where((text) => text.isNotEmpty)
        .join('\n')
        .trim();
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .trim();
  }

  String _normalizeInlineText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n');
  }

  String _textFromInlineChildren(List<NovelReaderNode> children) {
    final buffer = StringBuffer();
    for (final child in children) {
      if (child.type == NovelReaderNodeType.image) {
        continue;
      }
      final text = child.type == NovelReaderNodeType.spacer
          ? '\n'
          : child.text ?? child.link?.text ?? '';
      if (text.isEmpty) {
        continue;
      }
      buffer.write(text);
    }
    return _normalizeText(buffer.toString());
  }

  bool _isWhitespaceRune(int rune) {
    return String.fromCharCode(rune).trim().isEmpty;
  }

  String _nodeId(int index) => 'node-$index';

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
