import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late MemoryForumSessionStore sessions;
  late ForumFriendFeedRepository repository;
  setUp(() async {
    network = _Network();
    sessions = MemoryForumSessionStore();
    await sessions.merge(_session('7'));
    repository = ForumClientAdapterFactory(
      config: _config,
      network: network,
      sessionStore: sessions,
    ).createFriendFeed();
  });

  for (final scope in ForumFriendFeedScope.values) {
    test('reads the authenticated ${scope.name} touch list', () async {
      network.body = _page(scope: scope);
      final result = await repository.load(
        ForumFriendFeedQuery(accountUserId: '7', scope: scope),
      );
      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.currentUserId, '7');
      expect(page.scope, scope);
      expect(page.items.single.userId, '12');
      expect(page.items.single.username, 'A & 友');
      expect(
        page.items.single.profileUrl,
        'https://forum.example.test/home.php?mod=space&uid=12',
      );
      expect(page.items.single.note, '最近的近况');
      expect(
        page.items.single.avatarUrl,
        'https://forum.example.test/avatar.php?uid=12',
      );
      expect(page.items.single.visitedAtText, isNull);
      expect(
        page.items.single.isOnline,
        scope == ForumFriendFeedScope.online ? isTrue : isNull,
      );
      expect(
        page.items.single.canRemove,
        scope == ForumFriendFeedScope.friends,
      );
      expect(() => page.items.clear(), throwsUnsupportedError);
      final request = network.requests.single;
      expect(request.method, ForumRequestMethod.get);
      expect(request.headers['User-Agent'], 'mobile');
      expect(request.uri.queryParameters, {
        'mod': 'space',
        'do': 'friend',
        'uid': '7',
        'page': '1',
        'mobile': '2',
        ...switch (scope) {
          ForumFriendFeedScope.friends => <String, String>{},
          ForumFriendFeedScope.online => {'view': 'online', 'type': 'member'},
          ForumFriendFeedScope.visitors => {'view': 'visitor'},
          ForumFriendFeedScope.footprints => {'view': 'trace'},
        },
      });
      expect(request.followRedirects, isFalse);
    });
  }

  test(
    'stock empty touch page succeeds from authenticated navigation proof',
    () async {
      network.body = _page(rows: '');
      final page = (await repository.load(_query)).dataOrNull!;
      expect(page.items, isEmpty);
      expect(page.hasNext, isFalse);
      expect(page.count, isNull);
      expect(page.totalPages, isNull);
    },
  );

  test(
    'anonymous visitors remain visible without actionable identities',
    () async {
      const anonymous =
          '<li><span class="mimg"><img src="/static/image/magic/hidden.gif"></span><p class="mtit"><a href="javascript:;">匿名</a></p></li>';
      network.body = _page(
        scope: ForumFriendFeedScope.visitors,
        rows: '$anonymous$anonymous',
      );
      final page = (await repository.load(
        const ForumFriendFeedQuery(
          accountUserId: '7',
          scope: ForumFriendFeedScope.visitors,
        ),
      )).dataOrNull!;
      expect(page.items, hasLength(2));
      expect(
        page.items.every(
          (item) =>
              item.userId.isEmpty && item.profileUrl == null && !item.canRemove,
        ),
        isTrue,
      );
    },
  );

  test('source profile links retain their original query and fragment', () async {
    network.body = _page(
      rows: _row().replaceAll(
        'href="home.php?mod=space&amp;uid=12"',
        'href="home.php?mod=space&amp;uid=12&amp;do=profile&amp;from=space&amp;mobile=2#details"',
      ),
    );
    final item = (await repository.load(_query)).dataOrNull!.items.single;
    expect(item.userId, '12');
    expect(
      item.profileUrl,
      'https://forum.example.test/home.php?mod=space&uid=12&do=profile&from=space&mobile=2#details',
    );
  });

  test(
    'the title link is retained after verifying the avatar member',
    () async {
      network.body = _page(
        rows: _row().replaceFirst(
          'href="home.php?mod=space&amp;uid=12"',
          'href="/home.php?mod=space&amp;uid=12&amp;do=profile&amp;mobile=2"',
        ),
      );
      final item = (await repository.load(_query)).dataOrNull!.items.single;
      expect(
        item.profileUrl,
        'https://forum.example.test/home.php?mod=space&uid=12',
      );
    },
  );

  test(
    'ambiguous title links and different avatar members fail closed',
    () async {
      for (final rows in [
        _row().replaceFirst(
          '</p>',
          '<a href="home.php?mod=space&amp;uid=12&amp;from=space">another destination</a></p>',
        ),
        _row().replaceFirst(
          'href="home.php?mod=space&amp;uid=12"',
          'href="home.php?mod=space&amp;uid=13"',
        ),
        _row().replaceFirst(
          'href="home.php?mod=space&amp;uid=12"',
          'href="https://foreign.test/home.php?mod=space&amp;uid=12"',
        ),
      ]) {
        network.body = _page(rows: rows);
        expect((await repository.load(_query)).isFailure, isTrue);
      }
    },
  );

  test('same-list next link and exact pager summary are parsed', () async {
    network.body = _page(
      pager:
          '<div class="pg"><em>49</em><strong>1</strong><label><input name="custompage" value="1"><span> / 3 页</span></label><a class="nxt" href="home.php?mod=space&amp;uid=7&amp;do=friend&amp;page=2">下一页</a></div>',
    );
    final page = (await repository.load(_query)).dataOrNull!;
    expect(page.hasNext, isTrue);
    expect(page.totalPages, 3);
    expect(page.count, 49);
  });

  test('foreign scopes, accounts, pages and malformed rows fail closed', () async {
    final fixtures = [
      _page(actor: '8'),
      _page(scope: ForumFriendFeedScope.online),
      _page().replaceAll('class="mon"', ''),
      _page().replaceAll('uid=12', 'uid=13&uid=12'),
      _page(rows: _row() + _row()),
      _page().replaceAll('uid=12', 'uid=0'),
      _page().replaceAll('class="imglist"', 'class="buddy"'),
      _page().replaceAll('<ul>', '<section>').replaceAll('</ul>', '</section>'),
      _page(pager: '<div class="pg"><strong>2</strong></div>'),
      _page(
        pager:
            '<div class="pg"><a class="nxt" href="home.php?mod=space&amp;do=friend&amp;view=visitor&amp;page=2">下一页</a></div>',
      ),
      _page(
        pager:
            '<div class="pg"><a class="nxt" href="https://other.test/home.php?mod=space&amp;do=friend&amp;page=2">下一页</a></div>',
      ),
      _page(
        pager:
            '<div class="pg"><a class="nxt" href="home.php?mod=space&amp;do=friend&amp;page=3">下一页</a></div>',
      ),
      '<html>private server payload</html>',
    ];
    for (final fixture in fixtures) {
      network.body = fixture;
      final result = await repository.load(_query);
      expect(result.isFailure, isTrue, reason: fixture);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private server payload')),
      );
    }
  });

  test(
    'login and disabled friend feature are safe classified failures',
    () async {
      network.body =
          '<form id="loginform"><input name="username"><input name="password"></form>';
      expect(
        (await repository.load(_query)).failureOrNull!.kind,
        DataReadFailureKind.unauthorized,
      );
      network.body = '<div id="messagetext">private server notice</div>';
      final failure = (await repository.load(_query)).failureOrNull!;
      expect(failure.kind, DataReadFailureKind.business);
      expect(failure.diagnosticMessage, 'friend_feed_unavailable');
    },
  );

  test('unsafe avatar references are omitted', () async {
    network.body = _page().replaceAll(
      '/avatar.php?uid=12',
      'javascript:alert(1)',
    );
    expect(
      (await repository.load(_query)).dataOrNull!.items.single.avatarUrl,
      isNull,
    );
  });

  test('invalid and cancelled queries send no requests', () async {
    final cancellation = ForumRequestCancellation()..cancel();
    for (final query in [
      const ForumFriendFeedQuery(accountUserId: '0'),
      const ForumFriendFeedQuery(accountUserId: '7', page: 0),
      ForumFriendFeedQuery(accountUserId: '7', cancellation: cancellation),
    ]) {
      expect((await repository.load(query)).isFailure, isTrue);
    }
    expect(network.requests, isEmpty);
  });

  test(
    'late account change or cancellation cannot publish an old page',
    () async {
      network.gate = Completer<void>();
      final pending = repository.load(_query);
      await Future<void>.delayed(Duration.zero);
      await sessions.merge(_session('8'));
      network.gate!.complete();
      expect(
        (await pending).failureOrNull!.kind,
        DataReadFailureKind.unauthorized,
      );
      await sessions.merge(_session('7'));
      network.gate = Completer<void>();
      final cancellation = ForumRequestCancellation();
      final cancelled = repository.load(
        ForumFriendFeedQuery(accountUserId: '7', cancellation: cancellation),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      network.gate!.complete();
      expect(
        (await cancelled).failureOrNull!.kind,
        DataReadFailureKind.cancelled,
      );
    },
  );

  test(
    'facade installation and source overlays retain independent friend sources',
    () async {
      final missing = YamiboForumClient(config: _config, network: network);
      expect(
        (await missing.loadFriendFeed(_query)).failureOrNull!.kind,
        DataReadFailureKind.unsupported,
      );
      final client = YamiboForumClientBuilder(
        config: _config,
        network: network,
        sessionStore: sessions,
      ).buildStandardClient();
      expect(client.friendFeed, isNotNull);
      expect(client.friendDirectory, isNotNull);
      expect(client.friendRemovalCommand, isNotNull);
      expect((await client.loadFriendFeed(_query)).isSuccess, isTrue);
      final plan = ForumClientSourcePlan(friendFeed: repository);
      expect(
        plan.overlay(const ForumClientSourcePlan()).friendFeed,
        same(repository),
      );
      expect(
        const ForumClientSourcePlan().overlay(plan).friendFeed,
        same(repository),
      );
    },
  );
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://forum.example.test'),
  userAgent: 'mobile',
  desktopUserAgent: 'desktop',
);
const _query = ForumFriendFeedQuery(accountUserId: '7');
ForumSessionSnapshot _session(String actor) => ForumSessionSnapshot(
  isLoggedIn: true,
  userId: actor,
  username: 'actor',
  formhash: 'a1b2c3d4',
  updatedAt: DateTime(2026),
  source: 'fixture',
);
String _url(ForumFriendFeedScope scope) =>
    'home.php?mod=space&amp;do=friend${switch (scope) {
      ForumFriendFeedScope.friends => '',
      ForumFriendFeedScope.online => '&amp;view=online&amp;type=member',
      ForumFriendFeedScope.visitors => '&amp;view=visitor',
      ForumFriendFeedScope.footprints => '&amp;view=trace',
    }}';
String _row({bool removal = true}) =>
    '<li><span class="mimg"><a href="home.php?mod=space&amp;uid=12"><img src="/avatar.php?uid=12"></a></span><p class="mtit">${removal ? '<a class="mico" href="home.php?mod=spacecp&amp;ac=friend&amp;op=ignore&amp;uid=12">删除</a>' : ''}<a class="mico" href="home.php?mod=space&amp;do=pm&amp;touid=12">发消息</a><a href="home.php?mod=space&amp;uid=12"><span>A &amp; 友</span></a></p><p class="mtxt">最近的近况</p></li>';
String _page({
  String actor = '7',
  ForumFriendFeedScope scope = ForumFriendFeedScope.friends,
  String? rows,
  String pager = '',
}) =>
    '<html><head><script>var discuz_uid = \'$actor\';</script></head><body><div class="header"><h2>我的好友</h2></div><div class="dhnv">${[for (final tab in ForumFriendFeedScope.values) '<a href="${_url(tab)}"${scope == tab ? ' class="mon"' : ''}>${tab.name}</a>'].join()}</div>${rows == '' ? '' : '<div id="friend_ul" class="imglist"><ul>${rows ?? _row(removal: scope == ForumFriendFeedScope.friends)}</ul></div>'}$pager</body></html>';

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  String body = _page();
  Completer<void>? gate;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await gate?.future;
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
