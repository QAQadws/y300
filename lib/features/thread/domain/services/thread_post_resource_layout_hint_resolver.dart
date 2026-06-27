import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';

class ThreadPostResourceLayoutHintResolver {
  const ThreadPostResourceLayoutHintResolver({
    this.defaultBlockImageAspectRatio = 0.7,
    this.lockForCurrentBuild = false,
  }) : assert(defaultBlockImageAspectRatio > 0);

  final double defaultBlockImageAspectRatio;
  final bool lockForCurrentBuild;

  String get signature {
    return [
      defaultBlockImageAspectRatio.toStringAsFixed(6),
      lockForCurrentBuild,
    ].join('|');
  }

  ThreadPostResourceLayoutHints resolve(ThreadPostBodyDocument document) {
    final blockImages = <String, ThreadPostBlockImageLayoutHint>{};
    final inlineImages = <String, ThreadPostInlineImageLayoutHint>{};

    void collect(List<ThreadPostBodyBlock> blocks) {
      for (final block in blocks) {
        if (block is ThreadPostImageBlock) {
          final key = ThreadPostResourceLayoutHints.blockImageKey(block);
          blockImages[key] = _blockImageHint(block);
        } else if (block is ThreadPostTextBlock) {
          for (final run in block.runs) {
            final image = run.inlineImage;
            if (image == null) {
              continue;
            }
            final hint = _inlineImageHint(image);
            if (hint == null) {
              continue;
            }
            final key = ThreadPostResourceLayoutHints.inlineImageKey(image);
            inlineImages[key] = hint;
          }
        } else if (block is ThreadPostQuoteBlock) {
          collect(block.blocks);
        }
      }
    }

    collect(document.blocks);
    return ThreadPostResourceLayoutHints(
      blockImages: Map<String, ThreadPostBlockImageLayoutHint>.unmodifiable(
        blockImages,
      ),
      inlineImages: Map<String, ThreadPostInlineImageLayoutHint>.unmodifiable(
        inlineImages,
      ),
    );
  }

  ThreadPostBlockImageLayoutHint _blockImageHint(ThreadPostImageBlock image) {
    final dimension = _dimension(image.originalWidth, image.originalHeight);
    if (dimension != null) {
      return ThreadPostBlockImageLayoutHint(
        aspectRatio: dimension.aspectRatio,
        source: ThreadPostResourceLayoutHintSource.htmlAttribute,
        lockForCurrentBuild: lockForCurrentBuild,
      );
    }
    return ThreadPostBlockImageLayoutHint(
      aspectRatio: defaultBlockImageAspectRatio,
      source: ThreadPostResourceLayoutHintSource.contentDefault,
      lockForCurrentBuild: lockForCurrentBuild,
    );
  }

  ThreadPostInlineImageLayoutHint? _inlineImageHint(
    ThreadPostInlineImage image,
  ) {
    final dimension = _dimension(image.originalWidth, image.originalHeight);
    if (dimension == null) {
      return null;
    }
    return ThreadPostInlineImageLayoutHint(
      width: dimension.width,
      height: dimension.height,
      source: ThreadPostResourceLayoutHintSource.htmlAttribute,
      lockForCurrentBuild: lockForCurrentBuild,
    );
  }

  ThreadPostResourceDimension? _dimension(double? width, double? height) {
    if (width == null || height == null) {
      return null;
    }
    final dimension = ThreadPostResourceDimension(width: width, height: height);
    return dimension.isValid ? dimension : null;
  }
}
