import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import 'forum_html_widget_post_renderer.dart';

Widget legacyComparisonBodyBuilder(ForumHtmlComparisonBodyInput input) =>
    ForumHtmlWidgetPostRenderer(
      html: input.html,
      theme: input.theme,
      preferences: input.preferences,
      textStyle: input.textStyle,
      preparedDocument: input.preparedDocument,
      callbacks: input.callbacks,
      onBodyBuilt: input.onBodyBuilt,
      bodyPresentation: input.bodyPresentation,
      collapseExpansion: input.collapseExpansion,
      sourceId: input.sourceId,
      threadId: input.threadId,
      imageReferer: input.imageReferer,
      imageCacheOwnerId: input.imageCacheOwnerId,
      imageFallbackAspectRatioFor: input.imageFallbackAspectRatioFor,
      onBlockImageResolved: input.onBlockImageResolved,
      imageViewportCoordinator: input.imageViewportCoordinator,
      imageAnchorController: input.imageAnchorController,
      imagePrecacheService: input.imagePrecacheService,
      imageHost: input.imageHost,
      hasTrailingContent: input.hasTrailingContent,
    );

final legacyComparisonBodyOverride = forumHtmlComparisonBodyBuilderProvider
    .overrideWithValue(legacyComparisonBodyBuilder);
