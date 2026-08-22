import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/data/repositories/thread_repository_comic_thread_discovery_adapter.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

import '../../../support/data_source_contracts/comic_thread_discovery_contract_suite.dart';

void main() {
  runComicThreadDiscoveryContractSuite(
    () => ComicThreadDiscoveryContractDriver(
      name: 'Discuz v4 thread projection',
      createRepository: () => ThreadRepositoryComicThreadDiscoveryAdapter(
        threadRepository: _DiscoveryThreadRepository(_detail()),
      ),
      sourceTid: '100',
    ),
  );

  test('rejects a source without required thread capabilities', () async {
    final repository = ThreadRepositoryComicThreadDiscoveryAdapter(
      threadRepository: _DiscoveryThreadRepository(
        _detail(),
        capabilities: ThreadDetailSourceCapabilities(
          values: DataCapabilitySet<ThreadDetailCapability>.from(
            supported: const <ThreadDetailCapability>[
              ThreadDetailCapability.threadIdentity,
            ],
            unsupported: const <ThreadDetailCapability>[
              ThreadDetailCapability.renderableBody,
            ],
          ),
          paginationPrecision: PaginationPrecision.unknown,
        ),
      ),
    );

    final result = await repository.load(
      const ComicThreadDiscoveryRequest(sourceTid: '100'),
    );

    expect(result.failureOrNull?.kind, DataReadFailureKind.unsupported);
  });
}

ThreadDetailData _detail() {
  return ThreadDetailData(
    tid: '100',
    fid: '30',
    typeid: '398',
    subject: '测试漫画 第1话',
    author: 'author',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: '1001',
        author: 'author',
        authorId: '1',
        message: '<img src="https://img.test/1.jpg">',
        number: 1,
        isFirst: true,
        dateline: 'today',
      ),
    ],
  );
}

final class _DiscoveryThreadRepository implements ThreadRepository {
  _DiscoveryThreadRepository(
    this.detail, {
    ThreadDetailSourceCapabilities? capabilities,
  }) : capabilities = capabilities ?? ThreadDetailSourceCapabilities.full;

  final ThreadDetailData detail;

  @override
  final ThreadDetailSourceCapabilities capabilities;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    return DataReadSuccess(
      data: detail,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
