import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
    userAgent: 'mobile-test',
    desktopUserAgent: 'desktop-test',
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
  _ScenarioNetwork({this.profileBody});

  final String? profileBody;
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
          headers: const {
            'location': ['search.php?mod=forum&searchid=777&searchsubmit=yes'],
          },
          body: '',
        ),
      );
    }
    final page = request.uri.queryParameters['page'];
    return _response(
      request,
      _searchPage(
        tid: page == '2' ? '101' : '100',
        nextPage: page == '2' ? null : 2,
      ),
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

final class _Formhash implements ForumFormhashProvider {
  const _Formhash();

  @override
  Future<ForumFormhashResult> loadFormhash({bool preferProfile = true}) async {
    return const ForumFormhashSuccess('fixture-formhash');
  }
}

String _searchPage({required String tid, required int? nextPage}) =>
    '''
<ul class="threadlist"><li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=$tid&amp;mobile=2">
    <div class="threadlist_tit"><em>Fixture $tid</em></div>
  </a>
  <div class="threadlist_foot"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">Forum</a></div>
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
