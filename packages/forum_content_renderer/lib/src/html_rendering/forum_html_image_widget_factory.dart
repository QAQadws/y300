import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import '../helpers/forum_html_image_presentation.dart';
import 'forum_html_prepared_render_document.dart';
import 'forum_html_render_callbacks.dart';
import 'widgets/forum_html_image_view.dart';
import '../services/forum_html_image_viewport_coordinator.dart';
import '../services/forum_html_image_anchor_controller.dart';
import '../services/forum_html_body_presentation.dart';

typedef ForumHtmlImageFactoryBinding = ({
  ForumHtmlImageHost? host,
  ForumHtmlImageViewportCoordinator? viewport,
  bool handlesImageTap,
  ForumHtmlImageAnchorController? imageAnchors,
  Object? imageAnchorRevision,
  String sourceId,
});

/// A fresh factory is required for each HTML body: image numbering is local.
class ForumHtmlImageWidgetFactory extends WidgetFactory {
  ForumHtmlImageWidgetFactory({
    required this.binding,
    this.bodyPresentationFor,
    this.textAlignFor,
    this.onImageResolved,
    this.onTapImageRequest,
    this.onImageLayoutShift,
    this.onBodyBuilt,
    this.readableImageKeyPrefix,
    this.hasTrailingContentFor,
  });

  final ValueListenable<ForumHtmlImageFactoryBinding> binding;
  final ForumHtmlBodyPresentation? Function()? bodyPresentationFor;
  final TextAlign? Function()? textAlignFor;
  final VoidCallback? onBodyBuilt;
  final ValueChanged<Size>? onImageResolved;
  final void Function(ForumHtmlImageRequest request)? onTapImageRequest;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final String? readableImageKeyPrefix;
  final bool Function()? hasTrailingContentFor;
  var _nextImageIndex = 0;

  @override
  Iterable<dynamic> getDependencies(BuildContext context) {
    final alignment = textAlignFor?.call();
    return [...super.getDependencies(context), ?alignment];
  }

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    if (hasTrailingContentFor?.call() == true && child is Column) {
      // fwfh trims the root trailing margin. An interior display fragment must
      // retain that real CSS margin, so put a zero-size flow item after it.
      child = Column(
        mainAxisSize: child.mainAxisSize,
        mainAxisAlignment: child.mainAxisAlignment,
        crossAxisAlignment: child.crossAxisAlignment,
        textDirection: child.textDirection,
        verticalDirection: child.verticalDirection,
        textBaseline: child.textBaseline,
        children: [...child.children, const SizedBox.shrink()],
      );
    }
    final body = super.buildBodyWidget(context, child);
    onBodyBuilt?.call();
    return body;
  }

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url.trim();
    if (url.startsWith('asset:') ||
        url.startsWith('data:image/') ||
        url.startsWith('file:')) {
      return _fallback(tree, src);
    }
    final resolved = urlFull(url);
    final uri = resolved == null ? null : Uri.tryParse(resolved);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _fallback(tree, src);
    }
    final isSticker = _isSticker(resolved!);
    final readableIndex = _readableIndex(tree);
    final imageIndex = isSticker ? null : readableIndex ?? _nextImageIndex++;
    final htmlSize = _explicitSize(src);
    return ValueListenableBuilder<ForumHtmlImageFactoryBinding>(
      // fwfh caches this widget per DOM image. A table can insert/remove a
      // scroll wrapper during width measurement, so its image binding must
      // survive reparenting. Each DOM slot owns a key, including repeated URLs.
      key: _hasTableAncestor(tree.element) ? GlobalKey() : null,
      valueListenable: binding,
      builder: (context, binding, child) {
        final host = binding.host;
        if (host == null) {
          return _fallback(tree, src) ?? const SizedBox.shrink();
        }
        final image = host.resolveImage(
          url: uri,
          imageIndex: imageIndex,
          isSticker: isSticker,
          htmlSize: htmlSize,
        );
        if (image == null) {
          return _fallback(tree, src) ?? const SizedBox.shrink();
        }
        final presentation = isSticker ? bodyPresentationFor?.call() : null;
        final child = ForumHtmlImageView(
          host: host,
          image: image,
          initialInlineSize: presentation?.inlineImageSizeFor(image.identity),
          rememberInlineSize: presentation == null
              ? null
              : (size) =>
                    presentation.recordInlineImageSize(image.identity, size),
          onImageResolved: onImageResolved,
          onImageLayoutShift: onImageLayoutShift,
          viewportCoordinator: isSticker ? null : binding.viewport,
        );
        return _wrapTap(
          child,
          enabled: binding.handlesImageTap,
          image: image,
          src: src,
          element: tree.element,
          readableIndex: readableIndex,
          isSticker: isSticker,
          binding: binding,
        );
      },
    );
  }

  bool _hasTableAncestor(html_dom.Element element) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'table') return true;
    }
    return false;
  }

  Widget? _fallback(BuildTree tree, ImageSource src) {
    final fallback = super.buildImageWidget(tree, src);
    if (fallback == null) return null;
    return ValueListenableBuilder<ForumHtmlImageFactoryBinding>(
      valueListenable: binding,
      child: forumHtmlClipImage(fallback),
      builder: (context, binding, child) => _wrapTap(
        child!,
        enabled: binding.handlesImageTap,
        src: src,
        element: tree.element,
        readableIndex: _readableIndex(tree),
        isSticker: _isSticker(urlFull(src.url) ?? src.url),
        binding: binding,
      ),
    );
  }

  Widget _wrapTap(
    Widget child, {
    required bool enabled,
    ForumHtmlDisplayImage? image,
    required ImageSource src,
    required html_dom.Element element,
    required int? readableIndex,
    required bool isSticker,
    required ForumHtmlImageFactoryBinding binding,
  }) {
    final callback = onTapImageRequest;
    final gesture = GestureDetector(
      key: readableIndex == null
          ? null
          : Key(
              '${readableImageKeyPrefix ?? 'thread-post-html-first-readable-image'}-$readableIndex',
            ),
      behavior: HitTestBehavior.opaque,
      onTap: !enabled || callback == null
          ? null
          : () => callback(
              ForumHtmlImageRequest(
                url: image?.sourceUrl ?? urlFull(src.url) ?? src.url,
                alt: src.image?.alt,
                title: src.image?.title,
                width: src.width,
                height: src.height,
                isSticker: isSticker,
                attachmentId: _attachmentIdFromElement(element),
                readableIndex: readableIndex,
                cacheKey: image?.cacheKey,
              ),
            ),
      child: child,
    );
    final anchors = binding.imageAnchors;
    if (image == null || readableIndex == null || isSticker) {
      return gesture;
    }
    return ForumHtmlImageAnchor(
      controller: anchors,
      sourceId: binding.sourceId,
      index: readableIndex,
      cacheKey: image.cacheKey,
      url: image.sourceUrl,
      child: gesture,
    );
  }

  int? _readableIndex(BuildTree tree) {
    final raw = tree.element.attributes[forumHtmlReadableImageIndexAttribute];
    final parsed = int.tryParse(raw?.trim() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }

  Size? _explicitSize(ImageSource src) {
    final width = src.width;
    final height = src.height;
    if (width == null || height == null) return null;
    final size = Size(width, height);
    return forumHtmlValidImageSize(size) ? size : null;
  }

  bool _isSticker(String url) =>
      url.contains('/static/image/smiley/') ||
      url.contains('static/image/smiley/');

  String? _attachmentIdFromElement(html_dom.Element element) {
    final aimgMatch = RegExp(r'^aimg_(\d+)$').firstMatch(element.id);
    if (aimgMatch != null) return aimgMatch.group(1);
    final aid = element.attributes['aid']?.trim();
    if (aid != null && aid.isNotEmpty) return aid;
    final src = DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      domAttributes: const [
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ],
    );
    if (src == null) return null;
    return RegExp(r'aimg[_=/-](\d+)').firstMatch(src)?.group(1) ??
        RegExp(r'(?:aid|attachmentid)=(\d+)').firstMatch(src)?.group(1);
  }
}
