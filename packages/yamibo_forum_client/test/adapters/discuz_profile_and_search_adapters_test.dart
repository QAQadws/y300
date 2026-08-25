import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/data_source_contracts/repository_contract_suites.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
    userAgent: 'mobile-test',
    desktopUserAgent: 'desktop-test',
  );

  runCurrentUserProfileContractSuite(
    () => CurrentUserProfileContractDriver(
      name: 'Discuz v4 API',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixedNetwork(_currentProfileBody),
      ).createCurrentUserProfile(),
    ),
  );
  runForumUserProfileContractSuite(
    () => ForumUserProfileContractDriver(
      name: 'Discuz mobile profile HTML',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _ScenarioNetwork(profileBody: _profileHtml),
      ).createForumUserProfile(),
      query: const ForumUserProfileQuery(userId: '509957'),
    ),
  );
  runForumSearchContractSuite(
    () => ForumSearchContractDriver(
      name: 'Discuz mobile search HTML',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _ScenarioNetwork(),
      ).createForumSearch(const _Formhash()),
      query: const ForumSearchQuery(keyword: 'fixture'),
    ),
  );
  runUserBlogDirectoryContractSuite(
    () => UserBlogDirectoryContractDriver(
      name: 'Discuz mobile blog directory HTML',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixedNetwork(_blogDirectoryHtml),
      ).createUserBlogDirectory(),
      query: const UserBlogDirectoryQuery.public(),
    ),
  );
  runUserBlogDetailContractSuite(
    () => UserBlogDetailContractDriver(
      name: 'Discuz mobile blog detail HTML',
      createRepository: () => ForumClientAdapterFactory(
        config: config,
        network: _FixedNetwork(_blogDetailHtml),
      ).createUserBlogDetail(),
      query: const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
    ),
  );

  test(
    'public profile adapter returns source-neutral identity and fields',
    () async {
      final network = _ScenarioNetwork(profileBody: _profileHtml);
      final repository = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createForumUserProfile();

      final result = await repository.load(
        const ForumUserProfileQuery(userId: '509957'),
      );

      final success =
          result
              as DataReadSuccess<
                ForumUserProfileData,
                ForumUserProfileReadCapabilities
              >;
      expect(success.data.identity.userId, '509957');
      expect(success.data.identity.displayName, 'Fixture user');
      expect(success.data.details.single.label, 'UID');
      expect(success.data.details.single.value, '509957');
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(network.requests.single.uri.queryParameters['uid'], '509957');
    },
  );

  test('search owns formhash, POST context and opaque continuation', () async {
    final network = _ScenarioNetwork();
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());
    const query = ForumSearchQuery(
      keyword: 'fixture',
      scope: ForumSearchScope.allForums,
    );

    final first = await repository.load(query);

    final firstSuccess =
        first as DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities>;
    expect(firstSuccess.data.topics.single.tid, '100');
    expect(firstSuccess.data.pagination.nextPage, isNotNull);
    expect(network.requests.first.method, ForumRequestMethod.post);
    expect(
      network.requests.first.body,
      containsPair('formhash', 'fixture-formhash'),
    );

    final second = await repository.loadNextPage(
      query,
      firstSuccess.data.pagination.nextPage!,
    );

    expect(second.dataOrNull!.topics.single.tid, '101');
    expect(network.requests, hasLength(3));
    expect(network.requests.last.uri.queryParameters['searchid'], '777');
    expect(network.requests.last.uri.queryParameters['page'], '2');
  });

  test(
    'current-forum search accepts canonical Discuz result redirects',
    () async {
      final network = _ScenarioNetwork(
        postLocation: 'search.php?mod=forum&searchid=777&searchsubmit=yes',
      );
      final repository = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createForumSearch(const _Formhash());
      const query = ForumSearchQuery(
        keyword: 'fixture',
        scope: ForumSearchScope.currentForum,
        forumId: '30',
      );

      final first = await repository.load(query);

      final firstSuccess =
          first
              as DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities>;
      expect(firstSuccess.data.topics.single.forumId, '30');
      expect(firstSuccess.data.pagination.nextPage, isNotNull);
      expect(network.requests.first.uri.queryParameters['mod'], 'curforum');
      expect(network.requests.first.uri.queryParameters['srhfid'], '30');
      expect(network.requests.first.body, containsPair('srhfid', '30'));

      final second = await repository.loadNextPage(
        query,
        firstSuccess.data.pagination.nextPage!,
      );

      expect(second.dataOrNull!.topics.single.tid, '101');
      expect(network.requests, hasLength(3));
    },
  );

  test('current-forum search keeps exact scoped redirects valid', () async {
    final network = _ScenarioNetwork(
      postLocation:
          'search.php?mod=curforum&srhfid=30&searchid=777&searchsubmit=yes',
    );
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());

    final result = await repository.load(
      const ForumSearchQuery(
        keyword: 'fixture',
        scope: ForumSearchScope.currentForum,
        forumId: '30',
      ),
    );

    expect(result.failureOrNull, isNull);
    expect(network.requests, hasLength(2));
  });

  test(
    'current-forum search rejects an explicitly conflicting forum',
    () async {
      final network = _ScenarioNetwork(
        postLocation:
            'search.php?mod=forum&srhfid=99&searchid=777&searchsubmit=yes',
      );
      final repository = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createForumSearch(const _Formhash());

      final result = await repository.load(
        const ForumSearchQuery(
          keyword: 'fixture',
          scope: ForumSearchScope.currentForum,
          forumId: '30',
        ),
      );

      expect(result.failureOrNull?.code, 'forum_search_context_invalid');
      expect(network.requests, hasLength(1));
    },
  );

  test('current-forum search rejects topics from another forum', () async {
    final network = _ScenarioNetwork(
      postLocation: 'search.php?mod=forum&searchid=777&searchsubmit=yes',
      initialBody: _searchPage(tid: '100', forumId: '99', nextPage: null),
    );
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());

    final result = await repository.load(
      const ForumSearchQuery(
        keyword: 'fixture',
        scope: ForumSearchScope.currentForum,
        forumId: '30',
      ),
    );

    expect(result.failureOrNull?.code, 'search_forum_identity_mismatch');
    expect(network.requests, hasLength(2));
  });

  test('current-forum search allows a proven empty result', () async {
    final network = _ScenarioNetwork(
      postLocation: 'search.php?mod=forum&searchid=777&searchsubmit=yes',
      initialBody: '<ul class="threadlist"></ul>',
    );
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());

    final result = await repository.load(
      const ForumSearchQuery(
        keyword: 'fixture',
        scope: ForumSearchScope.currentForum,
        forumId: '30',
      ),
    );

    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.topics, isEmpty);
  });

  test('search keeps invalid result contexts fail closed', () async {
    for (final location in <String>[
      'search.php?mod=forum',
      'search.php?mod=forum&searchid=777&searchid=779',
      'search.php?mod=forum&searchid=777&page=2',
      'search.php?mod=forum&mod=curforum&searchid=777',
      'https://other.test/search.php?mod=forum&searchid=777',
      'http://example.test/search.php?mod=forum&searchid=777',
    ]) {
      final network = _ScenarioNetwork(postLocation: location);
      final repository = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createForumSearch(const _Formhash());

      final result = await repository.load(
        const ForumSearchQuery(keyword: 'fixture'),
      );

      expect(
        result.failureOrNull?.code,
        'forum_search_context_invalid',
        reason: location,
      );
      expect(network.requests, hasLength(1), reason: location);
    }
  });

  test('all-forum search does not accept a scoped result context', () async {
    final network = _ScenarioNetwork(
      postLocation:
          'search.php?mod=forum&srhfid=30&searchid=777&searchsubmit=yes',
    );
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());

    final result = await repository.load(
      const ForumSearchQuery(keyword: 'fixture'),
    );

    expect(result.failureOrNull?.code, 'forum_search_context_invalid');
    expect(network.requests, hasLength(1));
  });

  test('search rejects invalid query before formhash or transport', () async {
    final network = _ScenarioNetwork();
    final repository = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createForumSearch(const _Formhash());

    final result = await repository.load(
      const ForumSearchQuery(keyword: '   ', scope: ForumSearchScope.allForums),
    );

    expect(result.failureOrNull!.kind, DataReadFailureKind.business);
    expect(network.requests, isEmpty);
  });
}

final class _ScenarioNetwork implements ForumClientNetwork {
  _ScenarioNetwork({this.profileBody, this.postLocation, this.initialBody});

  final String? profileBody;
  final String? postLocation;
  final String? initialBody;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (profileBody != null) {
      return _response(request, profileBody!);
    }
    if (request.method == ForumRequestMethod.post) {
      return ForumTransportSuccess(
        ForumResponse(
          uri: request.uri,
          statusCode: 302,
          headers: {
            'location': [
              postLocation ??
                  'search.php?mod=forum&searchid=777&searchsubmit=yes',
            ],
          },
          body: '',
        ),
      );
    }
    final page = request.uri.queryParameters['page'];
    return _response(
      request,
      page == '2'
          ? _searchPage(tid: '101', nextPage: null)
          : initialBody ?? _searchPage(tid: '100', nextPage: 2),
    );
  }

  ForumTransportResult<ForumResponse<Object?>> _response(
    ForumRequest request,
    String body,
  ) => ForumTransportSuccess(
    ForumResponse(
      uri: request.uri,
      statusCode: 200,
      headers: const {},
      body: body,
    ),
  );
}

final class _FixedNetwork implements ForumClientNetwork {
  _FixedNetwork(this.body);

  final Object? body;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async => ForumTransportSuccess(
    ForumResponse(
      uri: request.uri,
      statusCode: 200,
      headers: const {},
      body: body,
    ),
  );
}

final class _Formhash implements ForumFormhashProvider {
  const _Formhash();

  @override
  Future<ForumFormhashResult> loadFormhash({bool preferProfile = true}) async {
    return const ForumFormhashSuccess('fixture-formhash');
  }
}

String _searchPage({
  required String tid,
  String forumId = '30',
  required int? nextPage,
}) =>
    '''
<ul class="threadlist"><li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=$tid&amp;mobile=2">
    <div class="threadlist_tit"><em>Fixture $tid</em></div>
  </a>
  <div class="threadlist_foot"><a href="forum.php?mod=forumdisplay&amp;fid=$forumId&amp;mobile=2">Forum</a></div>
</li></ul>
${nextPage == null ? '' : '<div class="pg"><a class="nxt" href="search.php?mod=forum&amp;searchid=777&amp;page=$nextPage&amp;mobile=2">Next</a></div>'}
''';

const _profileHtml = '''
<html><body><div class="userinfo">
  <div class="avatar_m"><img src="/avatar.jpg"></div>
  <h2 class="name">Fixture user</h2>
  <div class="myinfo_list"><ul>
    <li><b>Profile</b></li><li>UID<span>509957</span></li>
  </ul></div>
</div><a href="member.php?mod=logging&amp;action=logout">Logout</a></body></html>
''';

const _currentProfileBody = <String, Object?>{
  'Variables': <String, Object?>{
    'member_uid': '509957',
    'member_username': 'Fixture user',
    'space': <String, Object?>{
      'uid': '509957',
      'username': 'Fixture user',
      'credits': '12',
      'posts': '3',
      'threads': '1',
    },
  },
};

const _blogDirectoryHtml = '''
<html><body>
  <div class="dhnv"><a class="mon" href="home.php?mod=space&amp;do=blog&amp;view=all">Public</a></div>
  <div id="dhnavs_li"><ul><li class="mon"><a href="home.php?mod=space&amp;do=blog&amp;view=all">Latest</a></li></ul></div>
  <div class="threadlist"><ul><li class="list">
    <div class="threadlist_top"><a class="avatar"><img src="/avatar.jpg"></a><div class="muser"><h3><a href="home.php?mod=space&amp;uid=101&amp;do=profile">Author</a></h3><div class="mtime"><span>Today</span></div></div></div>
    <a href="home.php?mod=space&amp;uid=101&amp;do=blog&amp;id=11"><div class="threadlist_tit">Fixture blog</div><div class="threadlist_mes">Excerpt</div></a>
  </li></ul></div>
</body></html>
''';

const _blogDetailHtml = '''
<html><body><div class="viewthread">
  <div class="view_tit">Fixture blog</div>
  <div class="plc">
    <div class="avatar"><img src="/owner.jpg"></div>
    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&amp;uid=101">Owner</a></li><li class="mtime">Today</li></ul>
    <div class="message"><p>Body</p></div>
    <div class="threadlist_foot"><a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=blog&amp;id=11">Favorite</a></div>
  </div>
  <div class="doing_list_box"></div>
</div></body></html>
''';
