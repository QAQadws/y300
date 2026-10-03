import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late MemoryForumSessionStore sessions;
  late ForumFriendRemovalCommand command;
  setUp(() async {
    network = _Network();
    sessions = MemoryForumSessionStore();
    await sessions.merge(_session('7'));
    command = ForumClientAdapterFactory(
      config: _config,
      network: network,
      sessionStore: sessions,
    ).createFriendRemovalCommand();
  });

  test(
    'prepares fresh actor-bound form and submits once for the exact friend',
    () async {
      final result = await command.execute(_submission);
      expect(result, isA<DataCommandApplied<ForumFriendRemovalReceipt>>());
      expect(result.receiptOrNull!.actorUserId, '7');
      expect(result.receiptOrNull!.userId, '12');
      expect(network.requests, hasLength(2));
      final prepare = network.requests.first;
      expect(prepare.method, ForumRequestMethod.get);
      expect(prepare.uri.queryParameters, {
        'mod': 'spacecp',
        'ac': 'friend',
        'op': 'ignore',
        'uid': '12',
        'mobile': 'no',
      });
      final submit = network.requests.last;
      expect(submit.method, ForumRequestMethod.post);
      expect(submit.headers['User-Agent'], 'desktop');
      expect(submit.followRedirects, isFalse);
      expect(submit.allowWafReplay, isFalse);
      expect(submit.uri.queryParameters['uid'], '12');
      expect(submit.uri.queryParameters['confirm'], '1');
      expect(submit.uri.queryParameters['inajax'], '1');
      expect(submit.body, {
        'friendsubmit': 'true',
        'formhash': 'a1b2c3d4',
        'referer': 'https://forum.example.test/home.php?mod=space&do=friend',
        'from': '',
        'handlekey': 'y300_friend_remove',
      });
    },
  );

  test('mismatched or ambiguous form fields never send a mutation', () async {
    final fixtures = [
      _form(actor: '8'),
      _form(target: '13'),
      _form(hash: 'bad-hash'),
      _form().replaceAll('method="post"', 'method="get"'),
      _form().replaceAll('uid=12', 'uid=12&amp;uid=13'),
      _form().replaceAll(
        'home.php?mod=spacecp',
        'https://other.test/home.php?mod=spacecp',
      ),
      _form().replaceAll('value="a1b2c3d4"', 'value="a1b2c3d4" disabled'),
      _form().replaceAll(
        '</form>',
        '<input type="hidden" name="formhash" value="b1b2c3d4"></form>',
      ),
      _form().replaceAll(
        '</form>',
        '<input type="hidden" name="fuids[]" value="99"></form>',
      ),
      _form().replaceAll('confirm=1', 'confirm=1&amp;key=bulk-secret'),
      '<div id="messagetext">private server notice</div>',
    ];
    for (final form in fixtures) {
      network.form = form;
      network.requests.clear();
      final result = await command.execute(_submission);
      expect(
        result,
        isA<DataCommandNotSent<ForumFriendRemovalReceipt>>(),
        reason: form,
      );
      expect(network.requests, hasLength(1));
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private server notice')),
      );
    }
  });

  test(
    'literal success callback must prove target and safe friend-request destination',
    () async {
      for (final response in [
        '操作成功',
        _success(target: '13'),
        _success(from: 'notice'),
        _success(
          forward:
              'https://other.test/home.php?mod=spacecp&ac=friend&op=request',
        ),
        _success(forward: 'home.php?mod=spacecp&ac=friend&op=request&uid=99'),
        _success().replaceAll("'uid':'12'", "'uid':'12','uid':'13'"),
        _success().replaceAll("'uid':'12'", "'uid':doSomething()"),
        _success().replaceAll('y300_friend_remove', 'unrelated'),
        _success() + _success(),
        '<script>var text="succeedhandle_y300_friend_remove(\'done\')";</script>',
        _success()
            .replaceAll('<script>', '<div>')
            .replaceAll('</script>', '</div>'),
        '<root><![CDATA[${_success()}]]><![CDATA[ignored]]></root>',
        _form() + _success(),
      ]) {
        network.response = response;
        network.requests.clear();
        final result = await command.execute(_submission);
        expect(
          result,
          isA<DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>>(),
          reason: response,
        );
        expect(result.failureOrNull!.retryPolicy, DataCommandRetryPolicy.never);
        expect(
          network.requests.where(
            (request) => request.method == ForumRequestMethod.post,
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'escaped response message cannot fabricate or break callback evidence',
    () async {
      network.response = _success().replaceAll(
        "'done'",
        r"'can\'t disclose private text'",
      );
      expect(
        await command.execute(_submission),
        isA<DataCommandApplied<ForumFriendRemovalReceipt>>(),
      );
    },
  );

  test('one actual server rejection remains safe and explicit', () async {
    network.response =
        '<root><![CDATA[<script>if(typeof errorhandle_y300_friend_remove==\'function\') {errorhandle_y300_friend_remove(\'private server rejection\', {});}</script>]]></root>';
    final result = await command.execute(_submission);
    expect(result, isA<DataCommandRejected<ForumFriendRemovalReceipt>>());
    expect(result.failureOrNull!.diagnosticMessage, 'friend_removal_rejected');
  });

  test(
    'transport errors after submission are unknown and never resent',
    () async {
      network.failPost = true;
      final result = await command.execute(_submission);
      expect(
        result,
        isA<DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>>(),
      );
      expect(
        network.requests.where(
          (request) => request.method == ForumRequestMethod.post,
        ),
        hasLength(1),
      );
      network.failPost = false;
      network.postStatus = 302;
      expect(
        await command.execute(_submission),
        isA<DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>>(),
      );
    },
  );

  test(
    'invalid actor, self target and early cancellation never reach transport',
    () async {
      for (final submission in [
        const ForumFriendRemovalSubmission(actorUserId: '7', userId: '7'),
        const ForumFriendRemovalSubmission(actorUserId: '8', userId: '12'),
        const ForumFriendRemovalSubmission(actorUserId: '7', userId: '0'),
        ForumFriendRemovalSubmission(
          actorUserId: '7',
          userId: '12',
          cancellation: ForumRequestCancellation()..cancel(),
        ),
      ]) {
        expect(
          await command.execute(submission),
          isA<DataCommandNotSent<ForumFriendRemovalReceipt>>(),
        );
      }
      expect(network.requests, isEmpty);
    },
  );

  test('account change during preparation prevents POST', () async {
    network.getGate = Completer<void>();
    final pending = command.execute(_submission);
    await Future<void>.delayed(Duration.zero);
    await sessions.merge(_session('8'));
    network.getGate!.complete();
    expect(await pending, isA<DataCommandNotSent<ForumFriendRemovalReceipt>>());
    expect(network.requests, hasLength(1));
  });

  test('late cancellation after POST cannot publish applied receipt', () async {
    network.postGate = Completer<void>();
    final cancellation = ForumRequestCancellation();
    final pending = command.execute(
      ForumFriendRemovalSubmission(
        actorUserId: '7',
        userId: '12',
        cancellation: cancellation,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    network.postGate!.complete();
    expect(
      await pending,
      isA<DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>>(),
    );
    expect(network.requests, hasLength(2));
  });

  test(
    'facade absent command is unsupported and overlays preserve installation',
    () async {
      final missing = YamiboForumClient(config: _config, network: network);
      expect(
        await missing.removeFriend(_submission),
        isA<DataCommandUnsupported<ForumFriendRemovalReceipt>>(),
      );
      final plan = ForumClientSourcePlan(friendRemovalCommand: command);
      expect(
        plan.overlay(const ForumClientSourcePlan()).friendRemovalCommand,
        same(command),
      );
      expect(
        const ForumClientSourcePlan().overlay(plan).friendRemovalCommand,
        same(command),
      );
    },
  );
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://forum.example.test'),
  userAgent: 'mobile',
  desktopUserAgent: 'desktop',
);
const _submission = ForumFriendRemovalSubmission(
  actorUserId: '7',
  userId: '12',
);
ForumSessionSnapshot _session(String actor) => ForumSessionSnapshot(
  isLoggedIn: true,
  userId: actor,
  username: 'actor',
  formhash: 'a1b2c3d4',
  updatedAt: DateTime(2026),
  source: 'fixture',
);
String _form({
  String actor = '7',
  String target = '12',
  String hash = 'a1b2c3d4',
}) =>
    '<html><head><script>var discuz_uid = \'$actor\';</script></head><body><form id="friendform_$target" method="post" action="home.php?mod=spacecp&amp;ac=friend&amp;op=ignore&amp;uid=$target&amp;confirm=1"><input type="hidden" name="referer" value="home.php"><input type="hidden" name="friendsubmit" value="true"><input type="hidden" name="formhash" value="$hash"><input type="hidden" name="from" value=""><button name="friendsubmit_btn" value="true">确认</button></form></body></html>';
String _success({
  String target = '12',
  String from = '',
  String forward = 'home.php?mod=spacecp&ac=friend&op=request',
}) =>
    '<root><![CDATA[<script>if(typeof succeedhandle_y300_friend_remove==\'function\') {succeedhandle_y300_friend_remove(\'$forward\', \'done\', {\'uid\':\'$target\',\'from\':\'$from\'});}hideWindow(\'y300_friend_remove\');showDialog(\'done\', \'right\');</script>]]></root>';

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  String form = _form();
  String response = _success();
  bool failPost = false;
  int postStatus = 200;
  Completer<void>? getGate;
  Completer<void>? postGate;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    final post = request.method == ForumRequestMethod.post;
    await (post ? postGate?.future : getGate?.future);
    if (post && failPost) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'fixture_timeout',
        ),
      );
    }
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: post ? postStatus : 200,
        headers: const {},
        body: post ? response : form,
      ),
    );
  }
}
