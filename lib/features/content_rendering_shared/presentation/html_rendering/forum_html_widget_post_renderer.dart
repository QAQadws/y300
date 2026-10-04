import '../../application/forum_html_render_preferences_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_image_host_provider.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_render_preparer.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumHtmlWidgetPostRenderer extends StatefulWidget {
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
  State<ForumHtmlWidgetPostRenderer> createState() =>
      _ForumHtmlWidgetPostRendererState();
}

class _ForumHtmlWidgetPostRendererState
    extends State<ForumHtmlWidgetPostRenderer> {
  @override
  Widget build(BuildContext context) {
    final preferences =
        widget.preferences ?? ForumHtmlReaderPreferences.defaults();
    final document =
        widget.preparedDocument ??
        const DefaultForumHtmlRenderPreparer().prepare(
          html: widget.html,
          preferences: preferences,
          theme: widget.theme,
          sourceId: widget.sourceId ?? 'anonymous',
          threadId: widget.threadId,
          imageCacheOwnerId: widget.imageCacheOwnerId,
        );
    final localizations = AppLocalizations.of(context);
    final host =
        widget.imageHost ??
        (widget.threadId?.trim().isNotEmpty == true
            ? CacheForumHtmlImageHost.lazy(
                dimensionIndexFor: () => ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(forumHtmlImageHostProvider).dimensionIndex,
              ).forContent(
                threadId: widget.threadId!,
                imageReferer: widget.imageReferer,
                imageCacheOwnerId: widget.imageCacheOwnerId,
                contentImageKind: widget.contentImageKind,
                imageRequestResolver: widget.imageRequestResolver,
                imageDimensionIndex: widget.imageDimensionIndex,
                fallbackAspectRatioFor: (spec, request) =>
                    widget.imageFallbackAspectRatioFor?.call(spec, request),
                onBlockImageResolved: (spec, request, size) =>
                    widget.onBlockImageResolved?.call(spec, request, size),
                imagePrecacheService: widget.imagePrecacheService,
              )
            : null);
    return ForumHtmlRenderer(
      preparedDocument: document,
      theme: widget.theme,
      options: preferences.renderOptions,
      labels: ForumHtmlCollapseLabels(
        fallbackTitle: localizations.threadHtmlCollapseContent,
        expandedSemanticsLabel: localizations.threadHtmlCollapseExpanded,
        collapsedSemanticsLabel: localizations.threadHtmlCollapseCollapsed,
      ),
      callbacks: widget.callbacks,
      imageHost: host,
      imageHostRevision:
          widget.imageHost ??
          (
            widget.threadId,
            widget.imageReferer,
            widget.imageCacheOwnerId,
            widget.contentImageKind,
            widget.imageRequestResolver,
            widget.imageDimensionIndex,
            widget.imagePrecacheService,
          ),
      imageViewportCoordinator: widget.imageViewportCoordinator,
      buildAsync: widget.buildAsync,
      enableCaching: widget.enableCaching,
      renderMode: widget.renderMode,
      onBodyBuilt: widget.onBodyBuilt,
      bodyPresentation: widget.bodyPresentation,
      collapseExpansion: widget.collapseExpansion,
      sourceId: widget.sourceId,
      blockSpacingMode: widget.blockSpacingMode,
      contentLayout: widget.contentLayout,
      linkBaseUri:
          widget.linkBaseUri ?? ForumHtmlWidgetPostRenderer.forumBaseUri,
    );
  }
}
