import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../domain/services/comic_title_parser_cases.dart';

typedef CommentDetailRead =
    DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>;
DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>
commentDetailPage({
  int page = 1,
  int lastPage = 3,
  String tid = '100',
  List<ThreadPost>? posts,
}) => DataReadSuccess(
  data: ThreadDetailData(
    tid: tid,
    fid: '33',
    subject: comicInteractionThreadTitle,
    author: 'author',
    replies: lastPage * 2 - 1,
    views: 1,
    currentPage: page,
    perPage: 2,
    lastPage: lastPage,
    nextPageUrl: page < lastPage
        ? 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&page=${page + 1}&mobile=2'
        : null,
    desktopUrl:
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&page=$page&mobile=2',
    posts: posts ?? [commentPost(page * 2 - 1), commentPost(page * 2)],
  ),
  capabilities: ThreadDetailSourceCapabilities.full.toReadCapabilities(),
  metadata: const DataReadMetadata.network(),
);

ThreadPost commentPost(int number, {String? message}) => ThreadPost(
  pid: '$number',
  author: 'author',
  authorId: '7',
  message:
      message ??
      '<div class="quote"><blockquote>quoted $number</blockquote></div><p>body $number</p>',
  number: number,
  isFirst: number == 1,
  dateline: 'today',
  replyUrl:
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=100&repquote=$number',
  rateUrl:
      'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=100&pid=$number',
  commentUrl:
      'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=100&pid=$number',
  ratingSummary: ThreadPostRatingSummary(
    participantText: '1',
    scoreText: '+2',
    ratings: const [
      ThreadPostRating(userName: 'rater', score: '+2', reason: '支持'),
    ],
    viewAllUrl:
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings&tid=100&pid=$number',
  ),
  comments: const [
    ThreadPostCommentEntry(
      author: 'reviewer',
      authorId: '8',
      message: '点评内容',
      dateline: 'today',
    ),
  ],
);

class CommentDetailRepository implements ThreadRepository {
  CommentDetailRepository({this.respond});
  final FutureOr<CommentDetailRead> Function(int page)? respond;
  final List<int> calls = [];
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;
  @override
  Future<CommentDetailRead> getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    calls.add(page);
    return await (respond?.call(page) ??
        commentDetailPage(page: page, tid: tid));
  }
}
