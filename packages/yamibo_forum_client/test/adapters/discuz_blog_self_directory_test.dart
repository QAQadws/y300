import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

const _selfQuery = UserBlogDirectoryQuery.self(ownerUserId: '101');
const _selfHref = 'home.php?mod=space&do=blog&view=me&mobile=2';
const _headerIdentity = "var STYLEID = '19', discuz_uid = '101';";

// Sanitized structure from a real, empty touch/home/space_blog_list response.
const _emptySelfBody =
    '''
<header><h2>日志</h2>
  <a href="home.php?mod=spacecp&ac=blog&mobile=2">发表日志</a>
</header>
<div class="dhnv">
  <a href="home.php?mod=space&do=blog&view=we&mobile=2" class="flex">好友的日志</a>
  <a href="$_selfHref" class="flex mon">我的日志</a>
  <a href="home.php?mod=space&do=blog&view=all&mobile=2" class="flex">随便看看</a>
</div>
<div class="threadlist_box cl">
  <div class="threadlist cl">
    <div class="threadlist_box mt10 cl"><h4>还没有相关的日志</h4></div>
  </div>
</div>
<footer><a href="home.php?mod=space&uid=101&do=profile&mycenter=1">我的</a></footer>
''';

String _document({String script = _headerIdentity, String? body}) =>
    '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Fixture author's blog</title>
<script type="text/javascript">$script</script>
</head><body id="home" class="pg_space">${body ?? _emptySelfBody}</body></html>
''';

String _ownFeed({String? personalCategory, int page = 1, int pages = 1}) =>
    blogFeed(
      view: 'me',
      owner: '101',
      personalCategory: personalCategory,
      page: page,
      pages: pages,
    ).replaceFirst(
      RegExp(r'<div class="dhnv"><a class="mon" href="[^"]+">'),
      '<div class="dhnv"><a class="mon" href="$_selfHref">',
    );

void main() {
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(String source, {UserBlogDirectoryQuery query = _selfQuery}) =>
      ForumClientAdapterFactory(
        config: blogConfig,
        network: BlogFixtureNetwork(source),
      ).createUserBlogDirectory().load(query);

  test('real empty own directory is a successful terminal page', () async {
    final network = BlogFixtureNetwork(_document());
    final result = await ForumClientAdapterFactory(
      config: blogConfig,
      network: network,
    ).createUserBlogDirectory().load(_selfQuery);

    expect(result.failureOrNull, isNull);
    final data = result.dataOrNull!;
    expect(data.scope, UserBlogFeedScope.self);
    expect(data.items, isEmpty);
    expect(data.categories, isEmpty);
    expect(data.pagination.currentPage, 1);
    expect(data.pagination.hasNext, isFalse);
    expect(data.pagination.hasPrevious, isFalse);
    expect(network.requests, hasLength(1));
    expect(network.requests.single.method, ForumRequestMethod.get);
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('uid', '101'),
    );
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('view', 'me'),
    );
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('mobile', '2'),
    );
  });

  test('own directory with entries verifies owner from header', () async {
    final result = await load(_document(body: _ownFeed()));
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.items.single.ownerUserId, '101');
    expect(result.dataOrNull!.items.single.blogId, '11');
    expect(result.dataOrNull!.items.single.title, 'Title & punctuation');
  });

  test('own category and pager retain their explicit owner', () async {
    final result = await load(
      _document(body: _ownFeed(personalCategory: '7', page: 2, pages: 3)),
      query: const UserBlogDirectoryQuery.self(
        ownerUserId: '101',
        personalCategoryId: '7',
        page: 2,
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.categories.single.id, '7');
    expect(result.dataOrNull!.pagination.currentPage, 2);
    expect(result.dataOrNull!.pagination.hasPrevious, isTrue);
    expect(result.dataOrNull!.pagination.hasNext, isTrue);
  });

  test('explicit other owner is independent of the logged-in actor', () async {
    final result = await load(
      _document(
        script: "var STYLEID = '19', discuz_uid = '202';",
        body: blogFeed(view: 'me', owner: '101'),
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.items.single.ownerUserId, '101');
  });

  for (final script in [
    'var discuz_uid = "101";',
    "var STYLEID = '19',\n discuz_uid = '101';",
    "var discuz_uid = '101';</script><script>var discuz_uid = '101';",
  ]) {
    test('accepts an unambiguous header declaration: $script', () async {
      final result = await load(_document(script: script));
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items, isEmpty);
    });
  }

  for (final (description, script, body) in <(String, String, String?)>[
    ('missing header identity', '', null),
    ('empty header identity', "var discuz_uid = '';", null),
    ('invalid header identity', "var discuz_uid = 'user';", null),
    (
      'anonymous header identity',
      "var STYLEID = '19', discuz_uid = '0';",
      null,
    ),
    (
      'different header identity',
      "var STYLEID = '19', discuz_uid = '202';",
      null,
    ),
    (
      'conflicting header identities',
      "var STYLEID = '19', discuz_uid = '101'; discuz_uid = '202';",
      null,
    ),
    (
      'conflicting anonymous identity',
      "var STYLEID = '19', discuz_uid = '101'; discuz_uid = '0';",
      null,
    ),
    (
      'body script identity',
      '',
      '<script>$_headerIdentity</script>$_emptySelfBody',
    ),
    ('author links without header identity', '', _ownFeed()),
    (
      'explicit empty uid',
      _headerIdentity,
      _emptySelfBody.replaceFirst('$_selfHref"', '$_selfHref&uid="'),
    ),
    (
      'explicit mismatched uid',
      _headerIdentity,
      _emptySelfBody.replaceFirst('$_selfHref"', '$_selfHref&uid=202"'),
    ),
  ]) {
    test('rejects $description instead of trusting the request', () async {
      final result = await load(_document(script: script, body: body));
      expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
      expect(result.dataOrNull, isNull);
    });
  }

  test('a matching header does not relax the requested scope', () async {
    final result = await load(
      _document(),
      query: const UserBlogDirectoryQuery.friends(),
    );
    expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
  });

  for (final ownerSuffix in ['', '&uid=202']) {
    test('header fallback does not authorize pager $ownerSuffix', () async {
      final body = _ownFeed(
        pages: 2,
      ).replaceFirst('&uid=101&page=2', '$ownerSuffix&page=2');
      final result = await load(_document(body: body));
      expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
    });

    test('header fallback does not expose category $ownerSuffix', () async {
      final body =
          '''$_emptySelfBody
<div id="dhnavs_li"><a href="$_selfHref$ownerSuffix&classid=7">Private category</a></div>
''';
      final result = await load(_document(body: body));
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.categories, isEmpty);
    });
  }

  test(
    'login response remains unauthorized instead of becoming empty',
    () async {
      final result = await load(
        _document(body: '<form id="loginform"></form>$_emptySelfBody'),
      );
      expect(result.failureOrNull!.kind, DataReadFailureKind.unauthorized);
      expect(result.failureOrNull!.code, 'user_blog_login_required');
      expect(result.dataOrNull, isNull);
    },
  );
}
