import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';

/// Renders a novel chapter's shared [RichBlock] tree. Block-level dispatch
/// keeps the novel-specific presentation (standalone link buttons, quote
/// styling, inline colour) while the underlying model is the canonical
/// reader_shared document.
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
    final blocks = document.blocks;
    return Column(
      key: const Key('novel-reader-document-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          _buildBlock(blocks[index]),
          if (index < blocks.length - 1) SizedBox(height: paragraphSpacing),
        ],
      ],
    );
  }

  Widget _buildBlock(RichBlock block) {
    if (block is RichTextBlock) {
      if (block.isHeading) {
        return NovelReaderParagraphBlock(
          key: _nodeKey(block.anchorId),
          runs: block.runs,
          style: typography.chapterTitle,
          linkStyle: typography.link,
          textAlign: TextAlign.start,
          firstLineIndent: 0,
          onLinkTap: onLinkTap,
          highlight: _highlightForBlock(block),
        );
      }
      if (block.isNovelLinkButton) {
        final run = block.runs.single;
        return NovelReaderLinkBlock(
          key: _nodeKey(block.anchorId),
          link: _linkFromRun(run),
          typography: typography,
          onTap: onLinkTap,
          highlighted: _highlightForBlock(block) != null,
        );
      }
      return NovelReaderParagraphBlock(
        key: _nodeKey(block.anchorId),
        runs: block.runs,
        style: typography.body,
        linkStyle: typography.link,
        textAlign: typography.textAlign,
        firstLineIndent: typography.firstLineIndent,
        onLinkTap: onLinkTap,
        highlight: _highlightForBlock(block),
      );
    }
    if (block is RichQuoteBlock) {
      return NovelReaderQuoteBlock(
        key: _nodeKey(block.anchorId),
        runs: _quoteRuns(block),
        typography: typography,
        onLinkTap: onLinkTap,
        highlight: _highlightForBlock(block),
      );
    }
    if (block is RichImageBlock) {
      return NovelReaderImageBlock(
        key: _nodeKey(block.anchorId),
        image: block,
        imageHeaderBuilder: imageHeaderBuilder,
      );
    }
    if (block is RichDividerBlock) {
      return Divider(key: _nodeKey(block.anchorId));
    }
    // RichSpacerBlock.
    return SizedBox(key: _nodeKey(block.anchorId), height: paragraphSpacing);
  }

  List<RichRun> _quoteRuns(RichQuoteBlock block) {
    final runs = <RichRun>[];
    for (final child in block.blocks) {
      if (child is RichTextBlock) {
        runs.addAll(child.runs);
      }
    }
    return runs;
  }

  static NovelReaderLink _linkFromRun(RichRun run) {
    return NovelReaderLink(
      url: run.linkUrl ?? '',
      text: run.text,
      tid: run.linkTid,
    );
  }

  static Key nodeKey(String nodeId) {
    return Key('novel-reader-node-$nodeId');
  }

  Key _nodeKey(String nodeId) {
    return nodeKeyBuilder?.call(nodeId) ?? nodeKey(nodeId);
  }

  NovelReaderSearchResult? _highlightForBlock(RichBlock block) {
    final result = highlightedResult;
    if (result == null || result.nodeId != block.anchorId) {
      return null;
    }
    return result;
  }
}

class NovelReaderParagraphBlock extends StatelessWidget {
  const NovelReaderParagraphBlock({
    super.key,
    required this.runs,
    required this.style,
    required this.linkStyle,
    required this.textAlign,
    required this.firstLineIndent,
    this.onLinkTap,
    this.highlight,
  });

  final List<RichRun> runs;
  final TextStyle style;
  final TextStyle linkStyle;
  final TextAlign textAlign;
  final double firstLineIndent;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final NovelReaderSearchResult? highlight;

  String get _plainText => runs.map((run) => run.text).join();

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[
      if (firstLineIndent > 0) TextSpan(text: _firstLineIndentPrefix()),
      if (highlight != null)
        ..._highlightedTextSpans()
      else
        for (final run in runs) ..._spansForRun(run),
    ];
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
    );
  }

  String _firstLineIndentPrefix() {
    final fontSize = style.fontSize ?? 16;
    final indentCount = math.max(1, (firstLineIndent / fontSize).round());
    return List<String>.filled(indentCount, '\u3000').join();
  }

  List<InlineSpan> _highlightedTextSpans() {
    final text = _plainText;
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

  List<InlineSpan> _spansForRun(RichRun run) {
    if (run.text == '\n') {
      return const <InlineSpan>[TextSpan(text: '\n')];
    }
    if (run.linkUrl != null) {
      final link = NovelReaderDocumentView._linkFromRun(run);
      return <InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onLinkTap?.call(link),
            child: Text(run.text, style: linkStyle),
          ),
        ),
      ];
    }
    if (run.text.isEmpty) {
      return const <InlineSpan>[];
    }
    return <InlineSpan>[TextSpan(text: run.text, style: _styleForRun(run))];
  }

  TextStyle? _styleForRun(RichRun run) {
    final color = _colorFromCss(run.color);
    if (!run.isBold && !run.isItalic && !run.isUnderline && color == null) {
      return null;
    }
    return TextStyle(
      fontWeight: run.isBold ? FontWeight.w700 : null,
      fontStyle: run.isItalic ? FontStyle.italic : null,
      decoration: run.isUnderline ? TextDecoration.underline : null,
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
    required this.runs,
    required this.typography,
    this.onLinkTap,
    this.highlight,
  });

  final List<RichRun> runs;
  final NovelReaderTypography typography;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final NovelReaderSearchResult? highlight;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        typography.quote.color ?? Theme.of(context).dividerColor;
    return DecoratedBox(
      key: const Key('novel-reader-quote-block'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        child: NovelReaderParagraphBlock(
          runs: runs,
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

class NovelReaderImageBlock extends StatefulWidget {
  const NovelReaderImageBlock({
    super.key,
    required this.image,
    this.imageHeaderBuilder,
  });

  final RichImageBlock image;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  State<NovelReaderImageBlock> createState() => _NovelReaderImageBlockState();
}

class _NovelReaderImageBlockState extends State<NovelReaderImageBlock> {
  int _retryToken = 0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.image.altText,
      child: LibraryCachedImage(
        key: ValueKey('novel-reader-image-${widget.image.url}-$_retryToken'),
        imageUrl: widget.image.url,
        fit: BoxFit.contain,
        placeholder: const SizedBox(
          height: 80,
          child: Center(child: Icon(Icons.image_outlined)),
        ),
        errorPlaceholder: SizedBox(
          key: const Key('novel-reader-image-error'),
          height: 96,
          child: Center(
            child: TextButton.icon(
              key: const Key('novel-reader-image-retry'),
              onPressed: () {
                setState(() {
                  _retryToken += 1;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('图片加载失败，点击重试'),
            ),
          ),
        ),
        headerBuilder: widget.imageHeaderBuilder,
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
              ? typography.link.copyWith(
                  backgroundColor: const Color(0x66FFD54F),
                )
              : typography.link,
        ),
      ),
    );
  }
}
