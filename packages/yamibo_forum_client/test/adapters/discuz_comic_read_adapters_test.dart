import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_comic_read_adapters.dart';

import '../support/data_source_contracts/repository_contract_suites.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
    userAgent: 'test-agent',
  );

  runComicEpisodeCatalogContractSuite(
    () => ComicEpisodeCatalogContractDriver(
      name: 'v4 projection',
      sourceTid: '100',
      createRepository: () => DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: _FakeThreadRepository(
          _detail(
            posts: [
              _post(
                pid: 'p1',
                number: 1,
                isFirst: true,
                message: '<img src="/page.jpg">',
              ),
            ],
          ),
        ),
        config: config,
      ),
    ),
  );
  runComicThreadDiscoveryContractSuite(
    () => ComicThreadDiscoveryContractDriver(
      name: 'v4 projection',
      sourceTid: '100',
      createRepository: () => ThreadRepositoryComicThreadDiscoveryAdapter(
        threadRepository: _FakeThreadRepository(_detail()),
        config: config,
      ),
    ),
  );
  runThreadReplyPageContractSuite(
    () => ThreadReplyPageContractDriver(
      name: 'v4 projection',
      tid: '100',
      createRepository: () => ApiThreadReplyPageRepository(
        repository: _FakeThreadRepository(_detail()),
      ),
    ),
  );

  test('catalog projects ordered DOM and attachment images once', () async {
    final thread = _FakeThreadRepository(
      _detail(
        posts: [
          ThreadPost(
            pid: 'p1',
            author: 'author',
            authorId: 'u1',
            message:
                '<img src="/data/attachment/forum/a.jpg">'
                '<img src="/static/image/smiley.png">',
            number: 1,
            isFirst: true,
            dateline: 'now',
            attachmentImages: const [
              ForumPostAttachmentImage(
                aid: '10',
                url: 'https://example.test/data/attachment/',
                attachment: 'forum/a.jpg',
                filename: 'a.jpg',
                attachimg: '1',
                ext: 'jpg',
              ),
              ForumPostAttachmentImage(
                aid: '11',
                url: 'https://example.test/data/attachment/',
                attachment: 'forum/b.png',
                filename: 'b.png',
                attachimg: '1',
                ext: 'png',
              ),
            ],
          ),
        ],
      ),
    );
    final repository = DiscuzApiComicEpisodeCatalogRepository(
      threadRepository: thread,
      config: config,
    );

    final result = await repository.loadCatalog(
      const ComicEpisodeCatalogRequest(sourceTid: '100'),
    );

    final success =
        result
            as DataReadSuccess<
              ComicEpisodeImageCatalog,
              ComicEpisodeCatalogCapabilities
            >;
    expect(success.data.images.map((image) => image.url), [
      'https://example.test/data/attachment/forum/a.jpg',
      'https://example.test/data/attachment/forum/b.png',
    ]);
    expect(success.data.images.last.attachmentId, '11');
    expect(success.data.images.last.origin, ComicEpisodeImageOrigin.attachment);
    expect(thread.requests, [('100', 1)]);
    expect(success.metadata.origin, DataReadOrigin.network);
  });

  test('catalog distinguishes a valid empty first post from failure', () async {
    final repository = DiscuzApiComicEpisodeCatalogRepository(
      threadRepository: _FakeThreadRepository(_detail()),
      config: config,
    );

    final result = await repository.loadCatalog(
      const ComicEpisodeCatalogRequest(sourceTid: '100'),
    );

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.images, isEmpty);
  });

  test('discovery returns a narrow sorted projection', () async {
    final detail = _detail(
      posts: [
        _post(pid: 'p2', number: 2, message: '<img src="/second.jpg">'),
        _post(pid: 'p1', number: 1, isFirst: true),
      ],
    );
    final repository = ThreadRepositoryComicThreadDiscoveryAdapter(
      threadRepository: _FakeThreadRepository(detail),
      config: config,
    );

    final result = await repository.load(
      const ComicThreadDiscoveryRequest(sourceTid: '100'),
    );

    final success =
        result
            as DataReadSuccess<
              ComicThreadDiscoveryDocument,
              ComicThreadDiscoveryCapabilities
            >;
    expect(success.data.posts.map((post) => post.pid), ['p1', 'p2']);
    expect(
      success.data.posts.last.imageReferences.single.url,
      'https://example.test/second.jpg',
    );
    expect(success.data.fid, '30');
  });

  test('reply page preserves identity and pagination semantics', () async {
    final repository = ApiThreadReplyPageRepository(
      repository: _FakeThreadRepository(
        _detail(
          currentPage: 2,
          posts: [_post(pid: 'p2', number: 2)],
          nextPageUrl: 'https://example.test/thread?page=3',
        ),
      ),
    );

    final result = await repository.loadPage(tid: '100', page: 2);

    final success =
        result
            as DataReadSuccess<
              ThreadReplyPage,
              ThreadReplyPageReadCapabilities
            >;
    expect(success.data.posts.single.pid, 'p2');
    expect(success.data.hasNext, isTrue);
    expect(success.data.page, 2);
  });

  test(
    'missing required thread capability fails closed before projection',
    () async {
      final repository = DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: _FakeThreadRepository(
          _detail(),
          sourceCapabilities: ThreadDetailSourceCapabilities(
            values: DataCapabilitySet.from(
              supported: const [ThreadDetailCapability.threadIdentity],
              unsupported: const [ThreadDetailCapability.firstPostIdentity],
            ),
            paginationPrecision: PaginationPrecision.directional,
          ),
        ),
        config: config,
      );

      final result = await repository.loadCatalog(
        const ComicEpisodeCatalogRequest(sourceTid: '100'),
      );

      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
    },
  );
}

ThreadDetailData _detail({
  List<ThreadPost>? posts,
  int currentPage = 1,
  String? nextPageUrl,
}) => ThreadDetailData(
  tid: '100',
  fid: '30',
  typeid: '7',
  subject: 'fixture subject',
  author: 'author',
  replies: 2,
  views: 3,
  currentPage: currentPage,
  perPage: 20,
  posts: posts ?? [_post(pid: 'p1', number: 1, isFirst: true)],
  nextPageUrl: nextPageUrl,
);

ThreadPost _post({
  required String pid,
  required int number,
  bool isFirst = false,
  String message = '',
}) => ThreadPost(
  pid: pid,
  author: 'author',
  authorId: 'u1',
  message: message,
  number: number,
  isFirst: isFirst,
  dateline: 'now',
);

final class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository(
    this.detail, {
    ThreadDetailSourceCapabilities? sourceCapabilities,
  }) : capabilities = sourceCapabilities ?? ThreadDetailSourceCapabilities.full;

  final ThreadDetailData detail;
  @override
  final ThreadDetailSourceCapabilities capabilities;
  final List<(String, int)> requests = [];

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    requests.add((tid, page));
    return DataReadSuccess(
      data: detail,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
