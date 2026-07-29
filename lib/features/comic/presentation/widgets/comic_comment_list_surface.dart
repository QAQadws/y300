import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_surface.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';

/// One lazy comment row shared by the paged list and the vertical reader tail.
class ComicCommentListItem extends StatelessWidget {
  const ComicCommentListItem({
    super.key,
    required this.projection,
    required this.sourceTid,
    this.imageHeaderBuilder,
    this.renderContext,
  });

  final ComicCommentItemProjection projection;
  final String sourceTid;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostRenderContext? renderContext;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(projection.sourceItem.floorNumber.toDouble()),
      child: ComicCommentCard(
        projection: projection,
        sourceTid: sourceTid,
        imageHeaderBuilder: imageHeaderBuilder,
        renderContext: renderContext,
      ),
    );
  }
}

/// A standalone, lazy comment list.
///
/// The reader-tail integration is deliberately outside this widget. Keeping
/// this surface scrollable on its own makes the Phase 2 component testable and
/// prevents a second reader-specific pagination or lifecycle state machine.
class ComicCommentListSurface extends StatefulWidget {
  const ComicCommentListSurface({
    super.key,
    required this.sourceTid,
    this.projection,
    this.isLoading = false,
    this.imageHeaderBuilder,
    this.onRetry,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 24),
    this.renderContext,
  });

  final String sourceTid;
  final ComicCommentContentProjection? projection;
  final bool isLoading;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry padding;
  final ThreadPostRenderContext? renderContext;

  @override
  State<ComicCommentListSurface> createState() =>
      _ComicCommentListSurfaceState();
}

class _ComicCommentListSurfaceState extends State<ComicCommentListSurface> {
  ThreadPostRenderContext? _ownedRenderContext;
  Object? _ownedRenderContextIdentity;

  @override
  Widget build(BuildContext context) {
    final renderContext = widget.renderContext ?? _ensureRenderContext(context);
    if (widget.isLoading) {
      return const ComicCommentFeedbackSurface(
        key: Key('comic-comment-loading'),
        kind: ComicCommentFeedbackKind.loading,
      );
    }

    final projection = widget.projection;
    final loadResult = projection?.sourceResult;
    if (loadResult == null ||
        loadResult.status == ComicCommentLoadStatus.empty) {
      return const ComicCommentFeedbackSurface(
        key: Key('comic-comment-empty'),
        kind: ComicCommentFeedbackKind.empty,
      );
    }
    if (loadResult.status == ComicCommentLoadStatus.failure ||
        loadResult.status == ComicCommentLoadStatus.cancelled) {
      return ComicCommentFeedbackSurface(
        key: const Key('comic-comment-failure-state'),
        kind: ComicCommentFeedbackKind.unavailable,
        onAction: widget.onRetry,
      );
    }
    if (loadResult.items.isEmpty &&
        loadResult.status != ComicCommentLoadStatus.partialFailure) {
      return const ComicCommentFeedbackSurface(
        key: Key('comic-comment-empty'),
        kind: ComicCommentFeedbackKind.empty,
      );
    }
    if (loadResult.items.isEmpty) {
      return ComicCommentFeedbackSurface(
        key: const Key('comic-comment-failure-state'),
        kind: ComicCommentFeedbackKind.unavailable,
        onAction: widget.onRetry,
      );
    }

    // The planner is shared by all visible cards. Keep only the current
    // result's keys so revisiting a recycled long-list item cannot retain
    // render plans from an older chapter/session.
    renderContext.prune(projection!.items.map(ComicCommentCard.toThreadPost));

    final hasPartialFailure =
        loadResult.status == ComicCommentLoadStatus.partialFailure;
    final itemCount = projection.items.length + (hasPartialFailure ? 1 : 0);
    return ListView.builder(
      key: const Key('comic-comment-list'),
      padding: widget.padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= projection.items.length) {
          return ComicCommentFeedbackSurface(
            key: const Key('comic-comment-failure-state'),
            kind: ComicCommentFeedbackKind.unavailable,
            onAction: widget.onRetry,
            compact: true,
          );
        }
        return ComicCommentListItem(
          projection: projection.items[index],
          sourceTid: widget.sourceTid,
          imageHeaderBuilder: widget.imageHeaderBuilder,
          renderContext: renderContext,
        );
      },
    );
  }

  ThreadPostRenderContext _ensureRenderContext(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final identity = (
      sourceTid: widget.sourceTid.trim(),
      imageHeaderBuilder: widget.imageHeaderBuilder,
      brightness: Theme.of(context).brightness,
      palette: palette.card.toARGB32(),
    );
    if (_ownedRenderContextIdentity != identity ||
        _ownedRenderContext == null) {
      _ownedRenderContextIdentity = identity;
      _ownedRenderContext = ThreadPostRenderContext(
        palette: palette,
        imageHeaderBuilder: widget.imageHeaderBuilder,
        renderOwnerFor: (post) => ThreadPostRenderContext.commentRenderOwner(
          sourceTid: widget.sourceTid,
          pid: post.pid,
        ),
      );
    }
    return _ownedRenderContext!;
  }
}
