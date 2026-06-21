sealed class ThreadPostBodyBlock {
  const ThreadPostBodyBlock();
}

class ThreadPostBodyDocument {
  const ThreadPostBodyDocument({required this.blocks});

  final List<ThreadPostBodyBlock> blocks;

  List<ThreadPostImageBlock> get images {
    final images = <ThreadPostImageBlock>[];
    void collect(List<ThreadPostBodyBlock> source) {
      for (final block in source) {
        if (block is ThreadPostImageBlock) {
          images.add(block);
        } else if (block is ThreadPostQuoteBlock) {
          collect(block.blocks);
        }
      }
    }

    collect(blocks);
    return List<ThreadPostImageBlock>.unmodifiable(images);
  }
}

class ThreadPostTextBlock extends ThreadPostBodyBlock {
  const ThreadPostTextBlock({required this.runs});

  final List<ThreadPostTextRun> runs;

  String get plainText => runs.map((run) => run.text).join();
}

class ThreadPostQuoteBlock extends ThreadPostBodyBlock {
  const ThreadPostQuoteBlock({required this.blocks});

  final List<ThreadPostBodyBlock> blocks;
}

class ThreadPostTextRun {
  const ThreadPostTextRun({
    required this.text,
    this.linkUrl,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.inlineImage,
  });

  final String text;
  final String? linkUrl;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final ThreadPostInlineImage? inlineImage;
}

class ThreadPostInlineImage {
  const ThreadPostInlineImage({
    required this.url,
    required this.rawUrl,
    this.altText,
  });

  final String url;
  final String rawUrl;
  final String? altText;
}

class ThreadPostImageBlock extends ThreadPostBodyBlock {
  const ThreadPostImageBlock({
    required this.url,
    required this.rawUrl,
    required this.index,
    this.aid,
    this.originalWidth,
    this.originalHeight,
  });

  final String url;
  final String rawUrl;
  final int index;
  final String? aid;
  final double? originalWidth;
  final double? originalHeight;
}
