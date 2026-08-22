import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_recovery_gateway.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

void main() {
  test(
    'metadata recovery requests page one through configured v4 repository',
    () async {
      final repository = _RecordingThreadRepository(_detail());
      final gateway = ThreadRepositoryNovelSourceMetadataRecoveryGateway(
        repository,
      );

      final detail = await gateway.loadFirstPage(tid: '521519');

      expect(detail.tid, '521519');
      expect(repository.tid, '521519');
      expect(repository.page, 1);
      expect(repository.query, const ThreadDetailQuery());
    },
  );
}

class _RecordingThreadRepository implements ThreadRepository {
  _RecordingThreadRepository(this.detail);

  final ThreadDetailData detail;
  String? tid;
  int? page;
  ThreadDetailQuery? query;

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
    this.tid = tid;
    this.page = page;
    this.query = query;
    return DataReadSuccess(
      data: detail,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

ThreadDetailData _detail() {
  return ThreadDetailData(
    tid: '521519',
    fid: '55',
    subject: '小说',
    author: '发布者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: '1',
        author: '发布者',
        authorId: '406769',
        message: '<p>简介</p>',
        number: 1,
        isFirst: true,
        dateline: '2026-07-13',
      ),
    ],
  );
}
