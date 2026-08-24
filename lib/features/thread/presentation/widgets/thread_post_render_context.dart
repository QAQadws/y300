import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/thread_detail_render_entries.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

/// Controls which interactions a reusable post card is allowed to expose.
///
/// The parser-mode page uses [full]. Comment surfaces use [readOnly], so they
/// can reuse the same post rendering implementation without presenting
/// no-op author, image, rating or post-action controls.
@immutable
class ThreadPostCardInteractionPolicy {
  const ThreadPostCardInteractionPolicy({
    required this.allowAuthorProfile,
    required this.allowPostLinks,
    required this.allowImageOpen,
    required this.allowImageFallbackCopy,
    required this.allowPostActions,
    required this.allowCommentAuthorProfile,
    required this.showPoll,
    required this.showComments,
    required this.showRating,
  });

  const ThreadPostCardInteractionPolicy.full()
    : this(
        allowAuthorProfile: true,
        allowPostLinks: true,
        allowImageOpen: true,
        allowImageFallbackCopy: true,
        allowPostActions: true,
        allowCommentAuthorProfile: true,
        showPoll: true,
        showComments: true,
        showRating: true,
      );

  const ThreadPostCardInteractionPolicy.readOnly()
    : this(
        allowAuthorProfile: false,
        allowPostLinks: true,
        allowImageOpen: false,
        allowImageFallbackCopy: false,
        allowPostActions: false,
        allowCommentAuthorProfile: false,
        showPoll: false,
        showComments: false,
        showRating: false,
      );

  final bool allowAuthorProfile;
  final bool allowPostLinks;
  final bool allowImageOpen;
  final bool allowImageFallbackCopy;
  final bool allowPostActions;
  final bool allowCommentAuthorProfile;
  final bool showPoll;
  final bool showComments;
  final bool showRating;
}

/// Shared context for one or more reusable parser-mode post cards.
///
/// The context owns the render-plan cache and the layout/resource hooks that
/// were previously owned by the full thread page. It deliberately does not
/// own a [ThreadDetailPageState], pagination state or a scroll controller.
class ThreadPostRenderContext {
  ThreadPostRenderContext({
    required this.palette,
    required this.imageHeaderBuilder,
    required this.renderOwnerFor,
    this.imageRefererFor = _emptyImageReferer,
    ThreadDetailRenderEntryPlanner? renderPlanner,
    ThreadPostImageDimensionLookup? dimensionLookup,
    this.onImageLayoutShift,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.onImageDiagnostics,
  }) : _renderPlanner =
           renderPlanner ??
           ThreadDetailRenderEntryPlanner(
             bodyRenderPlanner: ThreadPostBodyRenderPlanner(
               resourceLayoutHintResolver: ThreadPostResourceLayoutHintResolver(
                 lockTrustedDimensions: true,
                 dimensionLookup: dimensionLookup,
               ),
             ),
           );

  final ThreadDetailNativePalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String Function(ThreadPost post) renderOwnerFor;
  final String Function(ThreadPost post) imageRefererFor;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final double? Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
  )?
  imageFallbackAspectRatioFor;
  final void Function(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;

  final ThreadDetailRenderEntryPlanner _renderPlanner;

  ThreadPostBodyRenderPlan planFor(ThreadPost post) {
    return _renderPlanner.planFor(post);
  }

  void prune(Iterable<ThreadPost> posts) {
    _renderPlanner.prune(posts.toList(growable: false));
  }

  static String commentRenderOwner({
    required String sourceTid,
    required String pid,
  }) {
    final tid = sourceTid.trim().isEmpty ? 'unknown-thread' : sourceTid.trim();
    final postId = pid.trim().isEmpty ? 'unknown-post' : pid.trim();
    return 'comic-comment-$tid-$postId';
  }

  static String _emptyImageReferer(ThreadPost post) => '';
}
