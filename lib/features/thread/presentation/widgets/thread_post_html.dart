import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_display_transformer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';
import 'package:y300/features/thread/presentation/services/thread_post_continuous_image_adapter.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_continuous_image_adapter.dart';

typedef ThreadPostLinkTapHandler = void Function(String url);
typedef ThreadPostImageOpenHandler =
    void Function(ThreadPostImageOpenRequest request);
typedef ThreadPostBlockImageCacheRequestBuilder =
    ImageCacheRequest Function(ThreadPostImageBlock image);
typedef ThreadPostInlineImageCacheRequestBuilder =
    ImageCacheRequest Function(ThreadPostInlineImage image);

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

class ThreadPostResourceLayoutPolicy {
  const ThreadPostResourceLayoutPolicy({
    required this.lockImageAspectRatioForCurrentBuild,
    required this.lockInlineImageSizeForCurrentBuild,
    this.deferImageAspectRatioUpdateWhenAboveViewport = false,
  });

  /// Allows existing shared HTML renderers to keep using cache/image hints for
  /// precise layout, while the native thread reader can opt into stable heights.
  static const ThreadPostResourceLayoutPolicy defaults =
      ThreadPostResourceLayoutPolicy(
        lockImageAspectRatioForCurrentBuild: false,
        lockInlineImageSizeForCurrentBuild: false,
      );

  static const ThreadPostResourceLayoutPolicy lockedForReading =
      ThreadPostResourceLayoutPolicy(
        lockImageAspectRatioForCurrentBuild: true,
        lockInlineImageSizeForCurrentBuild: true,
        deferImageAspectRatioUpdateWhenAboveViewport: true,
      );

  static const ThreadPostResourceLayoutPolicy adaptiveBlockImagesForReading =
      ThreadPostResourceLayoutPolicy(
        lockImageAspectRatioForCurrentBuild: false,
        lockInlineImageSizeForCurrentBuild: true,
        deferImageAspectRatioUpdateWhenAboveViewport: true,
      );

  final bool lockImageAspectRatioForCurrentBuild;
  final bool lockInlineImageSizeForCurrentBuild;
  final bool deferImageAspectRatioUpdateWhenAboveViewport;

  @override
  bool operator ==(Object other) {
    return other is ThreadPostResourceLayoutPolicy &&
        other.lockImageAspectRatioForCurrentBuild ==
            lockImageAspectRatioForCurrentBuild &&
        other.lockInlineImageSizeForCurrentBuild ==
            lockInlineImageSizeForCurrentBuild &&
        other.deferImageAspectRatioUpdateWhenAboveViewport ==
            deferImageAspectRatioUpdateWhenAboveViewport;
  }

  @override
  int get hashCode => Object.hash(
    lockImageAspectRatioForCurrentBuild,
    lockInlineImageSizeForCurrentBuild,
    deferImageAspectRatioUpdateWhenAboveViewport,
  );
}

class ThreadPostImageOpenRequest {
  const ThreadPostImageOpenRequest({
    required this.document,
    required this.images,
    required this.image,
    required this.initialIndex,
    this.readerRequest,
  });

  final ThreadPostBodyDocument document;
  final List<ThreadPostImageBlock> images;
  final ThreadPostImageBlock image;
  final int initialIndex;
  final ThreadImageOpenRequest? readerRequest;

  List<String> get imageUrls =>
      images.map((image) => image.url).toList(growable: false);
}

class ThreadPostHtml extends StatefulWidget {
  const ThreadPostHtml({
    super.key,
    required this.data,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.blockImageCacheRequestBuilder,
    this.inlineImageCacheRequestBuilder,
    this.imageOpenContext,
    this.parser = const ThreadPostBodyParser(),
    this.normalizer = const ThreadPostBodyDocumentNormalizer(),
    this.style = ThreadPostBodyStyle.defaults,
    this.renderSettings = ThreadPostBodyRenderSettings.defaults,
    this.resourceLayoutPolicy = ThreadPostResourceLayoutPolicy.defaults,
    this.textTransformer,
    this.selectionEnabled = false,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    this.onOpenLink,
    this.onOpenImage,
    this.onOpenImages,
  });

  final String data;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostBodyParser parser;
  final ThreadPostBodyDocumentNormalizer normalizer;
  final ThreadPostBodyStyle style;
  final ThreadPostBodyRenderSettings renderSettings;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final ThreadPostTextTransformer? textTransformer;
  final bool selectionEnabled;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  State<ThreadPostHtml> createState() => _ThreadPostHtmlState();
}

class _ThreadPostHtmlState extends State<ThreadPostHtml> {
  late ThreadPostBodyDocument _document;
  late ThreadPostBodyDocument _displayDocument;
  late ThreadPostResourceLayoutHints _resourceLayoutHints;
  late _ThreadPostDocumentCacheKey _documentCacheKey;

  @override
  void initState() {
    super.initState();
    _parseDocument();
  }

  @override
  void didUpdateWidget(covariant ThreadPostHtml oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_documentCacheKey != _cacheKeyFor(widget)) {
      _parseDocument();
    }
  }

  void _parseDocument() {
    _documentCacheKey = _cacheKeyFor(widget);
    _document = widget.normalizer.normalize(widget.parser.parse(widget.data));
    _displayDocument = ThreadPostBodyDisplayTransformer(
      textTransformer: widget.textTransformer,
      signature: widget.renderSettings.textTransformerKey.isEmpty
          ? 'widget'
          : widget.renderSettings.textTransformerKey,
    ).transform(_document);
    _resourceLayoutHints = ThreadPostResourceLayoutHintResolver(
      defaultBlockImageAspectRatio: widget.style.imageFallbackAspectRatio,
      lockForCurrentBuild:
          widget.resourceLayoutPolicy.lockImageAspectRatioForCurrentBuild ||
          widget.resourceLayoutPolicy.lockInlineImageSizeForCurrentBuild,
    ).resolve(_document);
  }

  _ThreadPostDocumentCacheKey _cacheKeyFor(ThreadPostHtml widget) {
    return _ThreadPostDocumentCacheKey(
      data: widget.data,
      parser: widget.parser,
      normalizer: widget.normalizer,
      renderSettingsSignature: widget.renderSettings.signature,
      textTransformer: widget.textTransformer,
      imageFallbackAspectRatio: widget.style.imageFallbackAspectRatio,
      resourceLayoutPolicy: widget.resourceLayoutPolicy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final displayDocument = _displayDocument;
    if (displayDocument.blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    final effectiveStyle = _effectiveStyle(widget.style, widget.renderSettings);
    return ThreadPostBodyView(
      document: document,
      blocks: displayDocument.blocks,
      images: displayDocument.images,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      imageCacheOwnerId: widget.imageCacheOwnerId,
      blockImageCacheRequestBuilder: widget.blockImageCacheRequestBuilder,
      inlineImageCacheRequestBuilder: widget.inlineImageCacheRequestBuilder,
      imageOpenContext: widget.imageOpenContext,
      resourceLayoutHints: _resourceLayoutHints,
      style: effectiveStyle,
      resourceLayoutPolicy: widget.resourceLayoutPolicy,
      selectionEnabled: widget.selectionEnabled,
      diagnosticRecorder: widget.diagnosticRecorder,
      onOpenLink: widget.onOpenLink,
      onOpenImage: widget.onOpenImage,
      onOpenImages: widget.onOpenImages,
    );
  }

  ThreadPostBodyStyle _effectiveStyle(
    ThreadPostBodyStyle style,
    ThreadPostBodyRenderSettings settings,
  ) {
    TextStyle? textStyle = style.textStyle;
    if (settings.fontSize != null || settings.lineHeight != null) {
      textStyle = (textStyle ?? const TextStyle()).copyWith(
        fontSize: settings.fontSize,
        height: settings.lineHeight,
      );
    }
    return style.copyWith(
      blockSpacing:
          settings.paragraphSpacing ??
          settings.blockSpacing ??
          style.blockSpacing,
      textStyle: textStyle,
    );
  }
}

class _ThreadPostDocumentCacheKey {
  const _ThreadPostDocumentCacheKey({
    required this.data,
    required this.parser,
    required this.normalizer,
    required this.renderSettingsSignature,
    required this.textTransformer,
    required this.imageFallbackAspectRatio,
    required this.resourceLayoutPolicy,
  });

  final String data;
  final ThreadPostBodyParser parser;
  final ThreadPostBodyDocumentNormalizer normalizer;
  final String renderSettingsSignature;
  final ThreadPostTextTransformer? textTransformer;
  final double imageFallbackAspectRatio;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;

  @override
  bool operator ==(Object other) {
    return other is _ThreadPostDocumentCacheKey &&
        other.data == data &&
        identical(other.parser, parser) &&
        identical(other.normalizer, normalizer) &&
        other.renderSettingsSignature == renderSettingsSignature &&
        identical(other.textTransformer, textTransformer) &&
        other.imageFallbackAspectRatio == imageFallbackAspectRatio &&
        other.resourceLayoutPolicy == resourceLayoutPolicy;
  }

  @override
  int get hashCode => Object.hash(
    data,
    identityHashCode(parser),
    identityHashCode(normalizer),
    renderSettingsSignature,
    identityHashCode(textTransformer),
    imageFallbackAspectRatio,
    resourceLayoutPolicy,
  );
}

class ThreadPostBodySegmentView extends StatelessWidget {
  const ThreadPostBodySegmentView({
    super.key,
    required this.document,
    required this.segment,
    required this.images,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.blockImageCacheRequestBuilder,
    this.inlineImageCacheRequestBuilder,
    this.imageOpenContext,
    this.resourceLayoutHints = ThreadPostResourceLayoutHints.empty,
    this.style = ThreadPostBodyStyle.defaults,
    this.resourceLayoutPolicy = ThreadPostResourceLayoutPolicy.defaults,
    this.selectionEnabled = false,
    this.createSelectionArea = true,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    this.onOpenLink,
    this.onOpenImage,
    this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostBodySegment segment;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final bool selectionEnabled;
  final bool createSelectionArea;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    return ThreadPostBodyView(
      document: document,
      blocks: segment.blocks,
      images: images,
      imageHeaderBuilder: imageHeaderBuilder,
      imageCacheOwnerId: imageCacheOwnerId,
      blockImageCacheRequestBuilder: blockImageCacheRequestBuilder,
      inlineImageCacheRequestBuilder: inlineImageCacheRequestBuilder,
      imageOpenContext: imageOpenContext,
      resourceLayoutHints: resourceLayoutHints,
      style: style,
      resourceLayoutPolicy: resourceLayoutPolicy,
      selectionEnabled: selectionEnabled,
      createSelectionArea: createSelectionArea,
      diagnosticRecorder: diagnosticRecorder,
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
    required this.blocks,
    required this.images,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.blockImageCacheRequestBuilder,
    this.inlineImageCacheRequestBuilder,
    this.imageOpenContext,
    this.resourceLayoutHints = ThreadPostResourceLayoutHints.empty,
    this.style = ThreadPostBodyStyle.defaults,
    this.resourceLayoutPolicy = ThreadPostResourceLayoutPolicy.defaults,
    this.selectionEnabled = false,
    this.createSelectionArea = true,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    this.onOpenLink,
    this.onOpenImage,
    this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final List<ThreadPostBodyBlock> blocks;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final bool selectionEnabled;
  final bool createSelectionArea;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0 && !blocks[index].continuesPrevious)
            SizedBox(height: style.blockSpacing),
          _ThreadPostBodyBlockView(
            document: document,
            block: blocks[index],
            images: images,
            imageHeaderBuilder: imageHeaderBuilder,
            imageCacheOwnerId: imageCacheOwnerId,
            blockImageCacheRequestBuilder: blockImageCacheRequestBuilder,
            inlineImageCacheRequestBuilder: inlineImageCacheRequestBuilder,
            imageOpenContext: imageOpenContext,
            resourceLayoutHints: resourceLayoutHints,
            style: style,
            resourceLayoutPolicy: resourceLayoutPolicy,
            selectionEnabled: selectionEnabled,
            diagnosticRecorder: diagnosticRecorder,
            onOpenLink: onOpenLink,
            onOpenImage: onOpenImage,
            onOpenImages: onOpenImages,
          ),
        ],
      ],
    );
    return selectionEnabled && createSelectionArea && _hasSelectableText(blocks)
        ? SelectionArea(child: body)
        : body;
  }

  bool _hasSelectableText(List<ThreadPostBodyBlock> blocks) {
    for (final block in blocks) {
      if (block is ThreadPostTextBlock &&
          block.runs.any(
            (run) => run.inlineImage == null && run.text.trim().isNotEmpty,
          )) {
        return true;
      }
      if (block is ThreadPostQuoteBlock && _hasSelectableText(block.blocks)) {
        return true;
      }
    }
    return false;
  }
}

class _ThreadPostBodyBlockView extends StatelessWidget {
  const _ThreadPostBodyBlockView({
    required this.document,
    required this.block,
    required this.images,
    required this.imageHeaderBuilder,
    required this.imageCacheOwnerId,
    required this.blockImageCacheRequestBuilder,
    required this.inlineImageCacheRequestBuilder,
    required this.imageOpenContext,
    required this.resourceLayoutHints,
    required this.style,
    required this.resourceLayoutPolicy,
    this.selectionEnabled = false,
    required this.diagnosticRecorder,
    required this.onOpenLink,
    required this.onOpenImage,
    required this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostBodyBlock block;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final bool selectionEnabled;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
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
        imageCacheOwnerId: imageCacheOwnerId,
        inlineImageCacheRequestBuilder: inlineImageCacheRequestBuilder,
        resourceLayoutHints: resourceLayoutHints,
        style: style,
        resourceLayoutPolicy: resourceLayoutPolicy,
        selectionEnabled: selectionEnabled,
        onOpenLink: onOpenLink,
      );
    }
    if (block is ThreadPostImageBlock) {
      return ThreadPostImageBlockView(
        document: document,
        image: block,
        images: images,
        imageHeaderBuilder: imageHeaderBuilder,
        imageCacheOwnerId: imageCacheOwnerId,
        blockImageCacheRequestBuilder: blockImageCacheRequestBuilder,
        imageOpenContext: imageOpenContext,
        resourceLayoutHints: resourceLayoutHints,
        style: style,
        resourceLayoutPolicy: resourceLayoutPolicy,
        onOpenImage: onOpenImage,
        onOpenImages: onOpenImages,
        diagnosticRecorder: diagnosticRecorder,
      );
    }
    if (block is ThreadPostQuoteBlock) {
      return ThreadPostQuoteBlockView(
        document: document,
        quote: block,
        images: images,
        imageHeaderBuilder: imageHeaderBuilder,
        imageCacheOwnerId: imageCacheOwnerId,
        blockImageCacheRequestBuilder: blockImageCacheRequestBuilder,
        inlineImageCacheRequestBuilder: inlineImageCacheRequestBuilder,
        imageOpenContext: imageOpenContext,
        resourceLayoutHints: resourceLayoutHints,
        style: style,
        resourceLayoutPolicy: resourceLayoutPolicy,
        selectionEnabled: selectionEnabled,
        diagnosticRecorder: diagnosticRecorder,
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
    required this.imageCacheOwnerId,
    required this.blockImageCacheRequestBuilder,
    required this.inlineImageCacheRequestBuilder,
    required this.imageOpenContext,
    required this.resourceLayoutHints,
    required this.style,
    required this.resourceLayoutPolicy,
    required this.selectionEnabled,
    required this.diagnosticRecorder,
    required this.onOpenLink,
    required this.onOpenImage,
    required this.onOpenImages,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostQuoteBlock quote;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final bool selectionEnabled;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ThreadPostLinkTapHandler? onOpenLink;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = this.images;
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
            if (index > 0 && !quote.blocks[index].continuesPrevious)
              SizedBox(height: quoteStyle.blockSpacing),
            _ThreadPostBodyBlockView(
              document: document,
              block: quote.blocks[index],
              images: images,
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: imageCacheOwnerId,
              blockImageCacheRequestBuilder: blockImageCacheRequestBuilder,
              inlineImageCacheRequestBuilder: inlineImageCacheRequestBuilder,
              imageOpenContext: imageOpenContext,
              resourceLayoutHints: resourceLayoutHints,
              style: quoteStyle,
              resourceLayoutPolicy: resourceLayoutPolicy,
              selectionEnabled: selectionEnabled,
              diagnosticRecorder: diagnosticRecorder,
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
    this.imageCacheOwnerId,
    this.inlineImageCacheRequestBuilder,
    this.resourceLayoutHints = ThreadPostResourceLayoutHints.empty,
    this.style = ThreadPostBodyStyle.defaults,
    this.resourceLayoutPolicy = ThreadPostResourceLayoutPolicy.defaults,
    this.selectionEnabled = false,
    this.onOpenLink,
  });

  final List<ThreadPostTextRun> runs;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostInlineImageCacheRequestBuilder?
  inlineImageCacheRequestBuilder;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final bool selectionEnabled;
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
      selectionRegistrar: selectionEnabled
          ? SelectionContainer.maybeOf(context)
          : null,
      selectionColor: selectionEnabled
          ? DefaultSelectionStyle.of(context).selectionColor
          : null,
    );
  }

  InlineSpan _spanForRun(
    BuildContext context,
    ThreadPostTextRun run,
    TextStyle baseStyle,
  ) {
    final linkUrl = run.linkUrl?.trim();
    final isLink = linkUrl != null && linkUrl.isNotEmpty;
    final text = run.text;
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
    final request =
        inlineImageCacheRequestBuilder?.call(image) ??
        ForumImageCacheRequests.remoteSmiley(url: image.url);
    final child = _ThreadPostInlineImageView(
      image: image,
      request: request,
      imageHeaderBuilder: imageHeaderBuilder,
      layoutHint: resourceLayoutHints.inlineImage(image),
      resourceLayoutPolicy: resourceLayoutPolicy,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: KeyedSubtree(
          key: Key('thread-post-inline-image-${image.url}'),
          child: child,
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

class _ThreadPostInlineImageView extends ConsumerStatefulWidget {
  const _ThreadPostInlineImageView({
    required this.image,
    required this.request,
    required this.imageHeaderBuilder,
    required this.layoutHint,
    required this.resourceLayoutPolicy,
  });

  final ThreadPostInlineImage image;
  final ImageCacheRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostInlineImageLayoutHint? layoutHint;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;

  @override
  ConsumerState<_ThreadPostInlineImageView> createState() =>
      _ThreadPostInlineImageViewState();
}

class _ThreadPostInlineImageViewState
    extends ConsumerState<_ThreadPostInlineImageView> {
  Size? _cachedSize;
  String? _loadedCacheKey;

  @override
  void initState() {
    super.initState();
    if (!_locksInlineImageSize) {
      _loadCachedSize();
    }
  }

  @override
  void didUpdateWidget(covariant _ThreadPostInlineImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheKey != widget.request.cacheKey ||
        oldWidget.image.url != widget.image.url) {
      _cachedSize = null;
      _loadedCacheKey = null;
      if (!_locksInlineImageSize) {
        _loadCachedSize();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final originalSize = _inlineImageOriginalSize(widget.image);
    final hintSize = _hintSize();
    final size =
        hintSize ??
        originalSize ??
        (_locksInlineImageSize ? null : _cachedSize);
    final child = CachedLibraryImage(
      request: widget.request,
      fit: BoxFit.contain,
      width: size?.width,
      height: size?.height,
      placeholder: const SizedBox.shrink(),
      errorPlaceholder: Icon(
        Icons.image_not_supported_outlined,
        size: (size?.shortestSide ?? 14).clamp(12, 18).toDouble(),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      headerBuilder: widget.imageHeaderBuilder,
    );
    if (size == null) {
      return child;
    }
    return SizedBox(width: size.width, height: size.height, child: child);
  }

  Future<void> _loadCachedSize() async {
    if (_locksInlineImageSize) {
      return;
    }
    final cacheKey = widget.request.cacheKey.trim();
    if (cacheKey.isEmpty || _loadedCacheKey == cacheKey) {
      return;
    }
    _loadedCacheKey = cacheKey;
    final result = await ref
        .read(imageCacheServiceProvider)
        .getCached(cacheKey);
    if (!mounted || _loadedCacheKey != cacheKey || result == null) {
      return;
    }
    final width = result.width;
    final height = result.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return;
    }
    final next = Size(width.toDouble(), height.toDouble());
    if (_cachedSize == next || _inlineImageOriginalSize(widget.image) != null) {
      return;
    }
    if (_locksInlineImageSize) {
      return;
    }
    setState(() {
      _cachedSize = next;
    });
  }

  bool get _locksInlineImageSize =>
      widget.resourceLayoutPolicy.lockInlineImageSizeForCurrentBuild;

  Size? _hintSize() {
    final hint = widget.layoutHint;
    if (hint == null) {
      return null;
    }
    final size = Size(hint.width, hint.height);
    return size.width.isFinite &&
            size.height.isFinite &&
            size.width > 0 &&
            size.height > 0
        ? size
        : null;
  }

  Size? _inlineImageOriginalSize(ThreadPostInlineImage image) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    if (width != null &&
        height != null &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0) {
      return Size(width, height);
    }
    return null;
  }
}

final RegExp _discuzEditStatusPattern = RegExp(
  r'^本帖最后由\s*.+?\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑$',
);

class ThreadPostImageBlockView extends ConsumerStatefulWidget {
  const ThreadPostImageBlockView({
    super.key,
    required this.document,
    required this.image,
    required this.images,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.blockImageCacheRequestBuilder,
    this.imageOpenContext,
    this.resourceLayoutHints = ThreadPostResourceLayoutHints.empty,
    this.style = ThreadPostBodyStyle.defaults,
    this.resourceLayoutPolicy = ThreadPostResourceLayoutPolicy.defaults,
    this.onOpenImage,
    this.onOpenImages,
    this.diagnosticRecorder = const NoopThreadDetailDiagnosticRecorder(),
    @visibleForTesting this.imageProviderOverride,
  });

  final ThreadPostBodyDocument document;
  final ThreadPostImageBlock image;
  final List<ThreadPostImageBlock> images;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ThreadPostBlockImageCacheRequestBuilder? blockImageCacheRequestBuilder;
  final ThreadImageOpenContext? imageOpenContext;
  final ThreadPostResourceLayoutHints resourceLayoutHints;
  final ThreadPostBodyStyle style;
  final ThreadPostResourceLayoutPolicy resourceLayoutPolicy;
  final ThreadPostImageOpenHandler? onOpenImage;
  final void Function(List<ThreadPostImageBlock> images, int initialIndex)?
  onOpenImages;
  final ThreadDetailDiagnosticRecorder diagnosticRecorder;
  final ImageProvider? imageProviderOverride;

  @override
  ConsumerState<ThreadPostImageBlockView> createState() =>
      _ThreadPostImageBlockViewState();
}

class _ThreadPostImageBlockViewState
    extends ConsumerState<ThreadPostImageBlockView> {
  static const Duration _loadingIndicatorDelay = Duration(milliseconds: 350);
  static const ContinuousImageLayoutResolver _continuousImageLayoutResolver =
      ContinuousImageLayoutResolver();
  static const ContinuousImageViewportResolver _viewportResolver =
      ContinuousImageViewportResolver();
  static const ThreadPostContinuousImageAdapter _continuousImageAdapter =
      ThreadPostContinuousImageAdapter();
  static const ThreadImageReaderContinuousImageAdapter
  _threadImageReaderAdapter = ThreadImageReaderContinuousImageAdapter();

  double? _resolvedAspectRatio;
  double? _cachedAspectRatio;
  String? _loadedCacheKey;
  String? _lastBuiltDiagnosticItemId;
  String? _lastPlaceholderDiagnosticKey;

  @override
  void initState() {
    super.initState();
    if (!_locksImageAspectRatio) {
      _loadCachedAspectRatio();
    }
  }

  @override
  void didUpdateWidget(covariant ThreadPostImageBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.url != widget.image.url) {
      _resolvedAspectRatio = null;
      _cachedAspectRatio = null;
      _loadedCacheKey = null;
      if (!_locksImageAspectRatio) {
        _loadCachedAspectRatio();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _cacheRequest();
    final continuousItem = _continuousImageItem(request);
    final aspectRatio = _resolveAspectRatio(continuousItem);
    _recordBuiltIfNeeded(continuousItem);
    _recordPlaceholderIfNeeded(continuousItem, aspectRatio);
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
              child: CachedLibraryImage(
                request: request,
                imageProviderOverride: widget.imageProviderOverride,
                fit: widget.style.imageFit,
                placeholder: const _ThreadPostDelayedLoadingPlaceholder(
                  delay: _loadingIndicatorDelay,
                ),
                errorPlaceholder: const _ThreadPostImageErrorPlaceholder(
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
    _recordContinuousImage(
      ContinuousImageDiagnosticEventType.imageOpened,
      item: _continuousImageItem(_cacheRequest()),
      message: 'open initialIndex=$resolvedIndex',
    );
    final imageHandler = widget.onOpenImage;
    if (imageHandler != null) {
      imageHandler(
        ThreadPostImageOpenRequest(
          document: widget.document,
          images: widget.images,
          image: widget.image,
          initialIndex: resolvedIndex,
          readerRequest: _readerRequest(resolvedIndex),
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

  ThreadImageOpenRequest? _readerRequest(int initialIndex) {
    final context = widget.imageOpenContext;
    if (context == null) {
      return null;
    }
    final entries = widget.images
        .map((image) {
          return ThreadPostImageEntry(
            url: image.url,
            rawUrl: image.rawUrl,
            indexInPost: image.index,
            cacheKey: context.cacheKeyForImage(image),
            aid: image.aid,
            layoutHint: widget.resourceLayoutHints.blockImage(image),
          );
        })
        .toList(growable: false);
    final group = ThreadPostImageGroup(
      tid: context.tid,
      pid: context.pid,
      postNumber: context.postNumber,
      entries: entries,
    );
    final request = ThreadImageOpenRequest(
      tid: context.tid,
      pid: context.pid,
      postNumber: context.postNumber,
      referer: context.referer,
      group: group,
      initialIndex: initialIndex,
    );
    return ThreadImageOpenRequest(
      tid: request.tid,
      pid: request.pid,
      postNumber: request.postNumber,
      referer: request.referer,
      group: request.group,
      initialIndex: request.initialIndex,
      continuousImages: _threadImageReaderAdapter.mapRequest(
        request,
        fallbackAspectRatio: widget.style.imageFallbackAspectRatio,
        spacingAfter: widget.style.blockSpacing,
      ),
    );
  }

  void _handleImageResolved(Size size) {
    if (_locksImageAspectRatio) {
      return;
    }
    final width = size.width;
    final height = size.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final next = width / height;
    final item = _continuousImageItem(_cacheRequest());
    _recordContinuousImage(
      ContinuousImageDiagnosticEventType.imageDecodeResolved,
      item: item,
      width: width.round(),
      height: height.round(),
      aspectRatio: next,
      message: 'decoded block image',
    );
    if (_resolvedAspectRatio == next) {
      return;
    }
    if (_shouldDeferAspectRatioUpdate()) {
      _recordContinuousImage(
        ContinuousImageDiagnosticEventType
            .imageAspectRatioDeferredAboveViewport,
        item: item,
        width: width.round(),
        height: height.round(),
        aspectRatio: next,
        message: 'defer because image is above viewport',
      );
      return;
    }
    setState(() {
      _resolvedAspectRatio = next;
    });
    _recordContinuousImage(
      ContinuousImageDiagnosticEventType.imageAspectRatioApplied,
      item: item,
      width: width.round(),
      height: height.round(),
      aspectRatio: next,
      message: 'apply decoded aspect ratio',
    );
  }

  Future<void> _loadCachedAspectRatio() async {
    if (_locksImageAspectRatio) {
      return;
    }
    final request = _cacheRequest();
    final cacheKey = request.cacheKey.trim();
    if (cacheKey.isEmpty || _loadedCacheKey == cacheKey) {
      return;
    }
    _loadedCacheKey = cacheKey;
    final result = await ref
        .read(imageCacheServiceProvider)
        .getCached(cacheKey);
    if (!mounted || _loadedCacheKey != cacheKey || result == null) {
      return;
    }
    final width = result.width;
    final height = result.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return;
    }
    final next = width / height;
    if (next == _cachedAspectRatio) {
      return;
    }
    if (_locksImageAspectRatio) {
      return;
    }
    // 与 decode 回填保持一致：视口上方的高度变化会把"已读楼层"顶走，造成上滑
    // 回溯。此处补齐 above-viewport 保护，缓存比例只在图片仍处于/低于视口时应用。
    if (_shouldDeferAspectRatioUpdate()) {
      _recordContinuousImage(
        ContinuousImageDiagnosticEventType
            .imageAspectRatioDeferredAboveViewport,
        item: _continuousImageItem(request),
        width: width,
        height: height,
        aspectRatio: next,
        message: 'defer cached ratio because image is above viewport',
      );
      return;
    }
    setState(() {
      _cachedAspectRatio = next;
    });
  }

  bool get _locksImageAspectRatio {
    if (widget.resourceLayoutPolicy.lockImageAspectRatioForCurrentBuild) {
      return true;
    }
    // 当 plan 阶段已把可信尺寸（HTML/缓存）hydrate 进 hint 并标记锁定时，逐图锁定
    // 首帧高度，无需依赖全局策略——这样无尺寸图片仍可走受保护的 decode 回填。
    final hint = widget.resourceLayoutHints.blockImage(widget.image);
    return hint?.lockForCurrentBuild ?? false;
  }

  bool _shouldDeferAspectRatioUpdate() {
    if (!widget
        .resourceLayoutPolicy
        .deferImageAspectRatioUpdateWhenAboveViewport) {
      return false;
    }
    return _viewportResolver.isAboveViewport(context);
  }

  double _resolveAspectRatio(ContinuousImageItem item) {
    if (_locksImageAspectRatio) {
      return _continuousImageLayoutResolver
          .resolveInitialHint(item: item)
          .aspectRatio;
    }
    final decoded = _resolvedAspectRatio;
    if (decoded != null && decoded.isFinite && decoded > 0) {
      return _continuousImageLayoutResolver
          .resolveDecodedHint(width: (decoded * 1000).round(), height: 1000)!
          .aspectRatio;
    }
    final cached = _cachedAspectRatio;
    if (cached != null && cached.isFinite && cached > 0) {
      final hint = _continuousImageLayoutResolver.resolveFromDimensions(
        ContinuousImageDimensionCandidate(
          width: (cached * 1000).round(),
          height: 1000,
          source: ContinuousImageDimensionSource.persistedCache,
        ),
      );
      if (hint != null) {
        return hint.aspectRatio;
      }
    }
    return _continuousImageLayoutResolver
        .resolveInitialHint(item: item)
        .aspectRatio;
  }

  ContinuousImageItem _continuousImageItem(ImageCacheRequest request) {
    final ownerId = widget.imageCacheOwnerId?.trim();
    return _continuousImageAdapter.mapBlockImage(
      ownerId: ownerId == null || ownerId.isEmpty ? 'unknown' : ownerId,
      image: widget.image,
      cacheKey: request.cacheKey,
      fallbackAspectRatio: _validAspectRatio(
        widget.style.imageFallbackAspectRatio,
      ),
      spacingAfter: widget.style.blockSpacing,
      layoutHint: widget.resourceLayoutHints.blockImage(widget.image),
      includeContentDefaultHint: _locksImageAspectRatio,
    );
  }

  void _recordBuiltIfNeeded(ContinuousImageItem item) {
    if (_lastBuiltDiagnosticItemId == item.id) {
      return;
    }
    _lastBuiltDiagnosticItemId = item.id;
    _recordContinuousImage(
      ContinuousImageDiagnosticEventType.imageItemBuilt,
      item: item,
      message: 'build thread block image',
    );
  }

  void _recordPlaceholderIfNeeded(
    ContinuousImageItem item,
    double aspectRatio,
  ) {
    final key = '${item.id}:${aspectRatio.toStringAsFixed(4)}';
    if (_lastPlaceholderDiagnosticKey == key) {
      return;
    }
    _lastPlaceholderDiagnosticKey = key;
    _recordContinuousImage(
      ContinuousImageDiagnosticEventType.imagePlaceholderLaidOut,
      item: item,
      aspectRatio: aspectRatio,
      message: 'layout block image placeholder',
    );
  }

  void _recordContinuousImage(
    ContinuousImageDiagnosticEventType type, {
    required ContinuousImageItem item,
    double? aspectRatio,
    int? width,
    int? height,
    String message = '',
  }) {
    final recorder = widget.diagnosticRecorder;
    if (!recorder.enabled) {
      return;
    }
    recorder.recordContinuousImage(
      ContinuousImageDiagnosticEvent(
        time: DateTime.now(),
        type: type,
        itemId: item.id,
        ownerId: item.ownerId,
        index: item.index,
        source: item.sourceKind.name,
        aspectRatio: aspectRatio,
        width: width,
        height: height,
        message: message,
      ),
    );
  }

  double _validAspectRatio(double value) {
    return value.isFinite && value > 0
        ? value
        : ThreadPostBodyStyle.defaults.imageFallbackAspectRatio;
  }

  ImageCacheRequest _cacheRequest() {
    final builder = widget.blockImageCacheRequestBuilder;
    if (builder != null) {
      return builder(widget.image);
    }
    final ownerId = widget.imageCacheOwnerId?.trim();
    return ForumImageCacheRequests.threadInline(
      tid: ownerId == null || ownerId.isEmpty ? 'unknown' : ownerId,
      url: widget.image.url,
      imageIndex: widget.image.index,
    );
  }
}

class _ThreadPostImageSurface extends StatelessWidget {
  const _ThreadPostImageSurface({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _ThreadPostDelayedLoadingPlaceholder extends StatefulWidget {
  const _ThreadPostDelayedLoadingPlaceholder({required this.delay});

  final Duration delay;

  @override
  State<_ThreadPostDelayedLoadingPlaceholder> createState() =>
      _ThreadPostDelayedLoadingPlaceholderState();
}

class _ThreadPostDelayedLoadingPlaceholderState
    extends State<_ThreadPostDelayedLoadingPlaceholder> {
  Timer? _timer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showSpinner = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ThreadPostImageSurface(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _showSpinner
            ? IgnorePointer(
                key: const Key('thread-post-image-loading-spinner'),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('thread-post-image-idle')),
      ),
    );
  }
}

class _ThreadPostImageErrorPlaceholder extends StatelessWidget {
  const _ThreadPostImageErrorPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ThreadPostImageSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 20, color: scheme.onSurfaceVariant)],
      ),
    );
  }
}
