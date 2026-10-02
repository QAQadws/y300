import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late ForumFriendDirectoryRepository repository;
  setUp(() {
    network = _Network();
    repository = ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://forum.example.test'),
        userAgent: 'mobile-fixture',
        desktopUserAgent: 'desktop-fixture',
      ),
      network: network,
    ).createFriendDirectory();
  });

  test(
    'desktop friend source decodes numeric keys and quoted names safely',
    () async {
      final result = await repository.load(
        const ForumFriendDirectoryQuery(page: 2, username: "A'"),
      );
      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.page, 2);
      expect(page.perPage, 20);
      expect(page.count, 41);
      expect(page.hasNext, isTrue);
      expect(page.currentUserId, isNull);
      expect(page.items.single.userId, '12');
      expect(page.items.single.username, "A'友\\B");
      expect(
        page.items.single.avatarUrl,
        'https://forum.example.test/uc_server/avatar.php?uid=12&size=small',
      );
      expect(() => page.items.clear(), throwsUnsupportedError);
      final request = network.requests.single;
      expect(request.method, ForumRequestMethod.get);
      expect(request.context.operation, 'friends.read');
      expect(request.headers['User-Agent'], 'desktop-fixture');
      expect(request.uri.queryParameters, {
        'mod': 'spacecp',
        'ac': 'friend',
        'op': 'getinviteuser',
        'inajax': '1',
        'page': '2',
        'gid': '-1',
        'username': "A'",
      });
      expect(
        request.headers['Referer'],
        'https://forum.example.test/home.php?mod=spacecp&ac=pm',
      );
      expect(request.followRedirects, isFalse);
    },
  );

  test('empty directory is a successful page, not missing content', () async {
    network.body = _envelope(
      "{'userdata':{}, 'maxfriendnum':'0', 'singlenum':'0'}",
    );
    final result = await repository.load(const ForumFriendDirectoryQuery());
    expect(result.dataOrNull!.items, isEmpty);
    expect(result.dataOrNull!.hasNext, isFalse);
  });

  test('invalid avatars are omitted without inventing a URL', () async {
    network.body = _envelope(
      _literal.replaceAll(
        '/uc_server/avatar.php?uid=12&size=small',
        'javascript:alert(1)',
      ),
    );
    final result = await repository.load(const ForumFriendDirectoryQuery());
    expect(result.dataOrNull!.items.single.avatarUrl, isNull);
  });

  test(
    'expressions, duplicate keys, malformed counts and identities fail closed',
    () async {
      for (final literal in [
        'alert(1)',
        "{'userdata':(function(){return {}})(), 'maxfriendnum':'0', 'singlenum':'0'}",
        "{'userdata':{}, 'maxfriendnum':'0', 'maxfriendnum':'1', 'singlenum':'0'}",
        _literal.replaceAll("'uid':12", "'uid':13"),
        _literal.replaceAll("'singlenum':'1'", "'singlenum':'2'"),
        _literal.replaceAll("'maxfriendnum':'41'", "'maxfriendnum':'0'"),
        _literal.replaceAll("'maxfriendnum':'41'", "'maxfriendnum':'NaN'"),
        _literal.replaceAll("'uid':12", "'uid':12.5"),
        _literal.replaceAll("'uid':12", "'uid':12e1"),
        _literal.replaceAll("'uid':12", "'uid':012"),
        _literal.replaceAll("'uid':12", "'uid':'12'"),
        _literal.replaceAll("'avatar'", "'unexpected'"),
        _literal.replaceAll(r"A\'友\\B", r'A\nB'),
        '$_literal;alert(1)',
        "{'userdata':{'x':{'y':{'z':{'w':{}}}}},'maxfriendnum':'0','singlenum':'0'}",
      ]) {
        network.body = _envelope(literal);
        final result = await repository.load(const ForumFriendDirectoryQuery());
        expect(
          result.failureOrNull!.kind,
          DataReadFailureKind.parse,
          reason: literal,
        );
        expect(
          result.failureOrNull!.diagnosticMessage,
          'friend_response_unrecognized',
        );
      }
    },
  );

  test(
    'extra XML/HTML outside one literal and unbounded fields are rejected',
    () async {
      for (final body in [
        _literal,
        '${_envelope(_literal)}<script>alert(1)</script>',
        '<root><![CDATA[$_literal]]><![CDATA[{}]]></root>',
        '<html>private server response</html>',
        _envelope(_literal.replaceAll(r"A\'友\\B", 'a' * 17000)),
      ]) {
        network.body = body;
        final result = await repository.load(const ForumFriendDirectoryQuery());
        expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
        expect(
          result.failureOrNull!.diagnosticMessage,
          isNot(contains('private server response')),
        );
      }
    },
  );

  test('invalid query and early cancellation send no request', () async {
    final cancelled = ForumRequestCancellation()..cancel();
    for (final query in [
      const ForumFriendDirectoryQuery(page: 0),
      const ForumFriendDirectoryQuery(username: 'a\nb'),
      ForumFriendDirectoryQuery(cancellation: cancelled),
    ]) {
      expect((await repository.load(query)).isFailure, isTrue);
    }
    expect(network.requests, isEmpty);
  });

  test('late cancelled page never becomes a successful owner read', () async {
    final gate = Completer<void>();
    network.gate = gate;
    final cancellation = ForumRequestCancellation();
    final pending = repository.load(
      ForumFriendDirectoryQuery(cancellation: cancellation),
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    gate.complete();
    expect((await pending).failureOrNull!.kind, DataReadFailureKind.cancelled);
  });

  test('different origin and login status cannot become friend rows', () async {
    network.uri = Uri.parse('https://other.example/home.php');
    expect(
      (await repository.load(const ForumFriendDirectoryQuery())).isFailure,
      isTrue,
    );
    network.uri = null;
    network.statusCode = 401;
    expect(
      (await repository.load(
        const ForumFriendDirectoryQuery(),
      )).failureOrNull!.kind,
      DataReadFailureKind.unauthorized,
    );
  });
}

const _literal =
    r"{'userdata':{12:{'uid':12,'username':'A\'友\\B','avatar':'/uc_server/avatar.php?uid=12&size=small'}},'maxfriendnum':'41','singlenum':'1'}";
String _envelope(String literal) =>
    '<?xml version="1.0" encoding="UTF-8"?><root><![CDATA[$literal]]></root>';

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  String body = _envelope(_literal);
  Completer<void>? gate;
  Uri? uri;
  int statusCode = 200;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await gate?.future;
    return ForumTransportSuccess(
      ForumResponse(
        uri: uri ?? request.uri,
        statusCode: statusCode,
        headers: const {
          'content-type': ['text/xml'],
        },
        body: body,
      ),
    );
  }
}
