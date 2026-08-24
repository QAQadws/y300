import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

/// A read-only reply surface built from the parser-mode post card.
///
/// A comment is converted to a non-first [ThreadPost] with no poll, rating or
/// nested comments. This lets the existing post card keep owning avatar
/// layout, HTML-first rendering, theme adaptation and future parser-mode
/// fixes, while the comment surface exposes no post actions.
class ComicCommentCard extends StatefulWidget {
  const ComicCommentCard({
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

  /// Converts a comment to the existing parser-mode post-card input.
  ///
  /// Keeping this adapter public lets list surfaces prune the shared render
  /// plan cache without duplicating the post mapping rules.
  static ThreadPost toThreadPost(ComicCommentItemProjection projection) {
    final comment = projection.sourceItem;
    return ThreadPost(
      pid: comment.pid,
      author: comment.authorName,
      authorId: comment.authorId,
      message: projection.displayMessage,
      number: comment.floorNumber,
      // The first floor is filtered by the loader. Keeping this false also
      // prevents ThreadPostCard from adding the thread summary header.
      isFirst: false,
      dateline: projection.displayDateline,
      avatarUrl: comment.avatarUrl,
    );
  }

  @override
  State<ComicCommentCard> createState() => _ComicCommentCardState();
}

class _ComicCommentCardState extends State<ComicCommentCard> {
  ThreadPostRenderContext? _ownedRenderContext;
  Object? _ownedRenderContextIdentity;

  @override
  Widget build(BuildContext context) {
    final post = _postForComment();
    final renderContext = widget.renderContext ?? _ensureRenderContext(context);
    return ThreadPostCard(
      key: Key('comic-comment-card-${widget.projection.sourceItem.pid}'),
      post: post,
      state: null,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
      interactionPolicy: const ThreadPostCardInteractionPolicy.readOnly(),
      avatarFallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
      renderContext: renderContext,
    );
  }

  ThreadPost _postForComment() =>
      ComicCommentCard.toThreadPost(widget.projection);

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
