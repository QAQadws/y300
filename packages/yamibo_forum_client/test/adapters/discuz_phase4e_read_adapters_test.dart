import 'dart:convert';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/src/adapters/forum_home_snapshot_codec.dart';

import '../support/data_source_contracts/repository_contract_suites.dart';
import '../fixtures/thread_post_navigation_fixtures.dart';

void main() {
  late ForumClientConfig config;

  setUp(() {
    config = ForumClientConfig(
      siteOrigin: Uri.parse('https://bbs.example.test'),
      apiOrigin: Uri.parse('https://api.example.test/mobile/index.php'),
      userAgent: 'mobile-fixture',
      desktopUserAgent: 'desktop-fixture',
    );
  });

  runForumHomeContractSuite(
    () => ForumHomeContractDriver(
      name: 'mobile HTML',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _forumHomeHtml),
      ).createHtmlForumHome().home,
    ),
  );

  runForumNotificationContractSuite(
    () => ForumNotificationContractDriver(
      name: 'Discuz notifications',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _notificationEnvelope),
      ).createNotifications(),
    ),
  );

  runForumPrivateMessageContractSuite(
    () => ForumPrivateMessageContractDriver(
      name: 'Discuz private messages',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _messageEnvelope),
      ).createPrivateMessages(),
    ),
  );

  runForumStickerCatalogContractSuite(
    () => ForumStickerCatalogContractDriver(
      name: 'Discuz sticker catalog',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _stickerEnvelope),
      ).createStickerCatalog(store: _MemoryStickerStore()),
    ),
  );

  runThreadPostRatingsContractSuite(
    () => ThreadPostRatingsContractDriver(
      name: 'Discuz AJAX ratings',
      query: const ThreadPostRatingsQuery(tid: '100', pid: '200'),
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _ratingsAjax),
      ).createThreadPostRatings(),
    ),
  );

  runThreadPostLocatorContractSuite(
    () => ThreadPostLocatorContractDriver(
      name: 'Discuz findpost redirect',
      query: const ThreadPostLocationQuery(tid: '100', pid: '200'),
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork(
          (_) => mobilePostLocationHtml,
          responseUri: Uri.parse(
            'https://bbs.example.test/forum.php?mod=viewthread&tid=100&page=3',
          ),
        ),
      ).createThreadPostLocator(),
    ),
  );

  runThreadAuthorPostContractSuite(
    () => ThreadAuthorPostContractDriver(
      name: 'Discuz author posts',
      query: const ThreadAuthorPostQuery(
        tid: '100',
        authorId: '10',
        page: 2,
        pageSize: 200,
      ),
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixtureNetwork((_) => _authorPostEnvelope),
      ).createThreadAuthorPosts(),
    ),
  );

  test('forum home loads directory, carousel and favorites once', () async {
    final network = _FixtureNetwork((_) => _forumHomeHtml);
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createHtmlForumHome().home;

    final home = await repository.loadHome(const ForumHomeQuery());

    expect(network.requests, hasLength(1));
    expect(network.requests.single.uri.path, '/index.php');
    expect(network.requests.single.uri.queryParameters['mobile'], '2');
    final data = home.dataOrNull!;
    expect(data.directory.sections.single.forums.single.fid, '30');
    expect(data.carousel.single.imageUri.path, '/banner.jpg');
    expect(data.favoriteForums.single.fid, '16');
  });

  test(
    'forum home snapshot codec reads legacy layout and ignores aspect ratio',
    () {
      const codec = ForumHomeSnapshotCodec();

      final decoded = codec.decode(<String, Object?>{
        'homeSections': <Object?>[
          <String, Object?>{
            'kind': 'regular',
            'title': 'Legacy',
            'items': <Object?>[
              <String, Object?>{
                'fid': '30',
                'title': 'Forum',
                'description': 'Description',
                'todayPosts': 1,
              },
            ],
          },
        ],
        'chromeData': <String, Object?>{
          'carouselItems': <Object?>[
            <String, Object?>{
              'imageUrl': 'https://bbs.example.test/banner.jpg',
              'targetUrl': 'https://bbs.example.test/thread-100-1-1.html',
              'aspectRatio': 3.5,
            },
          ],
        },
      });

      expect(codec.canDecodeVersion(codecVersion: 2, parserVersion: 2), isTrue);
      expect(decoded.directory.sections.single.title, 'Legacy');
      expect(decoded.carousel.single.imageUri.path, '/banner.jpg');
    },
  );

  test('messages and notifications keep independent API contracts', () async {
    final network = _FixtureNetwork((request) {
      return switch (request.uri.queryParameters['module']) {
        'mynotelist' => _notificationEnvelope,
        'mypm' => _messageEnvelope,
        _ => const <String, Object?>{},
      };
    });
    final factory = ForumClientAdapterFactory(config: config, network: network);

    final notifications = await factory.createNotifications().load(
      const ForumNotificationQuery(),
    );
    final messages = await factory.createPrivateMessages().load(
      const ForumPrivateMessageQuery(),
    );

    expect(network.requests.map((item) => item.uri.queryParameters['module']), [
      'mynotelist',
      'mypm',
    ]);
    expect(notifications.dataOrNull!.items.single.id, 'notice-1');
    expect(notifications.dataOrNull!.items.single.occurredAt, isNotNull);
    expect(messages.dataOrNull!.items.single.messageId, 'pm-1');
    expect(messages.dataOrNull!.items.single.conversationId, 'conversation-1');
    expect(messages.dataOrNull!.items.single.sentAt, DateTime(2026, 1, 1, 12));
  });

  test('sticker catalog normalizes codes and uses its cache store', () async {
    final store = _MemoryStickerStore();
    final network = _FixtureNetwork((_) => _stickerEnvelope);
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createStickerCatalog(store: store);

    final first = await repository.load(const ForumStickerCatalogQuery());
    final second = await repository.load(const ForumStickerCatalogQuery());

    expect(first.dataOrNull!.groups.single.id, 'default');
    expect(
      first.dataOrNull!.groups.single.items.single.insertionCode,
      '{:1_1:}',
    );
    expect(store.encoded, isNotNull);
    expect(second.dataOrNull!.refreshed, isFalse);
    expect(network.requests, hasLength(1));
  });

  test('sticker catalog falls back to a stale legacy cache', () async {
    final store = _MemoryStickerStore()
      ..encoded = jsonEncode(<String, Object?>{
        'raw': _stickerEnvelope,
        'fetchedAt': 0,
        'module': 'smiley',
        'version': '4',
      });
    final repository = ForumClientAdapterFactory(
      config: config,
      network: _FailingNetwork(),
    ).createStickerCatalog(store: store);

    final result = await repository.load(
      const ForumStickerCatalogQuery(),
      cachePolicy: CacheLoadPolicy.networkFirst,
    );

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.groups.single.id, 'default');
    expect(
      result.when(
        success: (_, _, metadata) => metadata.freshness,
        failure: (_) => DataReadFreshness.current,
      ),
      DataReadFreshness.staleOrUnknown,
    );
  });

  test('ratings use the fixed AJAX request and parse CDATA HTML', () async {
    final network = _FixtureNetwork((_) => _ratingsAjax);
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPostRatings();

    final result = await repository.load(
      const ThreadPostRatingsQuery(tid: '100', pid: '200'),
    );

    final query = network.requests.single.uri.queryParameters;
    expect(query['action'], 'viewratings');
    expect(query['inajax'], '1');
    expect(query['ajaxtarget'], 'fwin_content_viewratings');
    expect(result.dataOrNull!.participantCount, 1);
    expect(result.dataOrNull!.ratings.single.userId, '10');
    expect(result.dataOrNull!.totalScoreText, '积分 +2 点');
  });

  test('post locator validates the final page identity', () async {
    final network = _FixtureNetwork(
      (_) => mobilePostLocationHtml,
      responseUri: Uri.parse(
        'https://bbs.example.test/forum.php?mod=viewthread&tid=100&page=3',
      ),
    );
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPostLocator();

    final result = await repository.locate(
      const ThreadPostLocationQuery(tid: '100', pid: '200'),
    );

    final request = network.requests.single.uri.queryParameters;
    expect(request['goto'], 'findpost');
    expect(request['mobile'], '2');
    expect(
      request.keys,
      unorderedEquals(['mod', 'goto', 'ptid', 'pid', 'mobile']),
    );
    expect(network.requests.single.headers['User-Agent'], 'mobile-fixture');
    expect(request['ptid'], '100');
    expect(request['pid'], '200');
    expect(result.dataOrNull!.page, 3);
  });

  for (final path in [
    '/forum.php?mod=viewthread&tid=100&page=3&mobile=2',
    '/thread-100-3-1.html',
    '/forum.php?mod=viewthread&tid=100&page=3&ordertype=1',
  ]) {
    test('post locator accepts verified ordinary mobile view $path', () async {
      final network = _FixtureNetwork(
        (_) => mobilePostLocationHtml,
        responseUri: config.siteOrigin.resolve(path),
      );
      final result =
          await ForumClientAdapterFactory(config: config, network: network)
              .createThreadPostLocator()
              .locate(const ThreadPostLocationQuery(tid: '100', pid: '200'));
      expect(result.dataOrNull?.page, 3);
      expect(result.dataOrNull?.pid, '200');
    });
  }

  final rejected = <String, (String, String)>{
    'wrong URL identity': (
      '/forum.php?mod=viewthread&tid=101&page=3',
      mobilePostLocationHtml,
    ),
    'wrong document identity': (
      '/forum.php?mod=viewthread&tid=100&page=3',
      mobilePostLocationHtml.replaceAll('thread-100-', 'thread-101-'),
    ),
    'target missing on home': (
      '/forum.php?mod=viewthread&tid=100',
      mobilePostMissingHtml,
    ),
    'forum home': ('/index.php', _forumHomeHtml),
    'unresolved redirect': (
      '/forum.php?mod=redirect&goto=findpost&ptid=100&pid=200',
      mobilePostLocationHtml,
    ),
    'desktop pagination': (
      '/forum.php?mod=viewthread&tid=100&page=7',
      desktopPostLocationHtml,
    ),
    'mobile disabled': (
      '/forum.php?mod=viewthread&tid=100&page=3&mobile=no',
      mobilePostLocationHtml,
    ),
    'filtered view': (
      '/forum.php?mod=viewthread&tid=100&page=3&authorid=10',
      mobilePostLocationHtml,
    ),
    'cross site': (
      'https://elsewhere.example/thread-100-3-1.html',
      mobilePostLocationHtml,
    ),
  };
  for (final item in rejected.entries) {
    test('post locator rejects ${item.key}', () async {
      final result =
          await ForumClientAdapterFactory(
            config: config,
            network: _FixtureNetwork(
              (_) => item.value.$2,
              responseUri: config.siteOrigin.resolve(item.value.$1),
            ),
          ).createThreadPostLocator().locate(
            const ThreadPostLocationQuery(tid: '100', pid: '200'),
          );
      expect(result.isSuccess, isFalse);
    });
  }

  for (final status in [200, 401, 403]) {
    test('post locator classifies permission evidence $status', () async {
      final result =
          await ForumClientAdapterFactory(
            config: config,
            network: _FixtureNetwork(
              (_) => loginRequiredPostHtml,
              statusCode: status,
              responseUri: config.siteOrigin.resolve(
                '/forum.php?mod=viewthread&tid=100',
              ),
            ),
          ).createThreadPostLocator().locate(
            const ThreadPostLocationQuery(tid: '100', pid: '200'),
          );
      expect(result.isSuccess, isFalse);
      expect(
        result.failureOrNull?.code,
        status == 403
            ? 'thread_post_location_permission_denied'
            : 'thread_post_location_login_required',
      );
    });
  }

  test('post locator does not retry transport errors', () async {
    final result =
        await ForumClientAdapterFactory(
          config: config,
          network: _FailingNetwork(),
        ).createThreadPostLocator().locate(
          const ThreadPostLocationQuery(tid: '100', pid: '200'),
        );
    expect(result.failureOrNull?.kind, DataReadFailureKind.network);
  });

  test('custom page size is not an ordinary pagination environment', () async {
    final result =
        await ForumClientAdapterFactory(
          config: config,
          network: _FixtureNetwork(
            (_) => mobilePostLocationHtml,
            responseUri: config.siteOrigin.resolve(
              '/forum.php?mod=viewthread&tid=100&page=3&ppp=200',
            ),
          ),
        ).createThreadPostLocator().locate(
          const ThreadPostLocationQuery(tid: '100', pid: '200'),
        );
    expect(result.failureOrNull?.code, 'thread_post_location_view_unconfirmed');
  });

  for (final status in [301, 404]) {
    test(
      'unsuccessful status $status cannot pass by carrying post markup',
      () async {
        final result =
            await ForumClientAdapterFactory(
              config: config,
              network: _FixtureNetwork(
                (_) => mobilePostLocationHtml,
                statusCode: status,
                responseUri: config.siteOrigin.resolve('/thread-100-3-1.html'),
              ),
            ).createThreadPostLocator().locate(
              const ThreadPostLocationQuery(tid: '100', pid: '200'),
            );
        expect(result.isSuccess, isFalse);
      },
    );
  }

  test('server error cannot pass by carrying cached post markup', () async {
    final result =
        await ForumClientAdapterFactory(
          config: config,
          network: _FixtureNetwork(
            (_) => mobilePostLocationHtml,
            statusCode: 503,
            responseUri: config.siteOrigin.resolve('/thread-100-3-1.html'),
          ),
        ).createThreadPostLocator().locate(
          const ThreadPostLocationQuery(tid: '100', pid: '200'),
        );
    expect(result.failureOrNull?.kind, DataReadFailureKind.server);
  });

  test(
    'long body and empty interactions do not affect post identity',
    () async {
      final result =
          await ForumClientAdapterFactory(
            config: config,
            network: _FixtureNetwork(
              (_) => longMobilePostLocationHtml,
              responseUri: config.siteOrigin.resolve('/thread-100-3-1.html'),
            ),
          ).createThreadPostLocator().locate(
            const ThreadPostLocationQuery(tid: '100', pid: '200'),
          );
      expect(result.dataOrNull?.page, 3);
    },
  );

  test('author posts are permanently wired to viewthread version 1', () async {
    final network = _FixtureNetwork((_) => _authorPostEnvelope);
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadAuthorPosts();

    final result = await repository.load(
      const ThreadAuthorPostQuery(
        tid: '100',
        authorId: '10',
        page: 2,
        pageSize: 200,
      ),
    );

    expect(
      network.requests.single.uri.queryParameters,
      containsPair('version', '1'),
    );
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('ppp', '200'),
    );
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('authorid', '10'),
    );
    expect(result.dataOrNull!.posts.single.authorId, '10');
    expect(result.dataOrNull!.currentPage, 2);
  });
}

final class _FixtureNetwork implements ForumClientNetwork {
  _FixtureNetwork(this.bodyFor, {this.responseUri, this.statusCode = 200});

  final int statusCode;

  final Object? Function(ForumRequest request) bodyFor;
  final Uri? responseUri;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: responseUri ?? request.uri,
        statusCode: statusCode,
        headers: const {},
        body: bodyFor(request),
      ),
    );
  }
}

final class _FailingNetwork implements ForumClientNetwork {
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async => const ForumTransportError(
    ForumTransportFailure(
      kind: ForumTransportFailureKind.network,
      code: 'offline',
    ),
  );
}

final class _MemoryStickerStore implements ForumStickerCatalogStore {
  String? encoded;

  @override
  Future<void> clear() async => encoded = null;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String encoded) async => this.encoded = encoded;
}

const _forumHomeHtml = '''
<html><body id="forum">
  <div class="index-top-wrapper"><div class="yami-swiper">
    <div class="swiper-slide"><a href="thread-100-1-1.html"><img src="/banner.jpg"></a></div>
  </div></div>
  <div class="forumlist">
    <a class="subforumshow" href="#regular"><h2>Regular</h2></a>
    <div id="regular"><a class="murl" href="forum.php?mod=forumdisplay&fid=30">
      <span class="mtit">Forum 3<span class="mnum">3</span></span><span class="mtxt">Description</span>
    </a></div>
    <a class="subforumshow" href="#sub-forum-myfav"><h2>Favorites</h2></a>
    <div id="sub-forum-myfav"><a class="murl" href="forum.php?mod=forumdisplay&fid=16">
      <span class="mtit">Favorite</span><span class="mtxt">Saved</span>
    </a></div>
  </div>
</body></html>
''';

const _notificationEnvelope = <String, Object?>{
  'Version': '4',
  'Variables': <String, Object?>{
    'count': '1',
    'page': '1',
    'perpage': '20',
    'list': <Object?>[
      <String, Object?>{
        'id': 'notice-1',
        'type': 'post',
        'new': '1',
        'authorid': '10',
        'author': 'Alice',
        'note': 'Fixture notice',
        'dateline': '1767225600',
      },
    ],
  },
};

const _messageEnvelope = <String, Object?>{
  'Version': '4',
  'Variables': <String, Object?>{
    'count': '1',
    'page': '1',
    'perpage': '20',
    'list': <Object?>[
      <String, Object?>{
        'pmid': 'pm-1',
        'plid': 'conversation-1',
        'isnew': '1',
        'subject': 'Fixture message',
        'msgfromid': '11',
        'msgfrom': 'Bob',
        'touid': '12',
        'tousername': 'Carol',
        'message': 'Preview',
        'vdateline': '2026-01-01 12:00',
      },
    ],
  },
};

const _stickerEnvelope = <String, Object?>{
  'Version': '4',
  'Variables': <String, Object?>{
    'smilies': <Object?>[
      <Object?>[
        <String, Object?>{
          'code': r'/\{\:1_1\:\}/',
          'image': 'default/fixture.gif',
        },
      ],
    ],
  },
};

const _ratingsAjax = '''
<root><![CDATA[
<div class="f_c"><table class="list">
<tr><td>积分</td><td>用户名</td><td>时间</td><td>理由</td></tr>
<tr><td>积分 +2 点</td><td><a href="space-uid-10.html">Alice</a></td><td>2026-01-01</td><td>Agree</td></tr>
</table></div><div class="o pns">总计: 积分 +2 点</div>
]]></root>
''';

const _authorPostEnvelope = <String, Object?>{
  'Version': '1',
  'Variables': <String, Object?>{
    'fid': '33',
    'ppp': '200',
    'thread': <String, Object?>{
      'tid': '100',
      'fid': '33',
      'subject': 'Fixture novel',
      'author': 'Alice',
      'replies': '201',
      'views': '300',
    },
    'postlist': <Object?>[
      <String, Object?>{
        'pid': '200',
        'author': 'Alice',
        'authorid': '10',
        'message': 'Chapter',
        'number': '201',
        'first': '0',
        'dateline': '2026-01-01',
      },
    ],
  },
};
