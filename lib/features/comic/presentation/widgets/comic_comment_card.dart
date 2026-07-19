import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

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
  });

  final ComicCommentItem comment;
  final String sourceTid;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  State<ComicCommentCard> createState() => _ComicCommentCardState();
}

class _ComicCommentCardState extends State<ComicCommentCard>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = _postForComment();
    return ThreadPostCard(
      key: Key('comic-comment-card-${widget.comment.pid}'),
      post: post,
      state: _stateForComment(),
      imageHeaderBuilder: widget.imageHeaderBuilder,
      onCopyActionUrl: (_, _) {},
      onOpenPostLink: (_) {},
      onOpenPostImages: null,
      onTogglePollOption: (_, _) {},
      onSubmitPollVote: (_) {},
      palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
      onOpenCommentAuthorProfile: null,
      onOpenPostActions: null,
    );
  }

  @override
  bool get wantKeepAlive => true;

  ThreadPost _postForComment() {
    final comment = widget.comment;
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

  ThreadDetailPageState _stateForComment() {
    return ThreadDetailPageState.initial(
      // ThreadPostHtmlFirstBody uses state.tid as the image-cache owner. A
      // per-comment owner prevents image index zero in different replies from
      // sharing the same cache key.
      tid: _renderOwnerId(),
      subject: '',
    );
  }

  String _renderOwnerId() {
    final tid = widget.sourceTid.trim().isEmpty
        ? 'unknown-thread'
        : widget.sourceTid.trim();
    final pid = widget.comment.pid.trim().isEmpty
        ? 'unknown-post'
        : widget.comment.pid.trim();
    return 'comic-comment-$tid-$pid';
  }
}
