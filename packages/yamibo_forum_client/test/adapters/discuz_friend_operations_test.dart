import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  test(
    'request prepare reads complete form and submit sends only advertised gid',
    () async {
      final scenario = await _Scenario.create();
      final preparation = (await scenario.prepare()).dataOrNull!;
      expect(preparation.action, ForumFriendAction.request);
      expect(preparation.selectedGroupId, '1');
      expect(preparation.groups.map((group) => group.id), ['0', '1']);
      final result = await scenario.submit(
        preparation,
        groupId: '0',
        note: 'Hello',
      );
      expect(result, isA<DataCommandApplied<ForumFriendReceipt>>());
      expect(result.receiptOrNull?.action, ForumFriendAction.request);
      final request = scenario.network.requests.last;
      expect(request.body, containsPair('gid', '0'));
      expect(request.body, containsPair('note', 'Hello'));
      expect(request.allowWafReplay, isFalse);
      expect(
        await scenario.submit(preparation),
        isA<DataCommandNotSent<ForumFriendReceipt>>(),
      );
      expect(scenario.network.requests, hasLength(2));
    },
  );

  test(
    'pending inbound request uses approval form without request note',
    () async {
      final scenario = await _Scenario.create(
        action: ForumFriendAction.approve,
      );
      final preparation = (await scenario.prepare()).dataOrNull!;
      expect(preparation.action, ForumFriendAction.approve);
      expect(preparation.acceptsNote, isFalse);
      expect(
        await scenario.submit(preparation),
        isA<DataCommandApplied<ForumFriendReceipt>>(),
      );
      expect(
        scenario.network.requests.last.body,
        containsPair('add2submit', 'true'),
      );
      expect(scenario.network.requests.last.body, isNot(contains('note')));
    },
  );

  test('remove friendship sends the exact confirmed form endpoint', () async {
    final scenario = await _Scenario.create(action: ForumFriendAction.remove);
    final preparation = (await scenario.prepare()).dataOrNull!;
    expect(preparation.groups, isEmpty);
    expect(
      await scenario.submit(preparation),
      isA<DataCommandApplied<ForumFriendReceipt>>(),
    );
    expect(scenario.network.requests.last.uri.queryParameters['confirm'], '1');
    expect(
      scenario.network.requests.last.body,
      containsPair('friendsubmit', 'true'),
    );
  });

  test(
    'foreign identity captcha and unknown controls fail closed before POST',
    () async {
      for (final source in [
        _form(
          ForumFriendAction.request,
        ).replaceFirst("discuz_uid = '7654'", "discuz_uid = '9999'"),
        _form(
          ForumFriendAction.request,
        ).replaceFirst('</form>', '<input name="seccodeverify"></form>'),
        _form(ForumFriendAction.request).replaceFirst('uid=4242', 'uid=9999'),
        _form(ForumFriendAction.request).replaceFirst(
          'name="formhash" value="1234abcd"',
          'name="formhash" value=""',
        ),
      ]) {
        final scenario = await _Scenario.create(source: source);
        expect((await scenario.prepare()).dataOrNull, isNull);
        expect(scenario.network.requests, hasLength(1));
      }
    },
  );

  test('invalid gid notes cancelled or changed accounts cannot send', () async {
    final scenario = await _Scenario.create();
    final preparation = (await scenario.prepare()).dataOrNull!;
    expect(
      await scenario.submit(preparation, groupId: '99'),
      isA<DataCommandNotSent<ForumFriendReceipt>>(),
    );
    expect(
      await scenario.submit(preparation, note: 'x' * 31),
      isA<DataCommandNotSent<ForumFriendReceipt>>(),
    );
    final cancellation = ForumRequestCancellation()..cancel();
    expect(
      await scenario.operations.submit(
        ForumFriendSubmission(
          preparation: preparation,
          actorUserId: '7654',
          cancellation: cancellation,
        ),
      ),
      isA<DataCommandNotSent<ForumFriendReceipt>>(),
    );
    await scenario.sessions.clear();
    expect(
      await scenario.submit(preparation),
      isA<DataCommandNotSent<ForumFriendReceipt>>(),
    );
    expect(scenario.network.requests, hasLength(1));
  });

  test('ambiguous result stays unknown and cannot be replayed', () async {
    for (final reply in [
      '<html>Unproved response</html>',
      _callback(ForumFriendAction.approve).replaceFirst("'4242'", "'9999'"),
      _callback(
        ForumFriendAction.approve,
      ).replaceFirst('https://example.test/', 'https://other.test/'),
    ]) {
      final scenario = await _Scenario.create(
        action: ForumFriendAction.approve,
        reply: reply,
      );
      final preparation = (await scenario.prepare()).dataOrNull!;
      final result = await scenario.submit(preparation);
      expect(result, isA<DataCommandOutcomeUnknown<ForumFriendReceipt>>());
      expect(result.failureOrNull?.retryPolicy, DataCommandRetryPolicy.never);
      expect(
        await scenario.submit(preparation),
        isA<DataCommandNotSent<ForumFriendReceipt>>(),
      );
      expect(scenario.network.requests, hasLength(2));
    }
  });

  test(
    'explicit error callback rejects without exposing remote payload',
    () async {
      final scenario = await _Scenario.create(
        reply: '''<script>
      if(typeof errorhandle_y300friend_7654_4242 == 'function') {
        errorhandle_y300friend_7654_4242('Private remote payload', {});
      }</script>''',
      );
      final result = await scenario.submit(
        (await scenario.prepare()).dataOrNull!,
      );
      expect(result, isA<DataCommandRejected<ForumFriendReceipt>>());
      expect(
        result.failureOrNull?.diagnosticMessage,
        'friend_operation_rejected',
      );
    },
  );
}

String _form(ForumFriendAction action) {
  final id = switch (action) {
    ForumFriendAction.request => 'addform_4242',
    ForumFriendAction.approve => 'addratifyform_4242',
    ForumFriendAction.remove => 'friendform_4242',
  };
  final submit = switch (action) {
    ForumFriendAction.request => 'addsubmit',
    ForumFriendAction.approve => 'add2submit',
    ForumFriendAction.remove => 'friendsubmit',
  };
  return '''<html><head><script>var discuz_uid = '7654';</script></head><body>
    <form id="$id" method="post" action="home.php?mod=spacecp&amp;ac=friend&amp;op=${action == ForumFriendAction.remove ? 'ignore' : 'add'}&amp;uid=4242${action == ForumFriendAction.remove ? '&amp;confirm=1&amp;loc=1' : ''}">
    <input type="hidden" name="referer" value="home.php">
    <input type="hidden" name="$submit" value="true">
    <input type="hidden" name="formhash" value="1234abcd">
    ${switch (action) {
    ForumFriendAction.request => '<input name="note" type="text"><select name="gid"><option value="0">Default</option><option value="1" selected>Friends</option></select>',
    ForumFriendAction.approve => '<label><input name="gid" type="radio" value="0">Default</label><label><input name="gid" type="radio" value="1" checked>Friends</label>',
    ForumFriendAction.remove => '',
  }}
    <button type="submit" name="${submit}_btn">Confirm</button></form></body></html>''';
}

String _callback(ForumFriendAction action) =>
    '''<script>
if(typeof succeedhandle_y300friend_7654_4242 == 'function') {
  succeedhandle_y300friend_7654_4242('${action == ForumFriendAction.remove ? 'https://example.test/home.php?mod=spacecp&ac=friend&op=request' : 'https://example.test/home.php?mod=space&uid=4242&do=profile&mobile=2'}', 'Private message', ${action == ForumFriendAction.request ? '{}' : "{'uid':'4242'}"});
}</script>''';

final class _Scenario {
  _Scenario(this.operations, this.network, this.sessions, this.action);
  final ForumFriendOperations operations;
  final _Network network;
  final MemoryForumSessionStore sessions;
  final ForumFriendAction action;
  static Future<_Scenario> create({
    ForumFriendAction action = ForumFriendAction.request,
    String? source,
    String? reply,
  }) async {
    final sessions = MemoryForumSessionStore();
    await sessions.merge(
      ForumSessionSnapshot(
        isLoggedIn: true,
        userId: '7654',
        username: 'Fixture',
        formhash: '1234abcd',
        updatedAt: DateTime.now(),
        source: 'test',
      ),
    );
    final network = _Network(
      source ?? _form(action),
      reply ?? _callback(action),
    );
    return _Scenario(
      ForumClientAdapterFactory(
        config: ForumClientConfig(
          siteOrigin: Uri.parse('https://example.test'),
          apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
          userAgent: 'test',
          desktopUserAgent: 'test',
        ),
        network: network,
        sessionStore: sessions,
      ).createFriendOperations(),
      network,
      sessions,
      action,
    );
  }

  Future<DataReadResult<ForumFriendPreparation, ForumFriendReadCapabilities>>
  prepare() => operations.prepare(
    ForumFriendQuery(
      actorUserId: '7654',
      targetUserId: '4242',
      actionLink: ForumUserProfileActionLink(
        kind: action == ForumFriendAction.remove
            ? ForumUserProfileActionKind.removeFriend
            : ForumUserProfileActionKind.addFriend,
        uri: Uri.parse(
          'https://example.test/home.php?mod=spacecp&ac=friend&op=${action == ForumFriendAction.remove ? 'ignore' : 'add'}&uid=4242',
        ),
      ),
    ),
  );
  Future<DataCommandResult<ForumFriendReceipt>> submit(
    ForumFriendPreparation preparation, {
    String? groupId,
    String note = '',
  }) => operations.submit(
    ForumFriendSubmission(
      preparation: preparation,
      actorUserId: '7654',
      groupId: groupId,
      note: note,
    ),
  );
}

final class _Network implements ForumClientNetwork {
  _Network(this.source, this.reply);
  final String source;
  final String reply;
  final requests = <ForumRequest>[];
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: request.method == ForumRequestMethod.get
            ? source
            : reply.replaceAll(
                'y300friend_7654_4242',
                request.uri.queryParameters['handlekey']!,
              ),
      ),
    );
  }
}
