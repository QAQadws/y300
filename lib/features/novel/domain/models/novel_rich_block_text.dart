import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

/// Plain-text helpers for the novel reader's view over the shared [RichBlock]
/// tree. Search offsets, pagination height estimates, progress snippets and the
/// rendered text must all agree on how a block flattens to text, so the rule
/// lives in one place.
extension NovelRichBlockText on RichBlock {
  /// The block's readable text, joining runs / nested quote blocks with the
  /// same line-break semantics the renderer uses.
  String get novelPlainText {
    final block = this;
    if (block is RichTextBlock) {
      return block.runs
          .map((run) => run.inlineImage != null && run.text.isEmpty
              ? ''
              : run.text)
          .join();
    }
    if (block is RichQuoteBlock) {
      return block.blocks
          .map((child) => child.novelPlainText)
          .where((text) => text.trim().isNotEmpty)
          .join('\n');
    }
    return '';
  }

  /// True when this text block is a single standalone link (rendered as a
  /// tappable link button rather than inline text).
  bool get isNovelLinkButton {
    final block = this;
    return block is RichTextBlock &&
        !block.isHeading &&
        block.runs.length == 1 &&
        block.runs.single.linkUrl != null &&
        block.runs.single.inlineImage == null;
  }
}
