import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _FakeNetwork network;
  late ForumClientAdapterFactory factory;

  setUp(() {
    network = _FakeNetwork();
    factory = ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://example.test'),
        apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
        userAgent: 'mobile-test',
        desktopUserAgent: 'desktop-test',
      ),
      network: network,
    );
  });

  test(
    'forum directory uses forumindex v4 and maps stable identities',
    () async {
      network.body = {
        'Variables': {
          'catlist': [
            {
              'fid': 'cat-1',
              'name': 'Category',
              'forums': ['30'],
            },
          ],
          'forumlist': [
            {
              'fid': '30',
              'name': 'Forum',
              'description': 'Description',
              'todayposts': '2',
            },
          ],
        },
      };

      final result = await factory.createApiForumDirectory().load(
        const ForumDirectoryQuery(),
      );

      final success =
          result
              as DataReadSuccess<
                ForumDirectoryData,
                ForumDirectoryReadCapabilities
              >;
      expect(success.data.sections.single.forums.single.fid, '30');
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(network.requests, hasLength(1));
      expect(
        network.requests.single.uri.queryParameters['module'],
        'forumindex',
      );
      expect(network.requests.single.uri.queryParameters['version'], '4');
    },
  );

  test('HTML directory excludes favorites and keeps server order', () async {
    network.body = '''
      <div class="forumlist">
        <a class="subforumshow" href="#regular"><h2>Category</h2></a>
        <div id="regular">
          <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
            <span class="mtit">Forum <span class="mnum">2</span></span>
            <span class="mtxt">Description</span>
          </a>
        </div>
        <a class="subforumshow" href="#sub-forum-myfav"><h2>Favorites</h2></a>
        <div id="sub-forum-myfav">
          <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=99">
            <span class="mtit">Favorite</span>
          </a>
        </div>
      </div>
    ''';

    final result = await factory.createHtmlForumDirectory().load(
      const ForumDirectoryQuery(),
    );

    final success =
        result
            as DataReadSuccess<
              ForumDirectoryData,
              ForumDirectoryReadCapabilities
            >;
    expect(success.data.sections.single.identity, 'regular');
    expect(success.data.sections.single.forums.single.fid, '30');
    expect(success.data.sections.single.forums.single.todayPosts, 2);
    expect(
      success.capabilities.supports(ForumDirectoryCapability.nestedForums),
      isFalse,
    );
    expect(network.requests.single.uri.path, '/index.php');
    expect(network.requests.single.uri.queryParameters['mobile'], '2');
  });

  test(
    'HTML directory uses cached document after a transport failure',
    () async {
      final documents = MemoryForumDocumentStore();
      final config = ForumClientConfig(
        siteOrigin: Uri.parse('https://example.test'),
        apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
        userAgent: 'mobile-test',
      );
      final descriptor = ForumCacheKeyCanonicalizer(
        siteOrigin: config.siteOrigin,
      ).forumHome(requestProfile: ForumDocumentRequestProfile.anonymous);
      final now = DateTime.utc(2026);
      await documents.put(
        ForumCachedDocument(
          descriptor: descriptor,
          body: '''
          <div class="forumlist">
            <a class="subforumshow" href="#regular"><h2>Cached</h2></a>
            <div id="regular"><a class="murl" href="forum-30-1.html">
              <span class="mtit">Forum</span>
            </a></div>
          </div>
        ''',
          fetchedAt: now,
          updatedAt: now,
        ),
      );
      network.failure = const ForumTransportFailure(
        kind: ForumTransportFailureKind.network,
        code: 'offline',
      );
      final localFactory = ForumClientAdapterFactory(
        config: config,
        network: network,
        documentStore: documents,
      );

      final result = await localFactory.createHtmlForumDirectory().load(
        const ForumDirectoryQuery(),
      );

      final success =
          result
              as DataReadSuccess<
                ForumDirectoryData,
                ForumDirectoryReadCapabilities
              >;
      expect(success.data.sections.single.title, 'Cached');
      expect(success.metadata.origin, DataReadOrigin.cachedDocumentFallback);
      expect(success.metadata.freshness, DataReadFreshness.staleOrUnknown);
    },
  );

  test('favorite thread directory preserves exact pagination', () async {
    network.body = {
      'Variables': {
        'perpage': '1',
        'count': '2',
        'list': [
          {
            'id': '101',
            'title': 'Thread',
            'favid': '9001',
            'author': 'Author',
            'replies': '3',
            'dateline': '100',
          },
        ],
      },
    };

    final result = await factory.createFavoriteThreadDirectory().load(
      const FavoriteThreadDirectoryQuery(page: 1),
    );

    final success =
        result
            as DataReadSuccess<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >;
    expect(success.data.items.single.tid, '101');
    expect(success.data.pagination.totalPages, 2);
    expect(success.capabilities.paginationPrecision, PaginationPrecision.exact);
    expect(
      network.requests.single.uri.queryParameters['module'],
      'myfavthread',
    );
    expect(network.requests.single.uri.queryParameters['page'], '1');
  });

  test('business envelope is a sanitized failure', () async {
    network.body = {
      'Message': {'messageval': 'login_required', 'messagestr': 'private'},
      'Variables': <String, Object?>{},
    };

    final result = await factory.createFavoriteForumDirectory().load(
      const FavoriteForumDirectoryQuery(),
    );

    final failure =
        result
            as DataReadFailure<
              FavoriteForumDirectoryData,
              FavoriteForumDirectoryReadCapabilities
            >;
    expect(failure.kind, DataReadFailureKind.business);
    expect(failure.code, 'login_required');
    expect(failure.diagnosticMessage, isNot(contains('private')));
  });
}

final class _FakeNetwork implements ForumClientNetwork {
  Object? body;
  ForumTransportFailure? failure;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    final transportFailure = failure;
    if (transportFailure != null) {
      return ForumTransportError(transportFailure);
    }
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
