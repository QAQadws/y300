import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/forum_html_image_widget_factory.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_image_host_provider.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_content_layout.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_render_preparer.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/widgets/forum_collapse_block.dart';
import 'package:y300/features/content_rendering_shared/presentation/services/forum_html_image_viewport_coordinator.dart';
import 'package:y300/features/content_rendering_shared/presentation/services/forum_html_body_presentation.dart';
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
    this.renderMode = RenderMode.column,
    this.onBodyBuilt,
    this.bodyPresentation,
    this.collapseExpansion,
    this.sourceId,
    this.threadId,
    this.imageReferer,
    this.imageCacheOwnerId,
    this.imageRequestResolver,
    this.imageDimensionIndex,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.imageViewportCoordinator,
    this.imagePrecacheService,
    this.imageHost,
    this.preparedDocument,
    this.contentImageKind = ForumImageKind.threadInline,
    this.blockSpacingMode = ForumHtmlBlockSpacingMode.paragraphLikeDivs,
    this.linkBaseUri,
    this.contentLayout = ForumHtmlContentLayout.document,
  });

  static final Uri forumBaseUri = Uri.parse('https://bbs.yamibo.com/');

  final String html;
  final ForumHtmlThemeContext theme;
  final ForumHtmlRenderCallbacks callbacks;
  final ForumHtmlReaderPreferences? preferences;
  final bool? buildAsync;
  final bool? enableCaching;

  /// Only the outer chapter may be a sliver; nested collapse content stays a box.
  final RenderMode renderMode;
  final VoidCallback? onBodyBuilt;
  final ForumHtmlBodyPresentation? bodyPresentation;

  /// Chapter-owned expansion memory when offscreen sliver children unmount.
  final Map<String, bool>? collapseExpansion;
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
  final ForumHtmlImageViewportCoordinator? imageViewportCoordinator;
  final ForumImagePrecacheService? imagePrecacheService;

  /// Explicit display port; default cache configuration stays in the App facade.
  final ForumHtmlImageHost? imageHost;
  final ForumHtmlPreparedRenderDocument? preparedDocument;
  final ForumImageKind contentImageKind;
  final ForumHtmlBlockSpacingMode blockSpacingMode;
  final ForumHtmlContentLayout contentLayout;

  /// The current source document, so fragment links retain article identity.
  final Uri? linkBaseUri;

  @override
  Widget build(BuildContext context) {
    final inheritedBinding = context
        .getInheritedWidgetOfExactType<_ForumHtmlInheritedHostBinding>()
        ?.binding;
    final resolvedPreferences =
        preferences ?? ForumHtmlReaderPreferences.defaults();
    final stylePolicy = ForumHtmlStylePolicy(
      resolvedPreferences,
      theme: theme,
      blockSpacingMode: blockSpacingMode,
      contentLayout: contentLayout,
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
    final handlesImageTapInFactory =
        inheritedBinding != null ||
        imageHost != null ||
        threadId?.trim().isNotEmpty == true;
    final presentation = bodyPresentation;
    final baseStyle = stylePolicy.baseTextStyle(context);
    Widget renderBody(
      VoidCallback? onReady,
      ForumHtmlImageHost? host,
      Object? hostRevision,
    ) {
      Widget render(ValueListenable<ForumHtmlImageFactoryBinding>? binding) =>
          HtmlWidget(
            preparedHtml,
            key: Key('forum-html-renderer-${sourceId ?? 'anonymous'}'),
            baseUrl: linkBaseUri ?? forumBaseUri,
            onErrorBuilder: onReady == null
                ? null
                : (_, _, _) {
                    onReady();
                    return null;
                  },
            buildAsync: buildAsync,
            customStylesBuilder: stylePolicy.customStylesFor,
            customWidgetBuilder: (element) => _buildCustomWidget(
              context,
              element,
              stylePolicy,
              resolvedPreferences,
              document,
              binding,
            ),
            factoryBuilder: _imageFactoryBuilder(onReady, binding),
            enableCaching: enableCaching,
            renderMode: renderMode,
            rebuildTriggers: [contentLayout, linkBaseUri],
            textStyle: baseStyle,
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
      if (inheritedBinding != null) return render(inheritedBinding);
      if (host == null) return render(null);
      return _ForumHtmlHostBinding(
        binding: (host: host, viewport: imageViewportCoordinator),
        revision: hostRevision,
        builder: render,
      );
    }

    Widget buildBody(VoidCallback? onReady) {
      if (inheritedBinding != null ||
          imageHost != null ||
          !handlesImageTapInFactory) {
        return renderBody(onReady, imageHost, (
          imageHost,
          imageViewportCoordinator,
        ));
      }
      final host =
          CacheForumHtmlImageHost.lazy(
            dimensionIndexFor: () => ProviderScope.containerOf(
              context,
              listen: false,
            ).read(forumHtmlImageHostProvider).dimensionIndex,
          ).forContent(
            threadId: threadId!,
            imageReferer: imageReferer,
            imageCacheOwnerId: imageCacheOwnerId,
            contentImageKind: contentImageKind,
            imageRequestResolver: imageRequestResolver,
            imageDimensionIndex: imageDimensionIndex,
            fallbackAspectRatioFor: imageFallbackAspectRatioFor,
            onBlockImageResolved: onBlockImageResolved,
            imagePrecacheService: imagePrecacheService,
          );
      return renderBody(onReady, host, (
        threadId,
        imageReferer,
        imageCacheOwnerId,
        contentImageKind,
        imageRequestResolver,
        imageDimensionIndex,
        imagePrecacheService,
        imageViewportCoordinator,
      ));
    }

    if (presentation == null || renderMode != RenderMode.column) {
      return buildBody(onBodyBuilt);
    }
    final revision = (
      preparedHtml,
      baseStyle,
      MediaQuery.textScalerOf(context),
      resolvedPreferences,
      theme.signature,
      contentLayout,
      linkBaseUri,
    );
    return ForumHtmlBodyLayout(
      key: ValueKey((presentation, revision)),
      presentation: presentation,
      sourceId: sourceId ?? 'anonymous',
      revision: revision,
      builder: (ready) => buildBody(() {
        ready();
        onBodyBuilt?.call();
      }),
    );
  }

  WidgetFactory Function()? _imageFactoryBuilder(
    VoidCallback? onReady,
    ValueListenable<ForumHtmlImageFactoryBinding>? binding,
  ) {
    if (binding == null) {
      return onReady == null ? null : () => _BodyReadyWidgetFactory(onReady);
    }
    return () => ForumHtmlImageWidgetFactory(
      binding: binding,
      onBodyBuilt: onReady,
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
    );
  }

  Widget? _buildCustomWidget(
    BuildContext context,
    html_dom.Element element,
    ForumHtmlStylePolicy stylePolicy,
    ForumHtmlReaderPreferences resolvedPreferences,
    ForumHtmlPreparedRenderDocument document,
    ValueListenable<ForumHtmlImageFactoryBinding>? imageBinding,
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
    final titleHtml =
        _firstChildWithClass(element, 'showcollapse_title')?.innerHtml ??
        AppLocalizations.of(context).threadHtmlCollapseContent;
    final contentHtml = _collapseContentHtml(element);
    Widget buildCollapse(BuildContext context) => ForumCollapseBlock(
      titleHtml: titleHtml,
      contentHtml: contentHtml,
      initiallyExpanded:
          collapseExpansion?[collapseId] ??
          stylePolicy.isForumCollapseInitiallyExpanded(element),
      onExpandedChanged: collapseExpansion == null
          ? null
          : (expanded) => collapseExpansion![collapseId] = expanded,
      sourceId: collapseId,
      onInteraction: callbacks.onInteraction,
      nestedRendererBuilder: (html, {required sourceId}) {
        final renderer = ForumHtmlWidgetPostRenderer(
          html: html,
          theme: theme,
          callbacks: callbacks,
          collapseExpansion: collapseExpansion,
          bodyPresentation: bodyPresentation,
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
          imageViewportCoordinator: imageViewportCoordinator,
          imagePrecacheService: imagePrecacheService,
          imageHost: imageHost,
          contentImageKind: contentImageKind,
          blockSpacingMode: blockSpacingMode,
          contentLayout: contentLayout,
          linkBaseUri: linkBaseUri,
          preparedDocument: document.copyWith(preparedHtml: html),
        );
        return imageBinding == null
            ? renderer
            : _ForumHtmlInheritedHostBinding(
                binding: imageBinding,
                child: renderer,
              );
      },
    );
    // HtmlWidget caches its widget tree. Re-read chapter-owned state when a
    // lazy sliver remounts this child instead of freezing the initial value.
    return collapseExpansion == null
        ? buildCollapse(context)
        : Builder(builder: buildCollapse);
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

/// fwfh keeps its initial factory. Update image bindings without remounting
/// the measured body or discarding a collapse block's local expansion state.
class _ForumHtmlHostBinding extends StatefulWidget {
  const _ForumHtmlHostBinding({
    required this.binding,
    required this.revision,
    required this.builder,
  });

  final ForumHtmlImageFactoryBinding binding;
  final Object? revision;
  final Widget Function(ValueListenable<ForumHtmlImageFactoryBinding>) builder;

  @override
  State<_ForumHtmlHostBinding> createState() => _ForumHtmlHostBindingState();
}

class _ForumHtmlHostBindingState extends State<_ForumHtmlHostBinding> {
  late final _binding = ValueNotifier(widget.binding);

  @override
  void didUpdateWidget(covariant _ForumHtmlHostBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _binding.value = widget.binding;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(_binding);

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }
}

class _ForumHtmlInheritedHostBinding extends InheritedWidget {
  const _ForumHtmlInheritedHostBinding({
    required this.binding,
    required super.child,
  });

  final ValueListenable<ForumHtmlImageFactoryBinding> binding;

  @override
  bool updateShouldNotify(_ForumHtmlInheritedHostBinding oldWidget) =>
      !identical(binding, oldWidget.binding);
}

class _BodyReadyWidgetFactory extends WidgetFactory {
  _BodyReadyWidgetFactory(this.onBodyBuilt);
  final VoidCallback onBodyBuilt;

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    final body = super.buildBodyWidget(context, child);
    onBodyBuilt();
    return body;
  }
}

class _DiscuzEditStatusText extends StatelessWidget {
  const _DiscuzEditStatusText({required this.text, required this.baseStyle});

  static final _whitespace = RegExp(r'[\s\u0085\u00a0\u2028\u2029]+');

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
      // Lay out the complete line at the reader's chosen size once. Scaling
      // only when necessary avoids iterative font-size measurement and keeps
      // both the painted line and its layout height within the available box.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text.replaceAll(_whitespace, ' ').trim(),
          key: const Key('forum-html-discuz-edit-status'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: source.copyWith(
            fontSize: baseFontSize == null ? null : baseFontSize * 0.88,
            fontStyle: FontStyle.italic,
            color: baseColor.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }
}
