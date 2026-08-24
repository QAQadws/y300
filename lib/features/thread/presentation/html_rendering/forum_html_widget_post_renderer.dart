import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_cached_image_widget_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/widgets/forum_collapse_block.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumHtmlWidgetPostRenderer extends StatelessWidget {
  const ForumHtmlWidgetPostRenderer({
    super.key,
    required this.html,
    required this.theme,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.preferences,
    this.buildAsync,
    this.enableCaching,
    this.sourceId,
    this.threadId,
    this.imageReferer,
    this.imageCacheOwnerId,
    this.imageRequestResolver,
    this.imageDimensionIndex,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.preparedDocument,
    this.contentImageKind = ForumImageKind.threadInline,
    this.blockSpacingMode = ForumHtmlBlockSpacingMode.paragraphLikeDivs,
  });

  static final Uri forumBaseUri = Uri.parse('https://bbs.yamibo.com/');

  final String html;
  final ForumHtmlThemeContext theme;
  final ForumHtmlRenderCallbacks callbacks;
  final ForumHtmlReaderPreferences? preferences;
  final bool? buildAsync;
  final bool? enableCaching;
  final String? sourceId;
  final String? threadId;
  final String? imageReferer;
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
  final ForumHtmlBlockSpacingMode blockSpacingMode;

  @override
  Widget build(BuildContext context) {
    final resolvedPreferences =
        preferences ?? ForumHtmlReaderPreferences.defaults();
    final stylePolicy = ForumHtmlStylePolicy(
      resolvedPreferences,
      theme: theme,
      blockSpacingMode: blockSpacingMode,
    );
    final document =
        preparedDocument ??
        const DefaultForumHtmlRenderPreparer().prepare(
          html: html,
          preferences: resolvedPreferences,
          theme: theme,
          sourceId: sourceId ?? 'anonymous',
          threadId: threadId,
          imageCacheOwnerId: imageCacheOwnerId,
        );
    final themeMatches = document.themeSignature == theme.signature;
    assert(
      themeMatches,
      'Forum HTML prepared document theme mismatch for '
      '${sourceId ?? 'anonymous'}.',
    );
    if (!themeMatches) {
      return const SizedBox.shrink(
        key: Key('forum-html-renderer-theme-mismatch'),
      );
    }
    final preparedHtml = document.preparedHtml;
    final imageAttachmentIdsByUrl = document.attachmentIdsByUrl;
    final handlesImageTapInFactory = threadId?.trim().isNotEmpty == true;
    return HtmlWidget(
      preparedHtml,
      key: Key('forum-html-renderer-${sourceId ?? 'anonymous'}'),
      baseUrl: forumBaseUri,
      buildAsync: buildAsync,
      customStylesBuilder: stylePolicy.customStylesFor,
      customWidgetBuilder: (element) => _buildCustomWidget(
        context,
        element,
        stylePolicy,
        resolvedPreferences,
        document,
      ),
      factoryBuilder: _cachedImageFactoryBuilder(),
      enableCaching: enableCaching,
      renderMode: RenderMode.column,
      textStyle: stylePolicy.baseTextStyle(context),
      onTapUrl: callbacks.onTapUrl == null
          ? null
          : (url) {
              callbacks.onInteraction?.call();
              return callbacks.onTapUrl!(url);
            },
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
      imageReferer: imageReferer,
      imageCacheOwnerId: imageCacheOwnerId,
      onTapImageRequest: callbacks.onTapImage == null
          ? null
          : (request) {
              callbacks.onInteraction?.call();
              callbacks.onTapImage!(request);
            },
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
    BuildContext context,
    html_dom.Element element,
    ForumHtmlStylePolicy stylePolicy,
    ForumHtmlReaderPreferences resolvedPreferences,
    ForumHtmlPreparedRenderDocument document,
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
          AppLocalizations.of(context).threadHtmlCollapseContent,
      contentHtml: _collapseContentHtml(element),
      initiallyExpanded: stylePolicy.isForumCollapseInitiallyExpanded(element),
      sourceId: collapseId,
      onInteraction: callbacks.onInteraction,
      nestedRendererBuilder: (html, {required sourceId}) {
        return ForumHtmlWidgetPostRenderer(
          html: html,
          theme: theme,
          callbacks: callbacks,
          preferences: resolvedPreferences,
          buildAsync: buildAsync,
          enableCaching: enableCaching,
          sourceId: sourceId,
          threadId: threadId,
          imageReferer: imageReferer,
          imageCacheOwnerId: imageCacheOwnerId,
          imageRequestResolver: imageRequestResolver,
          imageDimensionIndex: imageDimensionIndex,
          imageFallbackAspectRatioFor: imageFallbackAspectRatioFor,
          onBlockImageResolved: onBlockImageResolved,
          contentImageKind: contentImageKind,
          blockSpacingMode: blockSpacingMode,
          preparedDocument: document.copyWith(preparedHtml: html),
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

  void _handleTapImage(
    ImageMetadata image,
    Map<String, String> imageAttachmentIdsByUrl,
  ) {
    final callback = callbacks.onTapImage;
    if (callback == null || image.sources.isEmpty) {
      return;
    }
    callbacks.onInteraction?.call();
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        key: const Key('forum-html-discuz-edit-status'),
        style: source.copyWith(
          fontSize: baseFontSize == null ? null : baseFontSize * 0.88,
          fontStyle: FontStyle.italic,
          color: baseColor.withValues(alpha: 0.62),
        ),
      ),
    );
  }
}
