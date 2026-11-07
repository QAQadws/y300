import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';

import '../domain/models/forum_html_reader_preferences.dart';

/// Optional development renderer injection; no implementation or fallback is
/// installed by production. The mounted body retains normal Widget ownership.
typedef ForumHtmlComparisonBodyBuilder = Widget Function(
  ForumHtmlComparisonBodyInput input,
);

final forumHtmlComparisonBodyBuilderProvider =
    Provider<ForumHtmlComparisonBodyBuilder?>((ref) => null);

final class ForumHtmlComparisonBodyInput {
  const ForumHtmlComparisonBodyInput({
    required this.html,
    required this.theme,
    required this.preferences,
    required this.textStyle,
    required this.preparedDocument,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.onBodyBuilt,
    this.bodyPresentation,
    this.collapseExpansion,
    this.sourceId,
    this.threadId,
    this.imageReferer,
    this.imageCacheOwnerId,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.imageViewportCoordinator,
    this.imageAnchorController,
    this.imagePrecacheService,
    this.imageHost,
    this.hasTrailingContent = false,
  });
  final String html;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences? preferences;
  final TextStyle? textStyle;
  final ForumHtmlPreparedRenderDocument preparedDocument;
  final ForumHtmlRenderCallbacks callbacks;
  final VoidCallback? onBodyBuilt;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final Map<String, bool>? collapseExpansion;
  final String? sourceId;
  final String? threadId;
  final String? imageReferer;
  final String? imageCacheOwnerId;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumHtmlImageViewportCoordinator? imageViewportCoordinator;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ForumImagePrecacheService? imagePrecacheService;
  final ForumHtmlImageHost? imageHost;
  final bool hasTrailingContent;
}
