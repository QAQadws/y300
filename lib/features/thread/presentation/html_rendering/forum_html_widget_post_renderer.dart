import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_cached_image_widget_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_image_deduplicator.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/widgets/forum_collapse_block.dart';

class ForumHtmlWidgetPostRenderer extends StatelessWidget {
  const ForumHtmlWidgetPostRenderer({
    super.key,
    required this.html,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.preferences,
    this.sourceId,
    this.threadId,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.imageRequestResolver,
    this.imageDimensionIndex,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.preparedDocument,
    this.contentImageKind = ForumImageKind.threadInline,
  });

  static final Uri forumBaseUri = Uri.parse('https://bbs.yamibo.com/');

  final String html;
  final ForumHtmlRenderCallbacks callbacks;
  final ForumHtmlReaderPreferences? preferences;
  final String? sourceId;
  final String? threadId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ForumImageRequestResolver? imageRequestResolver;
  final ForumImageDimensionIndex? imageDimensionIndex;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumHtmlPreparedRenderDocument? preparedDocument;
  final ForumImageKind contentImageKind;
  static const _imageDeduplicator = ForumHtmlImageDeduplicator();

  @override
  Widget build(BuildContext context) {
    final resolvedPreferences =
        preferences ?? ForumHtmlReaderPreferences.defaults();
    final stylePolicy = ForumHtmlStylePolicy(resolvedPreferences);
    final document = preparedDocument;
    final preparedHtml =
        document?.preparedHtml ??
        _imageDeduplicator.deduplicateAttachmentImages(
          stylePolicy.prepareHtml(html),
        );
    final imageAttachmentIdsByUrl =
        document?.attachmentIdsByUrl ??
        _collectImageAttachmentIds(preparedHtml);
    final handlesImageTapInFactory = threadId?.trim().isNotEmpty == true;
    return HtmlWidget(
      preparedHtml,
      key: Key('forum-html-renderer-${sourceId ?? 'anonymous'}'),
      baseUrl: forumBaseUri,
      customStylesBuilder: stylePolicy.customStylesFor,
      customWidgetBuilder: (element) =>
          _buildCustomWidget(element, stylePolicy, resolvedPreferences),
      factoryBuilder: _cachedImageFactoryBuilder(),
      renderMode: RenderMode.column,
      textStyle: stylePolicy.baseTextStyle(context),
      onTapUrl: callbacks.onTapUrl,
      onTapImage: handlesImageTapInFactory
          ? null
          : (image) => _handleTapImage(image, imageAttachmentIdsByUrl),
    );
  }

  WidgetFactory Function()? _cachedImageFactoryBuilder() {
    final tid = threadId?.trim();
    if (tid == null || tid.isEmpty) {
      return null;
    }
    return () => ForumHtmlCachedImageWidgetFactory(
      threadId: tid,
      imageHeaderBuilder: imageHeaderBuilder,
      imageCacheOwnerId: imageCacheOwnerId,
      onTapImageRequest: callbacks.onTapImage,
      onImageLayoutShift: callbacks.onImageLayoutShift,
      readableImageKeyPrefix: sourceId == null
          ? null
          : 'thread-post-html-first-readable-image-$sourceId',
      contentImageKind: contentImageKind,
      imageRequestResolver: imageRequestResolver,
      imageDimensionIndex: imageDimensionIndex,
      fallbackAspectRatioFor: imageFallbackAspectRatioFor,
      onBlockImageResolved: onBlockImageResolved,
    );
  }

  Widget? _buildCustomWidget(
    html_dom.Element element,
    ForumHtmlStylePolicy stylePolicy,
    ForumHtmlReaderPreferences resolvedPreferences,
  ) {
    if (stylePolicy.isDiscuzEditStatusElement(element)) {
      return _DiscuzEditStatusText(
        text: element.text.trim(),
        baseStyle: stylePolicy.baseTextStyle,
      );
    }
    if (!stylePolicy.isForumCollapseElement(element)) {
      return null;
    }

    final collapseId = _collapseSourceId(element);
    return ForumCollapseBlock(
      titleHtml:
          _firstChildWithClass(element, 'showcollapse_title')?.innerHtml ??
          '折叠内容',
      contentHtml: _collapseContentHtml(element),
      initiallyExpanded: stylePolicy.isForumCollapseInitiallyExpanded(element),
      sourceId: collapseId,
      nestedRendererBuilder: (html, {required sourceId}) {
        return ForumHtmlWidgetPostRenderer(
          html: html,
          callbacks: callbacks,
          preferences: resolvedPreferences,
          sourceId: sourceId,
          threadId: threadId,
          imageHeaderBuilder: imageHeaderBuilder,
          imageCacheOwnerId: imageCacheOwnerId,
          imageRequestResolver: imageRequestResolver,
          imageDimensionIndex: imageDimensionIndex,
          imageFallbackAspectRatioFor: imageFallbackAspectRatioFor,
          onBlockImageResolved: onBlockImageResolved,
          contentImageKind: contentImageKind,
          preparedDocument: preparedDocument?.copyWith(preparedHtml: html),
        );
      },
    );
  }

  String _collapseContentHtml(html_dom.Element element) {
    final content = _firstChildWithClass(element, 'showcollapse_content');
    if (content == null) {
      return '';
    }
    final clone = html_parser.parseFragment(content.innerHtml);
    for (final gather in clone.querySelectorAll('.showcollapse_gather')) {
      gather.remove();
    }
    return clone.nodes.map(_serializeNode).join();
  }

  html_dom.Element? _firstChildWithClass(
    html_dom.Element element,
    String className,
  ) {
    for (final child in element.children) {
      if (child.classes.contains(className)) {
        return child;
      }
    }
    return null;
  }

  String _collapseSourceId(html_dom.Element element) {
    final id = element.id;
    if (id.isNotEmpty) {
      return '${sourceId ?? 'anonymous'}-$id';
    }
    final title = _firstChildWithClass(element, 'showcollapse_title');
    final titleText = title?.text.trim();
    if (titleText != null && titleText.isNotEmpty) {
      return '${sourceId ?? 'anonymous'}-${_stableHash(titleText)}';
    }
    return '${sourceId ?? 'anonymous'}-${_stableHash(element.outerHtml)}';
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }

  Map<String, String> _collectImageAttachmentIds(String html) {
    final result = <String, String>{};
    final fragment = html_parser.parseFragment(html);
    for (final image in fragment.querySelectorAll('img')) {
      final src = image.attributes['src'];
      if (src == null || src.isEmpty) {
        continue;
      }
      final attachmentId = _attachmentIdFromElement(image);
      if (attachmentId == null) {
        continue;
      }
      result[src] = attachmentId;
      result[forumBaseUri.resolve(src).toString()] = attachmentId;
    }
    return result;
  }

  String? _attachmentIdFromElement(html_dom.Element element) {
    final id = element.id;
    final aimgMatch = RegExp(r'^aimg_(\d+)$').firstMatch(id);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final src = element.attributes['src'];
    return src == null ? null : _attachmentIdFromUrl(src);
  }

  void _handleTapImage(
    ImageMetadata image,
    Map<String, String> imageAttachmentIdsByUrl,
  ) {
    final callback = callbacks.onTapImage;
    if (callback == null || image.sources.isEmpty) {
      return;
    }
    final source = image.sources.first;
    callback(
      ForumHtmlImageRequest(
        url: source.url,
        alt: image.alt,
        title: image.title,
        width: source.width,
        height: source.height,
        isSticker: _isForumStickerImage(source.url),
        attachmentId:
            imageAttachmentIdsByUrl[source.url] ??
            _attachmentIdFromUrl(source.url),
        kind: _isForumStickerImage(source.url)
            ? ForumImageKind.remoteSmiley
            : null,
      ),
    );
  }

  bool _isForumStickerImage(String url) {
    return url.contains('/static/image/smiley/') ||
        url.contains('static/image/smiley/');
  }

  String? _attachmentIdFromUrl(String url) {
    final aimgMatch = RegExp(r'aimg[_=/-](\d+)').firstMatch(url);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final aidMatch = RegExp(r'(?:aid|attachmentid)=(\d+)').firstMatch(url);
    return aidMatch?.group(1);
  }
}

class _DiscuzEditStatusText extends StatelessWidget {
  const _DiscuzEditStatusText({required this.text, required this.baseStyle});

  final String text;
  final TextStyle Function(BuildContext context) baseStyle;

  @override
  Widget build(BuildContext context) {
    final source = baseStyle(context);
    final fallback = DefaultTextStyle.of(context).style;
    final baseFontSize = source.fontSize ?? fallback.fontSize;
    final baseColor =
        source.color ??
        fallback.color ??
        Theme.of(context).colorScheme.onSurface;
    return Text(
      text,
      key: const Key('forum-html-discuz-edit-status'),
      style: source.copyWith(
        fontSize: baseFontSize == null ? null : baseFontSize * 0.88,
        fontStyle: FontStyle.italic,
        color: baseColor.withValues(alpha: 0.62),
      ),
    );
  }
}
