import 'package:flutter/foundation.dart';

/// Semantic document used by novel parsing, search, bookmarks and HTML anchor
/// matching, and by on-demand plain-text extraction from thread bodies.
/// Feature-specific episode, progress and display settings stay in their
/// owning features.
///
/// The hierarchy is a sealed data-only value tree. Parsers produce it, and
/// reader services consume it directly, including across isolate boundaries.
@immutable
sealed class RichBlock {
  const RichBlock({this.anchorId = ''});

  /// Stable identity used for scroll anchoring, progress restore and search.
  /// Stability across re-parses/conversions matters: persisted anchors must
  /// keep resolving (novel keeps the historical `node-N` scheme).
  final String anchorId;
}

/// A run of text-level content (paragraph or heading). [headingLevel] is 0 for
/// body text and 1-6 for headings; thread bodies always use 0, the novel reader
/// folds its `heading` nodes onto level 1+ so a single block type covers both.
class RichTextBlock extends RichBlock {
  const RichTextBlock({
    super.anchorId,
    required this.runs,
    this.headingLevel = 0,
  });

  final List<RichRun> runs;
  final int headingLevel;

  bool get isHeading => headingLevel > 0;

  String get plainText => runs.map((run) => run.text).join();
}

/// A (possibly nested) quoted region.
class RichQuoteBlock extends RichBlock {
  const RichQuoteBlock({super.anchorId, required this.blocks});

  final List<RichBlock> blocks;
}

/// A block-level image. [aid] preserves the Discuz attachment identity alongside
/// the resolved and original source URLs.
class RichImageBlock extends RichBlock {
  const RichImageBlock({
    super.anchorId,
    required this.url,
    required this.rawUrl,
    required this.index,
    this.aid,
    this.altText,
    this.originalWidth,
    this.originalHeight,
  });

  final String url;
  final String rawUrl;
  final int index;
  final String? aid;
  final String? altText;
  final double? originalWidth;
  final double? originalHeight;
}

/// A horizontal rule (`<hr>`).
class RichDividerBlock extends RichBlock {
  const RichDividerBlock({super.anchorId});
}

/// An explicit vertical gap (e.g. a standalone `<br>` between blocks).
class RichSpacerBlock extends RichBlock {
  const RichSpacerBlock({super.anchorId});
}

/// An inline span inside a [RichTextBlock].
@immutable
class RichRun {
  const RichRun({
    required this.text,
    this.linkUrl,
    this.linkTid,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.color,
    this.inlineImage,
  });

  final String text;
  final String? linkUrl;

  /// Discuz thread id parsed from [linkUrl] when the link points at a post;
  /// lets the reader open it in-app instead of a browser.
  final String? linkTid;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;

  /// Raw CSS color string (e.g. `#ff0000`) preserved from inline styles.
  final String? color;
  final RichInlineImage? inlineImage;
}

/// A small inline image (emoji / smiley) rendered within a text run.
@immutable
class RichInlineImage {
  const RichInlineImage({
    required this.url,
    required this.rawUrl,
    this.aid,
    this.altText,
    this.titleText,
    this.originalWidth,
    this.originalHeight,
  });

  final String url;
  final String rawUrl;
  final String? aid;
  final String? altText;
  final String? titleText;
  final double? originalWidth;
  final double? originalHeight;
}

/// The parsed body: an ordered list of blocks.
@immutable
class RichDocument {
  const RichDocument({required this.blocks});

  static const RichDocument empty = RichDocument(blocks: <RichBlock>[]);

  final List<RichBlock> blocks;

  /// All block-level images in document order, descending into quotes.
  List<RichImageBlock> get images {
    final images = <RichImageBlock>[];
    void collect(List<RichBlock> source) {
      for (final block in source) {
        if (block is RichImageBlock) {
          images.add(block);
        } else if (block is RichQuoteBlock) {
          collect(block.blocks);
        }
      }
    }

    collect(blocks);
    return List<RichImageBlock>.unmodifiable(images);
  }
}
