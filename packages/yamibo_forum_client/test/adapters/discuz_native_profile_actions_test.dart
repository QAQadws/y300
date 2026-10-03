import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  test(
    'current touch template destinations work without mobile parameter',
    () async {
      final result = await _load(
        _source(
          viewer: '4242',
          links: '''
      <a href="home.php?mod=space&amp;uid=4242&amp;do=thread&amp;view=me">Topics</a>
      <a href="home.php?mod=space&amp;uid=4242&amp;do=blog&amp;view=me">Blogs</a>
      <a href="home.php?mod=space&amp;uid=4242&amp;do=favorite&amp;view=me&amp;type=thread">Favorites</a>
      <a href="home.php?mod=space&amp;do=pm">Messages</a>
      <a href="home.php?mod=space&amp;do=friend">Friends</a>
    ''',
          self: true,
        ),
        self: true,
      );
      final data = result.dataOrNull!;
      expect(data.actions, [
        ForumUserProfileActionKind.creditHistory,
        ForumUserProfileActionKind.threads,
        ForumUserProfileActionKind.blogs,
        ForumUserProfileActionKind.forumFavorites,
        ForumUserProfileActionKind.messages,
        ForumUserProfileActionKind.friends,
        ForumUserProfileActionKind.settings,
      ]);
      expect(data.actionLinks.map((item) => item.kind), data.actions);
      expect(
        data.actionLinks.every((item) => item.uri.host == 'example.test'),
        isTrue,
      );
      expect(data.groupName, 'Registered');
      expect(data.customTitle, 'Reader');
      expect(data.details.map((item) => item.section), [
        ForumUserProfileDetailSection.account,
        ForumUserProfileDetailSection.account,
        ForumUserProfileDetailSection.personal,
        ForumUserProfileDetailSection.activity,
      ]);
    },
  );

  test(
    'public profile exposes source topics blogs PM and friend request',
    () async {
      final result = await _load(_source(viewer: '7654', links: _publicLinks));
      final data = result.dataOrNull!;
      expect(data.actions, [
        ForumUserProfileActionKind.threads,
        ForumUserProfileActionKind.blogs,
        ForumUserProfileActionKind.sendMessage,
        ForumUserProfileActionKind.addFriend,
      ]);
      expect(data.viewerUserId, '7654');
      expect(data.isOnline, isTrue);
      expect(
        data.actionLinks.last.uri.queryParameters['handlekey'],
        'addfriendhk_4242',
      );
    },
  );

  test('guests never receive authenticated profile actions', () async {
    final result = await _load(_source(viewer: '0', links: _publicLinks));
    expect(result.dataOrNull!.actions, [
      ForumUserProfileActionKind.threads,
      ForumUserProfileActionKind.blogs,
    ]);
    expect(result.dataOrNull!.viewerUserId, isNull);
  });

  test('only an exact advertised friend destination grants a friend action', () async {
    for (final raw in [
      'https://other.test/home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=9999',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242&amp;uid=4242',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242&amp;addsubmit=1',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242&amp;mobile=1',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242&amp;handlekey=wrong',
      'home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242#fragment',
    ]) {
      final result = await _load(
        _source(viewer: '7654', links: '<a href="$raw">Friend</a>'),
      );
      expect(result.dataOrNull!.actions, isEmpty, reason: raw);
    }
  });

  test('viewer mismatch discards all profile content', () async {
    final result = await _load(
      _source(viewer: '9999', links: _publicLinks),
      viewer: '7654',
    );
    expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
    expect(result.dataOrNull, isNull);
  });

  test('cancelled profile read returns no parsed account content', () async {
    final cancellation = ForumRequestCancellation()..cancel();
    final result = await _load(
      _source(viewer: '4242', links: ''),
      cancellation: cancellation,
    );
    expect(result.failureOrNull?.kind, DataReadFailureKind.cancelled);
    expect(result.dataOrNull, isNull);
  });
}

const _publicLinks = '''
<a href="home.php?mod=space&amp;uid=4242&amp;do=thread">Topics</a>
<a href="home.php?mod=space&amp;uid=4242&amp;do=blog">Blogs</a>
<a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=4242">PM</a>
<a href="home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=4242&amp;handlekey=addfriendhk_4242">Friend</a>
''';

String _source({
  required String viewer,
  required String links,
  bool self = false,
}) =>
    '''
<html><head><script>var discuz_uid = '$viewer';</script></head><body>
<div class="userinfo"><h2 class="name">Fixture</h2></div>
<div class="user_box" onclick="window.location.href='home.php?mod=spacecp&amp;ac=credit&amp;op=log'"><li><span>42</span>Credits</li></div>
<div class="myinfo_list_ico">$links</div>
<div class="myinfo_list"><ul><li><b>Profile</b><span class="mtxt">${self ? '<a href="home.php?mod=spacecp">Edit</a>' : 'Online'}</span></li>
<li>UID<span>4242</span></li><li>User group<em>Expires soon</em><span>Registered</span></li>
<li>Custom title<span>Reader</span></li><li>Registration date<span>2006-01-01</span></li></ul></div>
</body></html>''';

Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
_load(
  String source, {
  bool self = false,
  String? viewer,
  ForumRequestCancellation? cancellation,
}) =>
    ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://example.test'),
        apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
        userAgent: 'test',
        desktopUserAgent: 'test',
      ),
      network: _Network(source),
    ).createForumUserProfile().load(
      ForumUserProfileQuery(
        userId: '4242',
        view: self ? ForumUserProfileView.self : ForumUserProfileView.public,
        viewerUserId: viewer,
      ),
      cancellation: cancellation,
    );

final class _Network implements ForumClientNetwork {
  _Network(this.source);
  final String source;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async => ForumTransportSuccess(
    ForumResponse(
      uri: request.uri,
      statusCode: 200,
      headers: const {},
      body: source,
    ),
  );
}
