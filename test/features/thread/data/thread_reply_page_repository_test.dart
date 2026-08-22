import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_reply_page_repository.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

void main() {
  test('maps JSON thread repository data to a reply page', () async {
    final repository = _FakeThreadRepository(
      data: ThreadDetailData(
        tid: '570140',
        fid: '30',
        subject: 'subject',
        author: 'owner',
        replies: 39,
        views: 1,
        currentPage: 2,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '2',
            author: 'reply',
            authorId: '8',
            message: '<p>reply</p>',
            number: 2,
            isFirst: false,
            dateline: 'today',
          ),
        ],
      ),
    );
    final adapter = ApiThreadReplyPageRepository(repository: repository);

    final result = await adapter.loadPage(tid: '570140', page: 2);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.tid, '570140');
    expect(result.dataOrNull!.page, 2);
    expect(result.dataOrNull!.replyCount, 39);
    expect(result.dataOrNull!.posts.single.rawMessage, '<p>reply</p>');
    expect(repository.requested, <String>['570140:2']);
  });

  test('rejects invalid page before touching the repository', () async {
    final repository = _FakeThreadRepository();
    final adapter = ApiThreadReplyPageRepository(repository: repository);

    final result = await adapter.loadPage(tid: '570140', page: 0);

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull!.code, 'invalid_reply_page_request');
    expect(repository.requested, isEmpty);
  });
}

class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository({this.data});

  final ThreadDetailData? data;
  final List<String> requested = <String>[];

  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    requested.add('$tid:$page');
    final value = data;
    if (value == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.server,
        diagnosticMessage: 'missing',
      );
    }
    return DataReadSuccess(
      data: value,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
