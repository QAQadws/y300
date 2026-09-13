import 'package:y300/features/comic/presentation/widgets/comic_comment_scroll_support.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/comic/presentation/comic_comment_presentation_store.dart';
import 'package:flutter/semantics.dart';
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
    required this.layoutOwner,
    required this.layoutRevision,
    this.imageReferer,
    this.renderContext,
    this.interactionController,
    this.presentation,
  });

  final ComicCommentItemProjection projection;
  final Object layoutOwner;
  final Object layoutRevision;
  final ComicCommentInteractionController? interactionController;
  final String sourceTid;
  final String? imageReferer;
  final ThreadPostRenderContext? renderContext;
  final ComicCommentPostPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    return ComicCommentScrollAnchor(
      owner: layoutOwner,
      contentRevision: layoutRevision,
      child: Semantics(
        container: true,
        sortKey: OrdinalSortKey(projection.sourceItem.floorNumber.toDouble()),
        child: ComicCommentCard(
          interactionController: interactionController,
          projection: projection,
          sourceTid: sourceTid,
          imageReferer: imageReferer,
          renderContext: renderContext,
          presentation: presentation,
        ),
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
    this.onLoadMore,
    this.appendError,
    this.imageReferer,
    this.onRetry,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 24),
    this.renderContext,
    this.interactionController,
    this.presentationStore,
  });

  final ComicCommentInteractionController? interactionController;
  final String sourceTid;
  final ComicCommentContentProjection? projection;
  final bool isLoading;
  final VoidCallback? onLoadMore;
  final ComicCommentLoadErrorCode? appendError;
  final String? imageReferer;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry padding;
  final ThreadPostRenderContext? renderContext;
  final ComicCommentPresentationStore? presentationStore;

  @override
  State<ComicCommentListSurface> createState() =>
      _ComicCommentListSurfaceState();
}

class _ComicCommentListSurfaceState extends State<ComicCommentListSurface>
    with AutomaticKeepAliveClientMixin {
  var _ownedPresentationStore = ComicCommentPresentationStore();
  ComicCommentPresentationStore get _presentation =>
      widget.presentationStore ?? _ownedPresentationStore;
  final _layoutRevision = ComicCommentLayoutRevisionTracker();
  ThreadPostRenderContext? _ownedRenderContext;
  Object? _ownedRenderContextIdentity;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant ComicCommentListSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceTid != widget.sourceTid ||
        !identical(oldWidget.presentationStore, widget.presentationStore)) {
      _ownedPresentationStore.dispose();
      _ownedPresentationStore = ComicCommentPresentationStore();
      _ownedRenderContext = null;
    }
  }

  @override
  void dispose() {
    _ownedPresentationStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
    _presentation.synchronize(projection);

    final hasPartialFailure =
        loadResult.status == ComicCommentLoadStatus.partialFailure;
    final itemCount =
        projection.items.length +
        (hasPartialFailure || loadResult.hasMore ? 1 : 0);
    return ListView.builder(
      controller: _presentation.scrollController,
      scrollCacheExtent: const ScrollCacheExtent.viewport(1),
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = projection.items.indexWhere(
          (item) => item.sourceItem.pid == key.value,
        );
        return index < 0 ? null : index;
      },
      key: const Key('comic-comment-list'),
      padding: widget.padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= projection.items.length) {
          if (loadResult.hasMore &&
              widget.appendError == null &&
              widget.onLoadMore == null) {
            return const ComicCommentFeedbackSurface(
              kind: ComicCommentFeedbackKind.loading,
              compact: true,
            );
          }
          if (loadResult.hasMore &&
              widget.appendError == null &&
              widget.onLoadMore != null) {
            return ComicCommentLoadMoreTrigger(
              identity: loadResult.nextPage!,
              onVisible: widget.onLoadMore!,
              child: const ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.loading,
                compact: true,
              ),
            );
          }
          return ComicCommentFeedbackSurface(
            key: const Key('comic-comment-failure-state'),
            kind: ComicCommentFeedbackKind.unavailable,
            onAction: widget.onRetry,
            compact: true,
          );
        }
        return ComicCommentListItem(
          key: ValueKey(projection.items[index].sourceItem.pid),
          layoutOwner: _presentation,
          layoutRevision: _layoutRevision.update(projection),
          interactionController: widget.interactionController,
          projection: projection.items[index],
          sourceTid: widget.sourceTid,
          imageReferer: widget.imageReferer,
          renderContext: renderContext,
          presentation: _presentation[projection.items[index].sourceItem.pid],
        );
      },
    );
  }

  ThreadPostRenderContext _ensureRenderContext(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final identity = (
      sourceTid: widget.sourceTid.trim(),
      imageReferer: widget.imageReferer,
      brightness: Theme.of(context).brightness,
      palette: palette.card.toARGB32(),
    );
    if (_ownedRenderContextIdentity != identity ||
        _ownedRenderContext == null) {
      _ownedRenderContextIdentity = identity;
      final presentation = _presentation;
      _ownedRenderContext = ThreadPostRenderContext(
        palette: palette,
        imageReferer: widget.imageReferer,
        bodyPresentationFor: (post) => presentation.forRenderedPost(post)?.body,
        imageViewportCoordinator: presentation.imageViewport,
        imageFallbackAspectRatioFor: (post, _, request) => presentation
            .forRenderedPost(post)
            ?.imageAspectRatio(request.cacheKey),
        onBlockImageResolved: (post, _, request, size) => presentation
            .forRenderedPost(post)
            ?.recordImageSize(request.cacheKey, size),
        renderOwnerFor: (post) => ThreadPostRenderContext.commentRenderOwner(
          sourceTid: widget.sourceTid,
          pid: post.pid,
        ),
      );
    }
    return _ownedRenderContext!;
  }
}
