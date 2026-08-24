import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  group('YamiboForumClientBuilder', () {
    test('installs the verified standard read-source matrix', () {
      final client = _builder().buildStandardReads();
      final sources = client.sourcePlan;

      expect(sources.forumHome, isA<DiscuzForumHomeHtmlRepository>());
      expect(identical(sources.forumDirectory, sources.forumHome), isTrue);
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
      expect(sources.notifications, isA<DiscuzForumNotificationRepository>());
      expect(
        sources.privateMessages,
        isA<DiscuzForumPrivateMessageRepository>(),
      );
      expect(
        sources.stickerCatalog,
        isA<DiscuzForumStickerCatalogRepository>(),
      );
      expect(sources.postRatings, isA<DiscuzThreadPostRatingsRepository>());
      expect(sources.postLocator, isA<DiscuzThreadPostLocatorRepository>());
      expect(
        sources.threadAuthorPosts,
        isA<DiscuzThreadAuthorPostRepository>(),
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

    test('installs search without a host formhash provider', () {
      final network = _CountingNetwork();
      final client = _builder(network: network).buildStandardReads();

      expect(client.sourcePlan.forumSearch, isA<DiscuzForumSearchRepository>());
      expect(network.requestCount, 0);
    });

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

    test('uses a resource-capable network for image resources', () {
      final network = _ResourceCapableNetwork();
      final client = _builder(network: network).buildStandardReads();

      expect(identical(client.resources, network), isTrue);
    });

    test('standard Dio composition only needs host persistence ports', () {
      final client = YamiboForumClientBuilder.standardDio(
        config: _config,
        cookies: MemoryForumCookieStore(),
        caches: ForumClientCachePorts(
          documents: MemoryForumDocumentStore(),
          snapshots: MemoryForumSnapshotStore(),
          stickers: MemoryForumStickerCatalogStore(),
        ),
      ).buildStandardReads();

      expect(client.network, isA<DioForumClientNetwork>());
      expect(identical(client.resources, client.network), isTrue);
      expect(client.sourcePlan.forumSearch, isNotNull);
    });

    test('fails resource reads closed when no client is installed', () async {
      final client = _builder().buildStandardReads();
      final reference = ForumResourceReferenceResolver(
        siteOrigin: _config.siteOrigin,
      ).resolve('/avatar.jpg');

      final result = await client.resources.open(
        ForumResourceRequest(reference: reference!),
      );

      expect(
        (result as ForumResourceError).failure.kind,
        ForumResourceFailureKind.unsupported,
      );
    });

    test('standard formhash reads profile and updates session', () async {
      final sessions = MemoryForumSessionStore();
      final network = _QueueNetwork(<Object?>[
        <String, Object?>{
          'Variables': <String, Object?>{
            'member_uid': '42',
            'member_username': 'Fixture User',
            'formhash': 'fixture-formhash',
          },
        },
      ]);
      final factory = ForumClientAdapterFactory(
        config: _config,
        network: network,
        sessionStore: sessions,
      );

      final result = await factory
          .createStandardFormhashProvider(sessions)
          .loadFormhash();

      expect(result, isA<ForumFormhashSuccess>());
      expect((result as ForumFormhashSuccess).value, 'fixture-formhash');
      expect(network.modules, <String>['profile']);
      expect(sessions.readCurrent()?.userId, '42');
      expect(sessions.readCurrent()?.username, 'Fixture User');
      expect(sessions.readFreshFormhash(), 'fixture-formhash');
    });

    test('standard formhash falls back to forumindex', () async {
      final sessions = MemoryForumSessionStore();
      final network = _QueueNetwork(<Object?>[
        <String, Object?>{
          'Variables': <String, Object?>{'member_uid': '0'},
        },
        <String, Object?>{
          'Variables': <String, Object?>{'formhash': 'fallback-formhash'},
        },
      ]);
      final factory = ForumClientAdapterFactory(
        config: _config,
        network: network,
        sessionStore: sessions,
      );

      final result = await factory
          .createStandardFormhashProvider(sessions)
          .loadFormhash();

      expect((result as ForumFormhashSuccess).value, 'fallback-formhash');
      expect(network.modules, <String>['profile', 'forumindex']);
      expect(sessions.readFreshFormhash(), 'fallback-formhash');
    });

    test('session projection failures do not invalidate a read', () async {
      final network = _QueueNetwork(<Object?>[
        <String, Object?>{
          'Variables': <String, Object?>{
            'member_uid': '42',
            'formhash': 'fixture-formhash',
          },
        },
      ]);
      final factory = ForumClientAdapterFactory(
        config: _config,
        network: network,
        sessionStore: _ThrowingSessionStore(),
      );

      final result = await factory
          .createStandardFormhashProvider(_ThrowingSessionStore())
          .loadFormhash();

      expect(result, isA<ForumFormhashSuccess>());
      expect((result as ForumFormhashSuccess).value, 'fixture-formhash');
    });
  });
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://bbs.example.invalid'),
  apiOrigin: Uri.parse('https://api.example.invalid'),
  userAgent: 'yamibo-forum-client-test',
);

YamiboForumClientBuilder _builder({
  ForumClientNetwork? network,
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

final class _ResourceCapableNetwork extends _CountingNetwork
    implements ForumResourceClient {
  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) async {
    return ForumResourceSuccess(
      uri: request.reference.uri,
      statusCode: 200,
      content: Stream<List<int>>.value(const <int>[0xff, 0xd8, 0xff]),
      contentLength: 3,
      contentType: 'image/jpeg',
      validUntil: DateTime.utc(2026, 1, 1),
      fileExtension: '.jpg',
    );
  }
}

class _CountingNetwork implements ForumClientNetwork {
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

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(this._responses);

  final List<Object?> _responses;
  final List<String> modules = <String>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    modules.add(request.uri.queryParameters['module'] ?? '');
    if (_responses.isEmpty) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.network,
          code: 'fixture_exhausted',
        ),
      );
    }
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: _responses.removeAt(0),
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

final class _ThrowingSessionStore implements ForumSessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> merge(ForumSessionSnapshot snapshot) async {
    throw StateError('fixture persistence failure');
  }

  @override
  ForumSessionSnapshot? readCurrent() => null;

  @override
  String? readFreshFormhash() => null;
}
