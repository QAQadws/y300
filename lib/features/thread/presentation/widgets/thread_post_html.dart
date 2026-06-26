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
    this.imageBorderRadius = const BorderRadius.all(Radius.circular(4)),
    this.imageFallbackAspectRatio = 0.7,
    this.imageFit = BoxFit.fitWidth,
  });

  static const ThreadPostBodyStyle defaults = ThreadPostBodyStyle();

  final double blockSpacing;
  final TextStyle? textStyle;
  final TextStyle? linkTextStyle;
  final BorderRadius imageBorderRadius;
  final double imageFallbackAspectRatio;
  final BoxFit imageFit;

  ThreadPostBodyStyle copyWith({
    double? blockSpacing,
    TextStyle? textStyle,
    TextStyle? linkTextStyle,
    BorderRadius? imageBorderRadius,
    double? imageFallbackAspectRatio,
    BoxFit? imageFit,
  }) {
    return ThreadPostBodyStyle(
      blockSpacing: blockSpacing ?? this.blockSpacing,
      textStyle: textStyle ?? this.textStyle,
      linkTextStyle: linkTextStyle ?? this.linkTextStyle,
      imageBorderRadius: imageBorderRadius ?? this.imageBorderRadius,
      imageFallbackAspectRatio:
          imageFallbackAspectRatio ?? this.imageFallbackAspectRatio,
      imageFit: imageFit ?? this.imageFit,
    );
  }
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
        imageHeaderBuilder: imageHeaderBuilder,
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
    if (block is ThreadPostQuoteBlock) {
      return ThreadPostQuoteBlockView(
        document: document,
        quote: block,
        images: images,
        imageHeaderBuilder: imageHeaderBuilder,
        style: style,
        textTransformer: textTransformer,
        onOpenLink: onOpenLink,
        onOpenImage: onOpenImage,
        onOpenImages: onOpenImages,
      );
    }
    return const SizedBox.shrink();
  }
}

class ThreadPostQuoteBlockView extends StatelessWidget {
  const ThreadPostQuoteBlockView({
    super.key,
    required this.document,
    required this.quote,
    required this.images,
    required this.imageHeaderBuilder,
    required this.style,
    required this.textTransformer,
    required this.onOpenLink,
    required this.onOpenImage,
    required this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostQuoteBlock quote;
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
    final scheme = Theme.of(context).colorScheme;
    final quoteStyle = style.copyWith(
      blockSpacing: (style.blockSpacing * 0.72).clamp(4, 8).toDouble(),
      textStyle: DefaultTextStyle.of(
        context,
      ).style.merge(style.textStyle).copyWith(color: scheme.onSurfaceVariant),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < quote.blocks.length; index++) ...[
            if (index > 0) SizedBox(height: quoteStyle.blockSpacing),
            _ThreadPostBodyBlockView(
              document: document,
              block: quote.blocks[index],
              images: images,
              imageHeaderBuilder: imageHeaderBuilder,
              style: quoteStyle,
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

class ThreadPostTextBlockView extends StatelessWidget {
  const ThreadPostTextBlockView({
    super.key,
    required this.runs,
    this.imageHeaderBuilder,
    this.style = ThreadPostBodyStyle.defaults,
    this.textTransformer,
    this.onOpenLink,
  });

  final List<ThreadPostTextRun> runs;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyStyle style;
  final ThreadPostTextTransformer? textTransformer;
  final ThreadPostLinkTapHandler? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style.textStyle);
    return RichText(
      text: TextSpan(
        children: [
          for (final run in runs)
            run.inlineImage == null
                ? _spanForRun(context, run, baseStyle)
                : _inlineImageSpan(context, run.inlineImage!),
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
    final text = textTransformer?.call(run.text) ?? run.text;
    final linkStyle = baseStyle
        .copyWith(
          decoration: TextDecoration.underline,
          color: Theme.of(context).colorScheme.primary,
        )
        .merge(style.linkTextStyle);
    var spanStyle = (isLink ? linkStyle : baseStyle).copyWith(
      fontWeight: run.isBold
          ? FontWeight.w800
          : (isLink ? linkStyle.fontWeight : baseStyle.fontWeight),
      fontStyle: run.isItalic
          ? FontStyle.italic
          : (isLink ? linkStyle.fontStyle : baseStyle.fontStyle),
      decoration: run.isUnderline || isLink
          ? TextDecoration.underline
          : baseStyle.decoration,
    );
    if (_isDiscuzEditStatus(run, text)) {
      spanStyle = _editStatusStyle(context, spanStyle);
    }
    return TextSpan(
      text: text,
      style: spanStyle,
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

  InlineSpan _inlineImageSpan(
    BuildContext context,
    ThreadPostInlineImage image,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: KeyedSubtree(
          key: Key('thread-post-inline-image-${image.url}'),
          child: LibraryCachedImage(
            imageUrl: image.url,
            fit: BoxFit.contain,
            placeholder: const SizedBox.shrink(),
            errorPlaceholder: Icon(
              Icons.image_not_supported_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            headerBuilder: imageHeaderBuilder,
          ),
        ),
      ),
    );
  }

  bool _isDiscuzEditStatus(ThreadPostTextRun run, String text) {
    return run.isItalic && _discuzEditStatusPattern.hasMatch(text.trim());
  }

  TextStyle _editStatusStyle(BuildContext context, TextStyle source) {
    final fallbackStyle = DefaultTextStyle.of(context).style;
    final baseFontSize = source.fontSize ?? fallbackStyle.fontSize;
    final baseColor =
        source.color ??
        fallbackStyle.color ??
        Theme.of(context).colorScheme.onSurface;
    return source.copyWith(
      fontSize: baseFontSize == null ? null : baseFontSize * 0.88,
      color: baseColor.withValues(alpha: 0.62),
    );
  }
}

final RegExp _discuzEditStatusPattern = RegExp(
  r'^本帖最后由\s*.+?\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑$',
);

class ThreadPostImageBlockView extends StatefulWidget {
  const ThreadPostImageBlockView({
    super.key,
    required this.document,
    required this.image,
    required this.images,
    this.imageHeaderBuilder,
    this.style = ThreadPostBodyStyle.defaults,
    this.onOpenImage,
    this.onOpenImages,
    @visibleForTesting this.imageProviderOverride,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostImageBlock image;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostBodyStyle style;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;
  final ImageProvider? imageProviderOverride;

  @override
  State<ThreadPostImageBlockView> createState() =>
      _ThreadPostImageBlockViewState();
}

class _ThreadPostImageBlockViewState extends State<ThreadPostImageBlockView> {
  double? _resolvedAspectRatio;

  @override
  void didUpdateWidget(covariant ThreadPostImageBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.url != widget.image.url) {
      _resolvedAspectRatio = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _resolvedAspectRatio ?? _fallbackAspectRatio();
    return SelectionContainer.disabled(
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.style.imageBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('thread-post-image-${widget.image.index}'),
          onTap: () => _openImage(context),
          child: ClipRRect(
            borderRadius: widget.style.imageBorderRadius,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: LibraryCachedImage(
                imageUrl: widget.image.url,
                imageProviderOverride: widget.imageProviderOverride,
                fit: widget.style.imageFit,
                placeholder: const _ThreadPostImagePlaceholder(
                  label: '图片加载中',
                  icon: Icons.image_outlined,
                ),
                errorPlaceholder: const _ThreadPostImagePlaceholder(
                  label: '图片加载失败',
                  icon: Icons.broken_image_outlined,
                ),
                headerBuilder: widget.imageHeaderBuilder,
                onImageResolved: _handleImageResolved,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    final initialIndex = widget.images.indexWhere(
      (item) => item.url == widget.image.url,
    );
    final resolvedIndex = initialIndex < 0 ? widget.image.index : initialIndex;
    final imageHandler = widget.onOpenImage;
    if (imageHandler != null) {
      imageHandler(
        ThreadPostImageOpenRequest(
          document: widget.document,
          images: widget.images,
          image: widget.image,
          initialIndex: resolvedIndex,
        ),
      );
      return;
    }
    final callback = widget.onOpenImages;
    if (callback != null) {
      callback(widget.images, resolvedIndex);
      return;
    }
    Clipboard.setData(ClipboardData(text: widget.image.url));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('图片链接已复制')));
  }

  void _handleImageResolved(Size size) {
    final width = size.width;
    final height = size.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final next = width / height;
    if (_resolvedAspectRatio == next) {
      return;
    }
    setState(() {
      _resolvedAspectRatio = next;
    });
  }

  double _fallbackAspectRatio() {
    return _validAspectRatio(widget.style.imageFallbackAspectRatio);
  }

  double _validAspectRatio(double value) {
    return value.isFinite && value > 0
        ? value
        : ThreadPostBodyStyle.defaults.imageFallbackAspectRatio;
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
