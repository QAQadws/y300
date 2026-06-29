import 'package:flutter/foundation.dart';

/// Canonical rich-text document model shared by the thread post reader and the
/// novel reader. Both features parse the same Discuz HTML, so the block/run/
/// image shapes are unified here (see plan §1.5/§6). Feature-specific metadata
/// (episode ids, word counts, render settings) stays in the owning feature —
/// `reader_shared` must not learn those concepts (DIP, plan §7).
///
/// The hierarchy is a sealed value tree: parsers produce it, renderers consume
/// it, and [RichDocumentCodec] ferries it across isolate boundaries.
@immutable
sealed class RichBlock {
  const RichBlock({
    this.anchorId = '',
    this.continuesPrevious = false,
  });

  /// Stable identity used for scroll anchoring, progress restore and search.
  /// Stability across re-parses/conversions matters: persisted anchors must
  /// keep resolving (novel keeps the historical `node-N` scheme).
  final String anchorId;

  /// True when this block visually continues the previous one (no paragraph
  /// gap). Used by the thread segmenter when a long block is split.
  final bool continuesPrevious;
}

/// A run of text-level content (paragraph or heading). [headingLevel] is 0 for
/// body text and 1-6 for headings; thread bodies always use 0, the novel reader
/// folds its `heading` nodes onto level 1+ so a single block type covers both.
class RichTextBlock extends RichBlock {
  const RichTextBlock({
    super.anchorId,
    super.continuesPrevious,
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
  const RichQuoteBlock({
    super.anchorId,
    super.continuesPrevious,
    required this.blocks,
  });

  final List<RichBlock> blocks;
}

/// A block-level image. [aid] is the Discuz attachment handle and is the only
/// key that lets a later pass swap a placeholder `<img>` for its real
/// attachment URL (plan §6 step 3) — it must survive parsing on both sides.
class RichImageBlock extends RichBlock {
  const RichImageBlock({
    super.anchorId,
    super.continuesPrevious,
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
  const RichDividerBlock({
    super.anchorId,
    super.continuesPrevious,
  });
}

/// An explicit vertical gap (e.g. a standalone `<br>` between blocks).
class RichSpacerBlock extends RichBlock {
  const RichSpacerBlock({
    super.anchorId,
    super.continuesPrevious,
  });
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
