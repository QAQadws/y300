import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

const _topics = UserThreadDirectoryQuery(userId: '101');
const _replies = UserThreadDirectoryQuery(
  userId: '101',
  type: UserThreadDirectoryType.replies,
);
const _context = 'home.php?mod=space&uid=101&do=thread&view=me';

// Sanitized structures from the custom and stock touch space_thread templates.
String _document({
  String uid = '101',
  String? script,
  bool replies = false,
  String rows = '',
  String pager = '',
  String? tabs,
}) =>
    '''
<!doctype html><html><head><meta charset="utf-8"><script>
${script ?? "var STYLEID = '19', discuz_uid = '$uid';"}
</script></head><body>
<div class="header"><h2>${replies ? '\u6211\u7684\u56de\u590d' : '\u6211\u7684\u4e3b\u9898'}</h2></div>
${tabs ?? '<div class="dhnv"><a class="${replies ? '' : 'mon'}" href="$_context">Topics</a><a class="${replies ? 'mon' : ''}" href="$_context&type=reply">Replies</a></div>'}
${rows.isEmpty ? '' : '<div class="threadlist"><ul>$rows</ul></div>'}
$pager</body></html>
''';

const _topicRow = '''
<li class="list">
  <div class="threadlist_top"><a class="mimg" href="home.php?mod=space&uid=101"><img src="/avatar.png"></a>
    <div class="muser"><h3><a href="home.php?mod=space&uid=101">Author &amp; name</a></h3><span class="mtime">2026-09-30</span></div></div>
  <a href="forum.php?mod=viewthread&tid=42&extra=page%3D1"><div class="threadlist_tit"><span class="micon">Poll</span><span class="micon top">Pinned</span><em>Title &amp; punctuation</em></div></a>
  <div class="none threadlist_imgs"><ul><li><img src="data/attachment/forum/cover.png"></li><li><img src="https://cdn.example.test/second.jpg"></li></ul></div>
  <div class="threadlist_mes">A <b>plain</b> excerpt</div>
  <div class="threadlist_foot"><ul><li class="mr"><a href="forum.php?mod=forumdisplay&fid=7">#Stories</a></li><li><i class="dm-eye-fill"></i>123</li><li><i class="dm-chat-s-fill"></i>0</li></ul></div>
</li>
''';

String _replyRow({
  String tid = '42',
  List<String> pids = const ['500', '501'],
}) =>
    '''
<li class="list"><a class="mt10" href="forum.php?mod=redirect&goto=findpost&ptid=$tid&pid="><div class="threadlist_tit"><span class="micon">Locked</span><em>Reply topic</em></div></a>
${pids.map((pid) => '<a href="forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid"><div class="quote"><blockquote>${pid == '500' ? '0' : 'A <b>reply</b> preview'}</blockquote></div></a>').join()}
</li>
''';

String _pager({bool replies = false, int page = 1, bool next = true}) =>
    '''
<div class="pg">${page > 1 ? '<span class="pgb"><a href="$_context${replies ? '&type=reply' : ''}&order=dateline&page=${page - 1}">Previous</a></span>' : ''}
${next ? '<a class="nxt" href="$_context${replies ? '&type=reply' : ''}&order=dateline&page=${page + 1}">Next</a>' : ''}</div>
''';

void main() {
  Future<
    DataReadResult<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
  >
  load(
    String source, {
    UserThreadDirectoryQuery query = _topics,
    Uri? responseUri,
    int status = 200,
    ForumRequestCancellation? cancellation,
    void Function()? beforeResponse,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      ForumClientAdapterFactory(
        config: blogConfig,
        network: _Network(
          source,
          responseUri: responseUri,
          status: status,
          beforeResponse: beforeResponse,
        ),
      ).createUserThreadDirectory().load(
        query,
        cancellation: cancellation,
        cachePolicy: cachePolicy,
      );

  test('parses topic metadata without badges or nested list rows', () async {
    final network = _Network(_document(rows: _topicRow, pager: _pager()));
    final client = YamiboForumClientBuilder(
      config: blogConfig,
      network: network,
    ).buildStandardClient();
    final result = await client.loadUserThreads(_topics);
    expect(client.userThreadDirectory, isNotNull);
    expect(result.failureOrNull, isNull);
    final item = result.dataOrNull!.items.single;
    expect(item.threadId, '42');
    expect(item.title, 'Title & punctuation');
    expect(item.badges.map((badge) => badge.kind), [
      ForumThreadBadgeKind.poll,
      ForumThreadBadgeKind.sticky,
    ]);
    expect(item.badges.map((badge) => badge.sourceLabel), ['Poll', 'Pinned']);
    expect(
      (result
              as DataReadSuccess<
                UserThreadDirectoryData,
                UserThreadDirectoryReadCapabilities
              >)
          .capabilities
          .supports(UserThreadDirectoryCapability.badges),
      isTrue,
    );
    expect(item.authorName, 'Author & name');
    expect(item.authorUserId, '101');
    expect(item.avatarUrl, 'https://example.test/avatar.png');
    expect(item.publishedAtText, '2026-09-30');
    expect(item.excerpt, 'A plain excerpt');
    expect(item.forumId, '7');
    expect(item.forumName, 'Stories');
    expect(item.views, 123);
    expect(item.replies, 0);
    expect(item.images, [
      'https://example.test/data/attachment/forum/cover.png',
      'https://cdn.example.test/second.jpg',
    ]);
    expect(item.replyPreviews, isEmpty);
    expect(result.dataOrNull!.pagination.hasNext, isTrue);
    expect(result.dataOrNull!.pagination.totalPages, isNull);
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
      containsPair('type', 'thread'),
    );
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('mobile', '2'),
    );
  });

  test('retains every reply pid despite an empty title-link pid', () async {
    final result = await load(
      _document(replies: true, rows: _replyRow(), pager: _pager(replies: true)),
      query: _replies,
    );
    expect(result.failureOrNull, isNull);
    final item = result.dataOrNull!.items.single;
    expect(item.authorName, isNull);
    expect(item.badges.single.kind, ForumThreadBadgeKind.closed);
    expect(item.badges.single.sourceLabel, 'Locked');
    expect(item.replyPreviews.map((p) => p.postId), ['500', '501']);
    expect(item.replyPreviews.map((p) => p.excerpt), ['0', 'A reply preview']);
    expect(
      item.replyPreviews.last.uri.queryParameters,
      containsPair('pid', '501'),
    );
    expect(
      item.replyPreviews.last.uri.queryParameters,
      containsPair('goto', 'findpost'),
    );
    expect(result.dataOrNull!.pagination.hasNext, isTrue);
  });

  test(
    'simple pager proves both directions without a total or current node',
    () async {
      final result = await load(
        _document(
          replies: true,
          rows: _replyRow(),
          pager: _pager(replies: true, page: 2),
        ),
        query: const UserThreadDirectoryQuery(
          userId: '101',
          type: UserThreadDirectoryType.replies,
          page: 2,
        ),
      );
      expect(result.failureOrNull, isNull);
      final pagination = result.dataOrNull!.pagination;
      expect(pagination.currentPage, 2);
      expect(pagination.hasPrevious, isTrue);
      expect(pagination.hasNext, isTrue);
      expect(pagination.totalPages, isNull);
    },
  );

  for (final replies in [false, true]) {
    test(
      'valid empty directory can retain a next page: replies=$replies',
      () async {
        final query = replies ? _replies : _topics;
        final result = await load(
          _document(
            replies: replies,
            pager: _pager(replies: replies),
          ),
          query: query,
        );
        expect(result.failureOrNull, isNull);
        expect(result.dataOrNull!.items, isEmpty);
        expect(result.dataOrNull!.pagination.hasNext, isTrue);
      },
    );
    test(
      'stock header identifies an empty terminal page: replies=$replies',
      () async {
        final result = await load(
          _document(replies: replies, tabs: ''),
          query: replies ? _replies : _topics,
        );
        expect(result.failureOrNull, isNull);
        expect(result.dataOrNull!.items, isEmpty);
        expect(result.dataOrNull!.pagination.hasNext, isFalse);
      },
    );
  }

  for (final (label, source, query) in <(String, String, UserThreadDirectoryQuery)>[
    ('wrong account', _document(uid: '202'), _topics),
    ('missing identity', _document(script: ''), _topics),
    (
      'body identity',
      _document(script: '', rows: '<script>var discuz_uid = "101";</script>'),
      _topics,
    ),
    (
      'conflicting identity',
      _document(script: "var discuz_uid='101'; discuz_uid='202';"),
      _topics,
    ),
    ('wrong directory type', _document(replies: true), _topics),
    (
      'wrong tab uid',
      _document().replaceFirst('uid=101&do=thread', 'uid=202&do=thread'),
      _topics,
    ),
    ('wrong tab view', _document().replaceFirst('view=me', 'view=we'), _topics),
    ('missing tab view', _document().replaceFirst('&view=me', ''), _topics),
    (
      'wrong pager uid',
      _document(pager: _pager().replaceFirst('uid=101', 'uid=202')),
      _topics,
    ),
    ('wrong pager type', _document(replies: true, pager: _pager()), _replies),
    (
      'wrong pager order',
      _document(pager: _pager().replaceFirst('order=dateline', 'order=hot')),
      _topics,
    ),
    (
      'skipped next page',
      _document(pager: _pager().replaceFirst('page=2', 'page=3')),
      _topics,
    ),
    (
      'reply quote mismatched tid',
      _document(
        replies: true,
        rows: _replyRow().replaceFirst('ptid=42&pid=500', 'ptid=43&pid=500'),
      ),
      _replies,
    ),
    (
      'reply quote missing pid',
      _document(replies: true, rows: _replyRow().replaceFirst('&pid=500', '')),
      _replies,
    ),
    (
      'foreign topic',
      _document(
        rows: _topicRow.replaceFirst(
          'forum.php?mod=viewthread',
          'https://evil.test/forum.php?mod=viewthread',
        ),
      ),
      _topics,
    ),
    (
      'ambiguous identity parameter',
      _document().replaceFirst(
        'uid=101&do=thread',
        'uid=101&uid=202&do=thread',
      ),
      _topics,
    ),
    (
      'unrelated document',
      '<html><head><script>var discuz_uid="101";</script></head><body>Generic page</body></html>',
      _topics,
    ),
  ]) {
    test('fails closed for $label', () async {
      final result = await load(source, query: query);
      expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      expect(result.dataOrNull, isNull);
    });
  }

  for (final (label, uri) in [
    (
      'different uid',
      'https://example.test/$_context&page=1&mobile=2'.replaceFirst(
        'uid=101',
        'uid=202',
      ),
    ),
    ('different page', 'https://example.test/$_context&page=2&mobile=2'),
    (
      'different type',
      'https://example.test/$_context&type=reply&page=1&mobile=2',
    ),
    ('different host', 'https://other.test/$_context&page=1&mobile=2'),
  ]) {
    test('rejects redirected response $label', () async {
      expect(
        (await load(
          _document(),
          responseUri: Uri.parse(uri),
        )).failureOrNull?.kind,
        DataReadFailureKind.parse,
      );
    });
  }

  test('classifies login form and anonymous viewer as unauthorized', () async {
    for (final source in [
      '<form id="loginform"></form>',
      _document(uid: '0'),
    ]) {
      expect(
        (await load(source)).failureOrNull?.kind,
        DataReadFailureKind.unauthorized,
      );
    }
    expect(
      (await load(
        _document(),
        responseUri: Uri.parse(
          'https://example.test/member.php?mod=logging&action=login',
        ),
      )).failureOrNull?.kind,
      DataReadFailureKind.unauthorized,
    );
  });

  test(
    'server notices stay structured failures and never empty successes',
    () async {
      for (final source in [
        '<div class="jump_c"><p>Server message</p></div>',
        '<div id="messagetext"><p>Server message</p></div>',
        '<div id="ct"><div class="nfl"><div class="f_c"><table><tr><td class="avt"></td></tr></table></div></div><a href="home.php?do=friend">Friend</a></div>',
      ]) {
        final result = await load(source);
        expect(result.failureOrNull?.kind, DataReadFailureKind.business);
        expect(
          result.failureOrNull?.diagnosticMessage,
          isNot(contains('Server message')),
        );
      }
    },
  );

  test('cancellation avoids requests and rejects late responses', () async {
    final cancellation = ForumRequestCancellation()..cancel();
    final network = _Network(_document());
    final repository = ForumClientAdapterFactory(
      config: blogConfig,
      network: network,
    ).createUserThreadDirectory();
    expect(
      (await repository.load(
        _topics,
        cancellation: cancellation,
      )).failureOrNull?.kind,
      DataReadFailureKind.cancelled,
    );
    expect(network.requests, isEmpty);
    final late = ForumRequestCancellation();
    expect(
      (await load(
        _document(),
        cancellation: late,
        beforeResponse: late.cancel,
      )).failureOrNull?.kind,
      DataReadFailureKind.cancelled,
    );
  });

  test('all cache policies use account-verified network reads', () async {
    final network = _Network(_document());
    final repository = ForumClientAdapterFactory(
      config: blogConfig,
      network: network,
    ).createUserThreadDirectory();
    for (final policy in CacheLoadPolicy.values) {
      expect(
        (await repository.load(_topics, cachePolicy: policy)).isSuccess,
        isTrue,
      );
    }
    expect(network.requests, hasLength(CacheLoadPolicy.values.length));
  });

  test('invalid account and page do not send a request', () async {
    final network = _Network(_document());
    final repository = ForumClientAdapterFactory(
      config: blogConfig,
      network: network,
    ).createUserThreadDirectory();
    for (final query in [
      const UserThreadDirectoryQuery(userId: '0'),
      const UserThreadDirectoryQuery(userId: '101', page: 0),
    ]) {
      expect(
        (await repository.load(query)).failureOrNull?.kind,
        DataReadFailureKind.business,
      );
    }
    expect(network.requests, isEmpty);
  });
}

final class _Network implements ForumClientNetwork {
  _Network(
    this.source, {
    this.responseUri,
    this.status = 200,
    this.beforeResponse,
  });
  final String source;
  final Uri? responseUri;
  final int status;
  final void Function()? beforeResponse;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    beforeResponse?.call();
    return ForumTransportSuccess(
      ForumResponse(
        uri: responseUri ?? request.uri,
        statusCode: status,
        headers: const {},
        body: source,
      ),
    );
  }
}
