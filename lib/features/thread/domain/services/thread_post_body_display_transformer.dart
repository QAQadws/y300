import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';

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

  ThreadPostBodyDocument transform(ThreadPostBodyDocument document) {
    final transformer = textTransformer;
    if (transformer == null) {
      return document;
    }
    return ThreadPostBodyDocument(
      blocks: List<ThreadPostBodyBlock>.unmodifiable(
        _transformBlocks(document.blocks, transformer),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThreadPostBodyDisplayTransformer && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  List<ThreadPostBodyBlock> _transformBlocks(
    List<ThreadPostBodyBlock> blocks,
    ThreadPostTextTransformer transformer,
  ) {
    return blocks
        .map((block) {
          if (block is ThreadPostTextBlock) {
            return ThreadPostTextBlock(
              anchorId: block.anchorId,
              continuesPrevious: block.continuesPrevious,
              runs: List<ThreadPostTextRun>.unmodifiable(
                block.runs.map((run) => _transformRun(run, transformer)),
              ),
            );
          }
          if (block is ThreadPostQuoteBlock) {
            return ThreadPostQuoteBlock(
              anchorId: block.anchorId,
              continuesPrevious: block.continuesPrevious,
              blocks: List<ThreadPostBodyBlock>.unmodifiable(
                _transformBlocks(block.blocks, transformer),
              ),
            );
          }
          return block;
        })
        .toList(growable: false);
  }

  ThreadPostTextRun _transformRun(
    ThreadPostTextRun run,
    ThreadPostTextTransformer transformer,
  ) {
    if (run.inlineImage != null) {
      return run;
    }
    return ThreadPostTextRun(
      text: transformer(run.text),
      linkUrl: run.linkUrl,
      isBold: run.isBold,
      isItalic: run.isItalic,
      isUnderline: run.isUnderline,
    );
  }
}
