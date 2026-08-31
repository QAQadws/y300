import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

typedef ThreadPostTextTransformer = String Function(String text);

/// Text-transformation strategy applied to post body blocks before rendering.
///
/// Identity is encoded in [signature]; two transformers with the same
/// [signature] are treated as equivalent for render-plan caching purposes.
class ThreadPostBodyDisplayTransformer {
  const ThreadPostBodyDisplayTransformer({
    this.textTransformer,
    this.signature = 'identity',
  });

  final ThreadPostTextTransformer? textTransformer;
  final String signature;

  RichDocument transform(RichDocument document) {
    final transformer = textTransformer;
    if (transformer == null) {
      return document;
    }
    return RichDocument(
      blocks: List<RichBlock>.unmodifiable(
        _transformBlocks(document.blocks, transformer),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThreadPostBodyDisplayTransformer && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  List<RichBlock> _transformBlocks(
    List<RichBlock> blocks,
    ThreadPostTextTransformer transformer,
  ) {
    return blocks
        .map((block) {
          if (block is RichTextBlock) {
            return RichTextBlock(
              anchorId: block.anchorId,
              continuesPrevious: block.continuesPrevious,
              runs: List<RichRun>.unmodifiable(
                block.runs.map((run) => _transformRun(run, transformer)),
              ),
            );
          }
          if (block is RichQuoteBlock) {
            return RichQuoteBlock(
              anchorId: block.anchorId,
              continuesPrevious: block.continuesPrevious,
              blocks: List<RichBlock>.unmodifiable(
                _transformBlocks(block.blocks, transformer),
              ),
            );
          }
          return block;
        })
        .toList(growable: false);
  }

  RichRun _transformRun(RichRun run, ThreadPostTextTransformer transformer) {
    if (run.inlineImage != null) {
      return run;
    }
    return RichRun(
      text: transformer(run.text),
      linkUrl: run.linkUrl,
      isBold: run.isBold,
      isItalic: run.isItalic,
      isUnderline: run.isUnderline,
    );
  }
}
