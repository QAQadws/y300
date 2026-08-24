import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/novel/data/services/novel_thread_gateway.dart';

void main() {
  group('PackageNovelThreadGateway', () {
    test(
      'projects the package author-post page into the novel model',
      () async {
        final source = _FakeAuthorPostRepository(
          DataReadSuccess(
            data: ThreadAuthorPostPage(
              tid: '200',
              subject: '测试小说标题',
              posts: [
                ThreadPost(
                  pid: '5001',
                  author: '楼主A',
                  authorId: '1',
                  message: '<p>第1章</p>',
                  number: 1,
                  isFirst: true,
                  dateline: '2026-01-01',
                ),
              ],
              currentPage: 3,
              pageSize: 200,
              totalReplyHint: 2,
              hasNext: true,
            ),
            capabilities: _readCapabilities,
            metadata: const DataReadMetadata.network(),
          ),
        );
        final gateway = PackageNovelThreadGateway(source);

        final result = await gateway.loadAuthorPostsPage(
          tid: '200',
          authorId: '1',
          page: 3,
        );

        expect(source.queries.single.tid, '200');
        expect(source.queries.single.authorId, '1');
        expect(source.queries.single.page, 3);
        expect(source.queries.single.pageSize, 200);
        expect(result.tid, '200');
        expect(result.currentPage, 3);
        expect(result.perPage, 200);
        expect(result.posts.single.pid, '5001');
        expect(result.nextPageUrl, 'author-page:4');
      },
    );

    test('throws when the package read fails', () async {
      final gateway = PackageNovelThreadGateway(
        _FakeAuthorPostRepository(
          const DataReadFailure(
            kind: DataReadFailureKind.business,
            code: 'viewthread_forbidden',
            diagnosticMessage: '读取失败',
          ),
        ),
      );

      expect(
        () => gateway.loadAuthorPostsPage(tid: '200', authorId: '1', page: 1),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', '读取失败'),
        ),
      );
    });
  });
}

final _readCapabilities = ThreadAuthorPostReadCapabilities(
  values: DataCapabilitySet.supported(ThreadAuthorPostCapability.values),
);

final class _FakeAuthorPostRepository implements ThreadAuthorPostRepository {
  _FakeAuthorPostRepository(this.result);

  final DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>
  result;
  final queries = <ThreadAuthorPostQuery>[];

  @override
  ThreadAuthorPostSourceCapabilities get capabilities =>
      ThreadAuthorPostSourceCapabilities(
        values: DataCapabilitySet.supported(ThreadAuthorPostCapability.values),
      );

  @override
  Future<DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>>
  load(
    ThreadAuthorPostQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  }) async {
    queries.add(query);
    return result;
  }
}
