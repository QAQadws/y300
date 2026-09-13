import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../domain/services/comic_title_parser_cases.dart';

typedef ComicInteractionRead =
    DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>;

ComicInteractionRead comicInteractionRead({
  String tid = '100',
  String fid = '33',
  int page = 1,
  bool first = true,
  bool rate = true,
  bool ambiguous = false,
  ThreadDetailReadCapabilities? capabilities,
}) => DataReadSuccess(
  data: ThreadDetailData(
    tid: tid,
    fid: fid,
    subject: comicInteractionThreadTitle,
    author: 'author',
    replies: 1,
    views: 1,
    currentPage: page,
    perPage: 20,
    desktopUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid',
    posts: [
      ThreadPost(
        pid: '200',
        author: 'author',
        authorId: '7',
        message: '',
        number: first ? 1 : 2,
        isFirst: first,
        dateline: '',
        rateUrl: rate
            ? 'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=$tid&pid=200'
            : null,
      ),
      if (ambiguous)
        ThreadPost(
          pid: '201',
          author: 'author',
          authorId: '7',
          message: '',
          number: 1,
          isFirst: true,
          dateline: '',
        ),
    ],
  ),
  capabilities:
      capabilities ?? ThreadDetailSourceCapabilities.full.toReadCapabilities(),
  metadata: const DataReadMetadata.network(),
);

class ComicInteractionRepository implements ThreadRepository {
  ComicInteractionRepository([List<FutureOr<ComicInteractionRead>>? responses])
    : responses = responses ?? [];
  final List<FutureOr<ComicInteractionRead>> responses;
  final List<({String tid, int page})> calls = [];
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;
  @override
  Future<ComicInteractionRead> getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    calls.add((tid: tid, page: page));
    return responses.isEmpty
        ? comicInteractionRead(tid: tid)
        : await responses.removeAt(0);
  }
}
