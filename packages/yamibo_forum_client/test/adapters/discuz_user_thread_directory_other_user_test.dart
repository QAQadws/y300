import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

const _target = '260328';
const _viewer = '101';
const _topics = UserThreadDirectoryQuery(
  userId: _target,
  viewerUserId: _viewer,
);
const _replies = UserThreadDirectoryQuery(
  userId: _target,
  viewerUserId: _viewer,
  type: UserThreadDirectoryType.replies,
);

// Sanitized custom/stock touch space_thread structures. Viewer identity comes
// from common/header; space_thread links identify the target space separately.
String _pageLink({
  String owner = _target,
  UserThreadDirectoryType type = UserThreadDirectoryType.threads,
  String? view = 'me',
  int? page,
}) =>
    'home.php?mod=space&uid=$owner&do=thread'
    '${type == UserThreadDirectoryType.replies ? '&type=reply' : ''}'
    '${view == null ? '' : '&view=$view'}'
    '${page == null ? '' : '&order=dateline&page=$page'}';

String _document({
  String viewer = _viewer,
  String owner = _target,
  UserThreadDirectoryType type = UserThreadDirectoryType.threads,
  String rows = '',
  int page = 1,
  bool hasNext = false,
  bool stock = false,
  String? heading,
}) {
  final personal = viewer == owner;
  final title =
      heading ??
      (personal
          ? type == UserThreadDirectoryType.replies
                ? '我的回复'
                : '我的主题'
          : 'Other author - Ta的${type == UserThreadDirectoryType.replies ? '回复' : '主题'}');
  final topics = _pageLink(owner: owner, view: personal ? 'me' : null);
  final replies = _pageLink(
    owner: owner,
    type: UserThreadDirectoryType.replies,
    view: personal ? 'me' : null,
  );
  return '''
<!doctype html><html><head><meta charset="utf-8"><script>
var STYLEID = '19', discuz_uid = '$viewer';
</script></head><body><div class="header"><h2>$title</h2></div>
${stock ? '' : '<div class="dhnv"><a class="${type == UserThreadDirectoryType.threads ? 'mon' : ''}" href="$topics">Topics</a><a class="${type == UserThreadDirectoryType.replies ? 'mon' : ''}" href="$replies">Replies</a></div>'}
${rows.isEmpty ? '' : '<div class="threadlist"><ul>$rows</ul></div>'}
${page > 1 || hasNext ? '<div class="pg">${page > 1 ? '<span class="pgb"><a href="${_pageLink(owner: owner, type: type, page: page - 1)}">Previous</a></span>' : ''}${hasNext ? '<a class="nxt" href="${_pageLink(owner: owner, type: type, page: page + 1)}">Next</a>' : ''}</div>' : ''}
</body></html>
''';
}

String _topicRow({String author = _target}) =>
    '''
<li class="list">
<div class="threadlist_top"><a class="mimg" href="home.php?mod=space&uid=$author"><img src="/avatar.png"></a><div class="muser"><h3><a href="home.php?mod=space&uid=$author">Other &amp; author</a></h3><span class="mtime">2026-10-02</span></div></div>
<a href="forum.php?mod=viewthread&tid=42"><div class="threadlist_tit"><span class="micon">Locked</span><em>Public &amp; topic</em></div></a>
<div class="none threadlist_imgs"><ul><li><img src="/one.jpg"></li><li><img src="/two.jpg"></li><li><img src="/three.jpg"></li></ul></div>
<div class="threadlist_mes">A <b>topic</b> preview</div>
<div class="threadlist_foot"><ul><li class="mr"><a href="forum.php?mod=forumdisplay&fid=7">#Stories</a></li><li><i class="dm-eye-fill"></i>0</li><li><i class="dm-chat-s-fill"></i>12</li></ul></div>
</li>
''';

String _replyRow({List<String> pids = const ['500', '501']}) =>
    '''
<li class="list"><a href="forum.php?mod=redirect&goto=findpost&ptid=42&pid="><div class="threadlist_tit"><em>Reply topic</em></div></a>
${pids.map((pid) => '<a href="forum.php?mod=redirect&goto=findpost&ptid=42&pid=$pid"><div class="quote"><blockquote>${pid == '500' ? '0' : 'A <b>reply</b> preview'}</blockquote></div></a>').join()}
</li>
''';

Future<
  DataReadResult<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
>
_load(
  String source, {
  UserThreadDirectoryQuery query = _topics,
  Uri? responseUri,
  ForumRequestCancellation? cancellation,
}) => ForumClientAdapterFactory(
  config: blogConfig,
  network: _Network(source, responseUri: responseUri),
).createUserThreadDirectory().load(query, cancellation: cancellation);

void main() {
  test(
    'shared facade requests target with canonical mobile me context',
    () async {
      final network = _Network(_document(rows: _topicRow(), hasNext: true));
      final client = YamiboForumClientBuilder(
        config: blogConfig,
        network: network,
      ).buildStandardClient();
      final result = await client.loadUserThreads(_topics);
      expect(result.failureOrNull, isNull);
      expect(network.requests, hasLength(1));
      expect(network.requests.single.uri.queryParameters, {
        'mod': 'space',
        'uid': _target,
        'do': 'thread',
        'view': 'me',
        'type': 'thread',
        'page': '1',
        'mobile': '2',
      });
      final item = result.dataOrNull!.items.single;
      expect(item.threadId, '42');
      expect(item.title, 'Public & topic');
      expect(item.authorUserId, _target);
      expect(item.authorName, 'Other & author');
      expect(item.publishedAtText, '2026-10-02');
      expect(item.excerpt, 'A topic preview');
      expect(item.views, 0);
      expect(item.replies, 12);
      expect(item.forumId, '7');
      expect(item.images, [
        'https://example.test/one.jpg',
        'https://example.test/two.jpg',
        'https://example.test/three.jpg',
      ]);
      expect(result.dataOrNull!.pagination.hasNext, isTrue);
    },
  );

  test(
    'source-forced other-user me response accepts the supplied URL shape',
    () async {
      final result = await _load(
        _document(rows: _topicRow()),
        responseUri: Uri.parse(
          'https://example.test/home.php?mod=space&uid=260328&do=thread&mobile=2',
        ),
      );
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items.single.authorUserId, _target);
    },
  );

  test(
    'other replies retain distinct PIDs and never require topic author owner',
    () async {
      // Real reply views omit topic-author metadata; tolerate it when advertised
      // without assigning the original topic author to the reply owner.
      final row = _replyRow().replaceFirst(
        '<li class="list">',
        '<li class="list"><div class="threadlist_top"><div class="muser"><h3><a href="home.php?mod=space&uid=303">Original author</a></h3></div></div>',
      );
      final result = await _load(
        _document(
          type: UserThreadDirectoryType.replies,
          rows: row,
          hasNext: true,
        ),
        query: _replies,
        responseUri: Uri.parse(
          'https://example.test/${_pageLink(type: UserThreadDirectoryType.replies, view: null)}&mobile=2',
        ),
      );
      expect(result.failureOrNull, isNull);
      final item = result.dataOrNull!.items.single;
      expect(item.authorUserId, '303');
      expect(item.replyPreviews.map((p) => p.postId), ['500', '501']);
      expect(item.replyPreviews.map((p) => p.excerpt), [
        '0',
        'A reply preview',
      ]);
      expect(item.replyPreviews.last.uri.queryParameters['pid'], '501');
      expect(item.replyPreviews.last.uri.queryParameters['goto'], 'findpost');
      expect(result.dataOrNull!.pagination.hasNext, isTrue);
    },
  );

  for (final type in UserThreadDirectoryType.values) {
    test(
      'custom and stock empty other pages are valid: ${type.name}',
      () async {
        for (final stock in [false, true]) {
          final result = await _load(
            _document(type: type, stock: stock),
            query: UserThreadDirectoryQuery(
              userId: _target,
              viewerUserId: _viewer,
              type: type,
            ),
          );
          expect(result.failureOrNull, isNull);
          expect(result.dataOrNull!.items, isEmpty);
          expect(result.dataOrNull!.pagination.hasNext, isFalse);
        }
      },
    );
  }

  test(
    'filtered empty reply batch follows pager instead of visible count',
    () async {
      final result = await _load(
        _document(
          type: UserThreadDirectoryType.replies,
          page: 2,
          hasNext: true,
        ),
        query: const UserThreadDirectoryQuery(
          userId: _target,
          viewerUserId: _viewer,
          type: UserThreadDirectoryType.replies,
          page: 2,
        ),
      );
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items, isEmpty);
      expect(result.dataOrNull!.pagination.currentPage, 2);
      expect(result.dataOrNull!.pagination.hasPrevious, isTrue);
      expect(result.dataOrNull!.pagination.hasNext, isTrue);
      expect(result.dataOrNull!.pagination.totalPages, isNull);
    },
  );

  for (final (label, source) in [
    ('viewer is owner', _document(viewer: _target)),
    ('different viewer', _document(viewer: '303')),
    ('wrong tab owner', _document(owner: '303')),
    (
      'explicit tab view we',
      _document().replaceFirst('do=thread', 'do=thread&view=we'),
    ),
    ('wrong topic author', _document(rows: _topicRow(author: '303'))),
    ('stock self heading', _document(stock: true, heading: '我的主题')),
    (
      'stock wrong type',
      _document(stock: true, heading: 'Other author - Ta的回复'),
    ),
    (
      'wrong pager owner',
      _document(hasNext: true).replaceFirst(
        'uid=$_target&do=thread&view=me',
        'uid=$_viewer&do=thread&view=me',
      ),
    ),
    (
      'pager omitted view',
      _document(hasNext: true).replaceFirst('&view=me', ''),
    ),
  ]) {
    test('other-user data rejects $label', () async {
      final result = await _load(source);
      expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      expect(result.dataOrNull, isNull);
    });
  }

  for (final (label, uri) in [
    (
      'viewer target',
      'https://example.test/${_pageLink(owner: _viewer)}&mobile=2',
    ),
    ('wrong page', 'https://example.test/${_pageLink(page: 2)}&mobile=2'),
    (
      'wrong type',
      'https://example.test/${_pageLink(type: UserThreadDirectoryType.replies)}&mobile=2',
    ),
    ('wrong origin', 'https://other.test/${_pageLink()}&mobile=2'),
    (
      'explicit view we',
      'https://example.test/${_pageLink(view: 'we')}&mobile=2',
    ),
    ('desktop mode', 'https://example.test/${_pageLink()}&mobile=1'),
  ]) {
    test('other-user response rejects $label', () async {
      expect(
        (await _load(
          _document(),
          responseUri: Uri.parse(uri),
        )).failureOrNull?.kind,
        DataReadFailureKind.parse,
      );
    });
  }

  test(
    'omitted viewer keeps strict self validation and explicit self works',
    () async {
      expect(
        (await _load(
          _document(),
          query: const UserThreadDirectoryQuery(userId: _target),
        )).failureOrNull?.kind,
        DataReadFailureKind.parse,
      );
      const explicitSelf = UserThreadDirectoryQuery(
        userId: _viewer,
        viewerUserId: _viewer,
      );
      expect(
        (await _load(_document(owner: _viewer), query: explicitSelf)).isSuccess,
        isTrue,
      );
      for (final explicit in [false, true]) {
        final query = explicit
            ? explicitSelf
            : const UserThreadDirectoryQuery(userId: _viewer);
        expect(
          (await _load(
            _document(owner: _viewer).replaceAll('&view=me', ''),
            query: query,
          )).failureOrNull?.kind,
          DataReadFailureKind.parse,
        );
        expect(
          (await _load(
            _document(owner: _viewer),
            query: query,
            responseUri: Uri.parse(
              'https://example.test/${_pageLink(owner: _viewer, view: null)}&mobile=2',
            ),
          )).failureOrNull?.kind,
          DataReadFailureKind.parse,
        );
      }
    },
  );

  test(
    'other directories still require authentication and preserve privacy failure',
    () async {
      for (final source in [
        '<form id="loginform"></form>',
        _document(viewer: '0'),
      ]) {
        expect(
          (await _load(source)).failureOrNull?.kind,
          DataReadFailureKind.unauthorized,
        );
      }
      for (final source in [
        '<div class="jump_c"><p>Permission denied</p></div>',
        '<div id="messagetext"><p>Permission denied</p></div>',
        '<div id="ct"><div class="nfl"><div class="f_c"><table><tr><td class="avt"></td></tr></table></div></div><a href="home.php?do=friend">Friend</a></div>',
      ]) {
        final result = await _load(source);
        expect(result.failureOrNull?.kind, DataReadFailureKind.business);
        expect(result.dataOrNull, isNull);
        expect(
          result.failureOrNull?.diagnosticMessage,
          isNot(contains('Permission denied')),
        );
      }
    },
  );

  test('query identity and validation isolate viewer and target', () async {
    expect(
      _topics,
      isNot(
        const UserThreadDirectoryQuery(userId: _target, viewerUserId: '303'),
      ),
    );
    expect(
      _topics,
      isNot(
        const UserThreadDirectoryQuery(userId: '303', viewerUserId: _viewer),
      ),
    );
    final network = _Network(_document());
    final repository = ForumClientAdapterFactory(
      config: blogConfig,
      network: network,
    ).createUserThreadDirectory();
    for (final viewer in ['', '0', 'invalid']) {
      expect(
        (await repository.load(
          UserThreadDirectoryQuery(userId: _target, viewerUserId: viewer),
        )).failureOrNull?.kind,
        DataReadFailureKind.business,
      );
    }
    expect(network.requests, isEmpty);
  });

  test(
    'other-user reads stay network-only and recheck viewer on every response',
    () async {
      final network = _Network(_document());
      final repository = ForumClientAdapterFactory(
        config: blogConfig,
        network: network,
      ).createUserThreadDirectory();
      for (final policy in CacheLoadPolicy.values) {
        final result = await repository.load(_topics, cachePolicy: policy);
        expect(result.isSuccess, isTrue);
      }
      network.source = _document(viewer: '303');
      expect(
        (await repository.load(_topics)).failureOrNull?.kind,
        DataReadFailureKind.parse,
      );
      expect(network.requests, hasLength(CacheLoadPolicy.values.length + 1));
      final cancelled = ForumRequestCancellation()..cancel();
      expect(
        (await repository.load(
          _topics,
          cancellation: cancelled,
        )).failureOrNull?.kind,
        DataReadFailureKind.cancelled,
      );
      expect(network.requests, hasLength(CacheLoadPolicy.values.length + 1));
    },
  );
}

final class _Network implements ForumClientNetwork {
  _Network(this.source, {this.responseUri});
  String source;
  final Uri? responseUri;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse(
        uri: responseUri ?? request.uri,
        statusCode: 200,
        headers: const {},
        body: source,
      ),
    );
  }
}
