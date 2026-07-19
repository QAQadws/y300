import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';

/// A read-only reply surface built from the parser-mode post card.
///
/// A comment is converted to a non-first [ThreadPost] with no poll, rating or
/// nested comments. This lets the existing post card keep owning avatar
/// layout, HTML-first rendering, theme adaptation and future parser-mode
/// fixes, while the comment surface exposes no post actions.
class ComicCommentCard extends StatefulWidget {
  const ComicCommentCard({
    super.key,
    required this.comment,
    required this.sourceTid,
    this.imageHeaderBuilder,
    this.renderContext,
  });

  final ComicCommentItem comment;
  final String sourceTid;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ThreadPostRenderContext? renderContext;

  /// Converts a comment to the existing parser-mode post-card input.
  ///
  /// Keeping this adapter public lets list surfaces prune the shared render
  /// plan cache without duplicating the post mapping rules.
  static ThreadPost toThreadPost(ComicCommentItem comment) {
    return ThreadPost(
      pid: comment.pid,
      author: comment.authorName,
      authorId: comment.authorId,
      message: comment.rawMessage,
      number: comment.floorNumber,
      // The first floor is filtered by the loader. Keeping this false also
      // prevents ThreadPostCard from adding the thread summary header.
      isFirst: false,
      dateline: comment.dateline,
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
      key: Key('comic-comment-card-${widget.comment.pid}'),
      post: post,
      state: null,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
      interactionPolicy: const ThreadPostCardInteractionPolicy.readOnly(),
      renderContext: renderContext,
    );
  }

  ThreadPost _postForComment() => ComicCommentCard.toThreadPost(widget.comment);

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
