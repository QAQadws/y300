import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';

class NovelReaderDocumentView extends StatelessWidget {
  const NovelReaderDocumentView({
    super.key,
    required this.document,
    required this.typography,
    required this.paragraphSpacing,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.highlightedResult,
    this.nodeKeyBuilder,
  });

  final NovelReaderDocument document;
  final NovelReaderTypography typography;
  final double paragraphSpacing;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final NovelReaderSearchResult? highlightedResult;
  final Key Function(String nodeId)? nodeKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('novel-reader-document-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < document.nodes.length; index++) ...[
          _buildNode(document.nodes[index]),
          if (index < document.nodes.length - 1) SizedBox(height: paragraphSpacing),
        ],
      ],
    );
  }

  Widget _buildNode(NovelReaderNode node) {
    switch (node.type) {
      case NovelReaderNodeType.heading:
        return NovelReaderParagraphBlock(
          key: _nodeKey(node.id),
          text: _textForNode(node),
          children: node.children,
          style: typography.chapterTitle,
          linkStyle: typography.link,
          textAlign: TextAlign.start,
          firstLineIndent: 0,
          onLinkTap: onLinkTap,
          highlight: _highlightForNode(node),
        );
      case NovelReaderNodeType.quote:
        return NovelReaderQuoteBlock(
          key: _nodeKey(node.id),
          text: _textForNode(node),
          children: node.children,
          typography: typography,
          onLinkTap: onLinkTap,
          highlight: _highlightForNode(node),
        );
      case NovelReaderNodeType.image:
        final image = node.image;
        if (image == null) {
          return const SizedBox.shrink();
        }
        return NovelReaderImageBlock(
          key: _nodeKey(node.id),
          image: image,
          imageHeaderBuilder: imageHeaderBuilder,
        );
      case NovelReaderNodeType.link:
        final link = node.link;
        if (link == null) {
          return NovelReaderParagraphBlock(
            key: _nodeKey(node.id),
            text: _textForNode(node),
            children: node.children,
            style: typography.body,
            linkStyle: typography.link,
            textAlign: typography.textAlign,
            firstLineIndent: typography.firstLineIndent,
            onLinkTap: onLinkTap,
            highlight: _highlightForNode(node),
          );
        }
        return NovelReaderLinkBlock(
          key: _nodeKey(node.id),
          link: link,
          typography: typography,
          onTap: onLinkTap,
          highlighted: _highlightForNode(node) != null,
        );
      case NovelReaderNodeType.divider:
        return Divider(key: _nodeKey(node.id));
      case NovelReaderNodeType.spacer:
        return SizedBox(
          key: _nodeKey(node.id),
          height: paragraphSpacing,
        );
      case NovelReaderNodeType.paragraph:
        return NovelReaderParagraphBlock(
          key: _nodeKey(node.id),
          text: _textForNode(node),
          children: node.children,
          style: typography.body,
          linkStyle: typography.link,
          textAlign: typography.textAlign,
          firstLineIndent: typography.firstLineIndent,
          onLinkTap: onLinkTap,
          highlight: _highlightForNode(node),
        );
    }
  }

  static Key nodeKey(String nodeId) {
    return Key('novel-reader-node-$nodeId');
  }

  Key _nodeKey(String nodeId) {
    return nodeKeyBuilder?.call(nodeId) ?? nodeKey(nodeId);
  }

  NovelReaderSearchResult? _highlightForNode(NovelReaderNode node) {
    final result = highlightedResult;
    if (result == null || result.nodeId != node.id) {
      return null;
    }
    return result;
  }

  String _textForNode(NovelReaderNode node) {
    final ownText = node.text?.trim();
    if (ownText != null && ownText.isNotEmpty) {
      return ownText;
    }
    return node.children
        .map((child) => child.text ?? child.link?.text ?? '')
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
  }
}

class NovelReaderParagraphBlock extends StatelessWidget {
  const NovelReaderParagraphBlock({
    super.key,
    required this.text,
    this.children = const <NovelReaderNode>[],
    required this.style,
    required this.linkStyle,
    required this.textAlign,
    required this.firstLineIndent,
    this.onLinkTap,
    this.highlight,
  });

  final String text;
  final List<NovelReaderNode> children;
  final TextStyle style;
  final TextStyle linkStyle;
  final TextAlign textAlign;
  final double firstLineIndent;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final NovelReaderSearchResult? highlight;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[
      if (firstLineIndent > 0) WidgetSpan(child: SizedBox(width: firstLineIndent)),
      if (highlight != null)
        ..._highlightedTextSpans()
      else if (children.isEmpty)
        ..._highlightedTextSpans()
      else
        for (final child in children) ..._spansForChild(child),
    ];
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
    );
  }

  List<InlineSpan> _highlightedTextSpans() {
    final result = highlight;
    if (result == null) {
      return <InlineSpan>[TextSpan(text: text)];
    }
    final start = result.matchStart.clamp(0, text.length).toInt();
    final end = result.matchEnd.clamp(start, text.length).toInt();
    if (start == end) {
      return <InlineSpan>[TextSpan(text: text)];
    }
    return <InlineSpan>[
      if (start > 0) TextSpan(text: text.substring(0, start)),
      TextSpan(
        text: text.substring(start, end),
        style: const TextStyle(
          backgroundColor: Color(0x66FFD54F),
          fontWeight: FontWeight.w700,
        ),
      ),
      if (end < text.length) TextSpan(text: text.substring(end)),
    ];
  }

  List<InlineSpan> _spansForChild(NovelReaderNode child) {
    if (child.type == NovelReaderNodeType.spacer) {
      return const <InlineSpan>[TextSpan(text: '\n')];
    }
    final link = child.link;
    if (child.type == NovelReaderNodeType.link && link != null) {
      return <InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onLinkTap?.call(link),
            child: Text(link.text, style: linkStyle),
          ),
        ),
      ];
    }
    if (child.children.isNotEmpty) {
      return <InlineSpan>[
        for (final grandChild in child.children) ..._spansForChild(grandChild),
      ];
    }
    final childText = child.text ?? child.link?.text ?? '';
    if (childText.isEmpty) {
      return const <InlineSpan>[];
    }
    return <InlineSpan>[
      TextSpan(
        text: childText,
        style: _styleForInline(child.style),
      ),
    ];
  }

  TextStyle? _styleForInline(NovelReaderInlineStyle inlineStyle) {
    final color = _colorFromCss(inlineStyle.color);
    if (!inlineStyle.bold && !inlineStyle.italic && color == null) {
      return null;
    }
    return TextStyle(
      fontWeight: inlineStyle.bold ? FontWeight.w700 : null,
      fontStyle: inlineStyle.italic ? FontStyle.italic : null,
      color: color,
    );
  }

  Color? _colorFromCss(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || !value.startsWith('#')) {
      return null;
    }
    final hex = value.substring(1);
    if (hex.length == 3) {
      final expanded = hex.split('').map((part) => '$part$part').join();
      final parsed = int.tryParse(expanded, radix: 16);
      return parsed == null ? null : Color(0xFF000000 | parsed);
    }
    if (hex.length == 6) {
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(0xFF000000 | parsed);
    }
    return null;
  }
}

class NovelReaderQuoteBlock extends StatelessWidget {
  const NovelReaderQuoteBlock({
    super.key,
    required this.text,
    this.children = const <NovelReaderNode>[],
    required this.typography,
    this.onLinkTap,
    this.highlight,
  });

  final String text;
  final List<NovelReaderNode> children;
  final NovelReaderTypography typography;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final NovelReaderSearchResult? highlight;

  @override
  Widget build(BuildContext context) {
    final borderColor = typography.quote.color ?? Theme.of(context).dividerColor;
    return DecoratedBox(
      key: const Key('novel-reader-quote-block'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        child: NovelReaderParagraphBlock(
          text: text,
          children: children,
          style: typography.quote,
          linkStyle: typography.link,
          textAlign: TextAlign.start,
          firstLineIndent: 0,
          onLinkTap: onLinkTap,
          highlight: highlight,
        ),
      ),
    );
  }
}

class NovelReaderImageBlock extends StatelessWidget {
  const NovelReaderImageBlock({
    super.key,
    required this.image,
    this.imageHeaderBuilder,
  });

  final NovelReaderImage image;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: image.altText,
      child: LibraryCachedImage(
        imageUrl: image.url,
        fit: BoxFit.contain,
        placeholder: const SizedBox(
          height: 80,
          child: Center(child: Icon(Icons.image_outlined)),
        ),
        errorPlaceholder: const SizedBox(
          height: 80,
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
        headerBuilder: imageHeaderBuilder,
      ),
    );
  }
}

class NovelReaderLinkBlock extends StatelessWidget {
  const NovelReaderLinkBlock({
    super.key,
    required this.link,
    required this.typography,
    this.onTap,
    this.highlighted = false,
  });

  final NovelReaderLink link;
  final NovelReaderTypography typography;
  final ValueChanged<NovelReaderLink>? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('novel-reader-link-block'),
        onPressed: () => onTap?.call(link),
        icon: const Icon(Icons.link),
        label: Text(
          link.text,
          style: highlighted
              ? typography.link.copyWith(backgroundColor: const Color(0x66FFD54F))
              : typography.link,
        ),
      ),
    );
  }
}
