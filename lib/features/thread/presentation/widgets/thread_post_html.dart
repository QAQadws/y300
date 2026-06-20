import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';

typedef ThreadPostTextTransformer = String Function(String text);
typedef ThreadPostLinkTapHandler = void Function(String url);
typedef ThreadPostImageOpenHandler =
    void Function(ThreadPostImageOpenRequest request);

class ThreadPostBodyStyle {
  const ThreadPostBodyStyle({
    this.blockSpacing = 10,
    this.textStyle,
    this.linkTextStyle,
    this.imageBorderRadius = const BorderRadius.all(Radius.circular(8)),
    this.imageMinHeight = 96,
    this.imageMaxHeight = 520,
    this.imageFallbackAspectRatio = 3 / 4,
    this.imageMinAspectRatio = 0.4,
    this.imageMaxAspectRatio = 2.2,
    this.imageFit = BoxFit.contain,
  });

  static const ThreadPostBodyStyle defaults = ThreadPostBodyStyle();

  final double blockSpacing;
  final TextStyle? textStyle;
  final TextStyle? linkTextStyle;
  final BorderRadius imageBorderRadius;
  final double imageMinHeight;
  final double imageMaxHeight;
  final double imageFallbackAspectRatio;
  final double imageMinAspectRatio;
  final double imageMaxAspectRatio;
  final BoxFit imageFit;
}

class ThreadPostImageOpenRequest {
  const ThreadPostImageOpenRequest({
    required this.document,
    required this.images,
    required this.image,
    required this.initialIndex,
  });

  final ThreadPostBodyDocument document;
  final List<ThreadPostImageBlock> images;
  final ThreadPostImageBlock image;
  final int initialIndex;

  List<String> get imageUrls =>
      images.map((image) => image.url).toList(growable: false);
}

class ThreadPostHtml extends StatelessWidget {
  const ThreadPostHtml({
    super.key,
    required this.data,
    this.imageHeaderBuilder,
    this.parser = const ThreadPostBodyParser(),
    this.style = ThreadPostBodyStyle.defaults,
    this.textTransformer,
    this.onOpenLink,
    this.onOpenImage,
    this.onOpenImages,
  });

  final String data;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyParser parser;
  final ThreadPostBodyStyle style;
  final ThreadPostTextTransformer? textTransformer;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final document = parser.parse(data);
    if (document.blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return ThreadPostBodyView(
      document: document,
      imageHeaderBuilder: imageHeaderBuilder,
      style: style,
      textTransformer: textTransformer,
      onOpenLink: onOpenLink,
      onOpenImage: onOpenImage,
      onOpenImages: onOpenImages,
    );
  }
}

class ThreadPostBodyView extends StatelessWidget {
  const ThreadPostBodyView({
    super.key,
    required this.document,
    this.imageHeaderBuilder,
    this.style = ThreadPostBodyStyle.defaults,
    this.textTransformer,
    this.onOpenLink,
    this.onOpenImage,
    this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyStyle style;
  final ThreadPostTextTransformer? textTransformer;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final blocks = document.blocks;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < blocks.length; index++) ...[
            if (index > 0) SizedBox(height: style.blockSpacing),
            _ThreadPostBodyBlockView(
              document: document,
              block: blocks[index],
              images: document.images,
              imageHeaderBuilder: imageHeaderBuilder,
              style: style,
              textTransformer: textTransformer,
              onOpenLink: onOpenLink,
              onOpenImage: onOpenImage,
              onOpenImages: onOpenImages,
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadPostBodyBlockView extends StatelessWidget {
  const _ThreadPostBodyBlockView({
    required this.document,
    required this.block,
    required this.images,
    required this.imageHeaderBuilder,
    required this.style,
    required this.textTransformer,
    required this.onOpenLink,
    required this.onOpenImage,
    required this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostBodyBlock block;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyStyle style;
  final ThreadPostTextTransformer? textTransformer;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final block = this.block;
    if (block is ThreadPostTextBlock) {
      return ThreadPostTextBlockView(
        runs: block.runs,
        style: style,
        textTransformer: textTransformer,
        onOpenLink: onOpenLink,
      );
    }
    if (block is ThreadPostImageBlock) {
      return ThreadPostImageBlockView(
        document: document,
        image: block,
        images: images,
        imageHeaderBuilder: imageHeaderBuilder,
        style: style,
        onOpenImage: onOpenImage,
        onOpenImages: onOpenImages,
      );
    }
    return const SizedBox.shrink();
  }
}

class ThreadPostTextBlockView extends StatelessWidget {
  const ThreadPostTextBlockView({
    super.key,
    required this.runs,
    this.style = ThreadPostBodyStyle.defaults,
    this.textTransformer,
    this.onOpenLink,
  });

  final List<ThreadPostTextRun> runs;
  final ThreadPostBodyStyle style;
  final ThreadPostTextTransformer? textTransformer;
  final ThreadPostLinkTapHandler? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style.textStyle);
    return RichText(
      text: TextSpan(
        children: [
          for (final run in runs) _spanForRun(context, run, baseStyle),
        ],
      ),
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: DefaultSelectionStyle.of(context).selectionColor,
    );
  }

  InlineSpan _spanForRun(
    BuildContext context,
    ThreadPostTextRun run,
    TextStyle baseStyle,
  ) {
    final linkUrl = run.linkUrl?.trim();
    final isLink = linkUrl != null && linkUrl.isNotEmpty;
    final linkStyle = baseStyle
        .copyWith(
          decoration: TextDecoration.underline,
          color: Theme.of(context).colorScheme.primary,
        )
        .merge(style.linkTextStyle);
    return TextSpan(
      text: textTransformer?.call(run.text) ?? run.text,
      style: (isLink ? linkStyle : baseStyle).copyWith(
        fontWeight: run.isBold
            ? FontWeight.w800
            : (isLink ? linkStyle.fontWeight : baseStyle.fontWeight),
        fontStyle: run.isItalic
            ? FontStyle.italic
            : (isLink ? linkStyle.fontStyle : baseStyle.fontStyle),
        decoration: run.isUnderline || isLink
            ? TextDecoration.underline
            : (isLink ? linkStyle.decoration : baseStyle.decoration),
      ),
      recognizer: isLink
          ? (TapGestureRecognizer()
              ..onTap = () {
                final handler = onOpenLink;
                if (handler != null) {
                  handler(linkUrl);
                  return;
                }
                Clipboard.setData(ClipboardData(text: linkUrl));
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(const SnackBar(content: Text('链接已复制')));
              })
          : null,
    );
  }
}

class ThreadPostImageBlockView extends StatelessWidget {
  const ThreadPostImageBlockView({
    super.key,
    required this.document,
    required this.image,
    required this.images,
    this.imageHeaderBuilder,
    this.style = ThreadPostBodyStyle.defaults,
    this.onOpenImage,
    this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostImageBlock image;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyStyle style;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _estimatedAspectRatio(image);
    return SelectionContainer.disabled(
      child: Material(
        color: Colors.transparent,
        borderRadius: style.imageBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('thread-post-image-${image.index}'),
          onTap: () => _openImage(context),
          child: ClipRRect(
            borderRadius: style.imageBorderRadius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                final height = (width / aspectRatio).clamp(
                  style.imageMinHeight,
                  style.imageMaxHeight,
                );
                return SizedBox(
                  height: height,
                  child: LibraryCachedImage(
                    imageUrl: image.url,
                    fit: style.imageFit,
                    placeholder: _ThreadPostImagePlaceholder(
                      label: '图片加载中',
                      icon: Icons.image_outlined,
                    ),
                    errorPlaceholder: _ThreadPostImagePlaceholder(
                      label: '图片加载失败',
                      icon: Icons.broken_image_outlined,
                    ),
                    headerBuilder: imageHeaderBuilder,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    final initialIndex = images.indexWhere((item) => item.url == image.url);
    final resolvedIndex = initialIndex < 0 ? image.index : initialIndex;
    final imageHandler = onOpenImage;
    if (imageHandler != null) {
      imageHandler(
        ThreadPostImageOpenRequest(
          document: document,
          images: images,
          image: image,
          initialIndex: resolvedIndex,
        ),
      );
      return;
    }
    final callback = onOpenImages;
    if (callback != null) {
      callback(images, resolvedIndex);
      return;
    }
    Clipboard.setData(ClipboardData(text: image.url));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('图片链接已复制')));
  }

  double _estimatedAspectRatio(ThreadPostImageBlock image) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    if (width != null && height != null && width > 0 && height > 0) {
      return (width / height)
          .clamp(style.imageMinAspectRatio, style.imageMaxAspectRatio)
          .toDouble();
    }
    return style.imageFallbackAspectRatio
        .clamp(style.imageMinAspectRatio, style.imageMaxAspectRatio)
        .toDouble();
  }
}

class _ThreadPostImagePlaceholder extends StatelessWidget {
  const _ThreadPostImagePlaceholder({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
