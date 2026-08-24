import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  group('YamiboForumClientBuilder', () {
    test('installs the verified standard read-source matrix', () {
      final client = _builder().buildStandardReads();
      final sources = client.sourcePlan;

      expect(sources.forumDirectory, isA<DiscuzForumDirectoryHtmlRepository>());
      expect(
        sources.forumTagDirectory,
        isA<DiscuzForumTagDirectoryRepository>(),
      );
      expect(sources.forumDisplay, isA<ForumDisplayHtmlRepository>());
      expect(
        sources.favoriteForumDirectory,
        isA<DiscuzFavoriteForumDirectoryRepository>(),
      );
      expect(
        sources.favoriteThreadDirectory,
        isA<DiscuzFavoriteThreadDirectoryRepository>(),
      );
      expect(
        sources.currentUserProfile,
        isA<DiscuzCurrentUserProfileRepository>(),
      );
      expect(sources.forumUserProfile, isA<DiscuzForumUserProfileRepository>());
      expect(
        sources.userBlogDirectory,
        isA<DiscuzUserBlogDirectoryRepository>(),
      );
      expect(sources.userBlogDetail, isA<DiscuzUserBlogDetailRepository>());
      expect(
        sources.comicEpisodeCatalog,
        isA<DiscuzApiComicEpisodeCatalogRepository>(),
      );
      expect(
        sources.comicThreadDiscovery,
        isA<ThreadRepositoryComicThreadDiscoveryAdapter>(),
      );
      expect(sources.threadReplyPage, isA<ApiThreadReplyPageRepository>());
      expect(sources.threadDetail, isA<ThreadDetailHtmlRepository>());
      expect(sources.threadIngestionDetail, isA<ApiThreadRepository>());
      expect(
        (sources.threadIngestionDetail! as ApiThreadRepository).apiVersion,
        '4',
      );
    });

    test(
      'omits search without formhash and fails closed without transport',
      () async {
        final network = _CountingNetwork();
        final client = _builder(network: network).buildStandardReads();

        expect(client.sourcePlan.forumSearch, isNull);
        final result = await client.searchForums(
          const ForumSearchQuery(keyword: 'fixture'),
        );

        expect(result.failureOrNull?.kind, DataReadFailureKind.unsupported);
        expect(result.failureOrNull?.code, 'source_not_installed');
        expect(network.requestCount, 0);
      },
    );

    test('installs search when a formhash provider is supplied', () {
      final client = _builder(
        formhashProvider: const _FixtureFormhashProvider(),
      ).buildStandardReads();

      expect(client.sourcePlan.forumSearch, isA<DiscuzForumSearchRepository>());
    });

    test('advanced source plans can still replace one contract', () {
      final custom = _FixtureThreadRepository();
      final client = YamiboForumClient(
        config: _config,
        network: _CountingNetwork(),
        sourcePlan: ForumClientSourcePlan(threadDetail: custom),
      );

      expect(identical(client.threadDetail, custom), isTrue);
      expect(client.sourcePlan.forumDirectory, isNull);
    });
  });
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://bbs.example.invalid'),
  apiOrigin: Uri.parse('https://api.example.invalid'),
  userAgent: 'yamibo-forum-client-test',
);

YamiboForumClientBuilder _builder({
  _CountingNetwork? network,
  ForumFormhashProvider? formhashProvider,
}) {
  return YamiboForumClientBuilder(
    config: _config,
    network: network ?? _CountingNetwork(),
    sessionStore: MemoryForumSessionStore(),
    documentStore: MemoryForumDocumentStore(),
    snapshotStore: MemoryForumSnapshotStore(),
    formhashProvider: formhashProvider,
  );
}

final class _CountingNetwork implements ForumClientNetwork {
  int requestCount = 0;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requestCount += 1;
    return const ForumTransportError(
      ForumTransportFailure(
        kind: ForumTransportFailureKind.network,
        code: 'fixture_network',
      ),
    );
  }
}

final class _FixtureFormhashProvider implements ForumFormhashProvider {
  const _FixtureFormhashProvider();

  @override
  Future<ForumFormhashResult> loadFormhash({bool preferProfile = true}) async =>
      const ForumFormhashSuccess('fixture-formhash');
}

final class _FixtureThreadRepository implements ThreadRepository {
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities(
        values: DataCapabilitySet.from(
          unsupported: ThreadDetailCapability.values,
        ),
        paginationPrecision: PaginationPrecision.unknown,
      );

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async => const DataReadFailure(
    kind: DataReadFailureKind.unsupported,
    code: 'fixture_unsupported',
    diagnosticMessage: 'fixture_unsupported',
  );
}
