import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://forum.example.test'),
    userAgent: 'mobile-fixture',
    desktopUserAgent: 'desktop-fixture',
  );
  late _Network network;
  late ForumPrivateMessageBatchCommand command;
  late ForumPrivateMessageBatchPreparationRepository preparation;
  setUp(() {
    network = _Network();
    final roles = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createPrivateMessageBatch();
    command = roles.command;
    preparation = roles.preparation;
  });

  test(
    'fresh desktop form and one ordered users[] POST preserve content',
    () async {
      const content = "[quote]繁體 & 简体 + = ?[/quote]\n:smile:";
      network.postBody = _success(2);
      final result = await command.execute(
        ForumPrivateMessageBatchSubmission(
          usernames: [' 收件人 & A ', "B'友", '收件人 & A'],
          message: content,
        ),
      );
      expect(
        result,
        isA<DataCommandApplied<ForumPrivateMessageBatchReceipt>>(),
      );
      final receipt = result.receiptOrNull!;
      expect(receipt.usernames, ['收件人 & A', "B'友"]);
      expect(receipt.serverReportedAcceptedCount, 2);
      expect(receipt.excludedUsernames, isEmpty);
      expect(receipt.confirmsSingleRecipient, isFalse);
      expect(network.requests.map((r) => r.method), [
        ForumRequestMethod.get,
        ForumRequestMethod.post,
      ]);
      for (final request in network.requests) {
        expect(request.headers['User-Agent'], 'desktop-fixture');
        expect(request.uri.queryParameters.containsKey('mobile'), isFalse);
        expect(request.uri.path, '/home.php');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Referer'] ?? '', isNot(contains('mobile')));
      }
      final post = network.requests.last;
      expect(post.uri.queryParameters['ajaxdata'], 'json');
      expect(post.uri.queryParameters['op'], 'send');
      final fields = post.body! as ForumFormFields;
      expect(
        fields.entries.where((e) => e.key == 'users[]').map((e) => e.value),
        ['收件人 & A', "B'友"],
      );
      expect(
        fields.entries.singleWhere((e) => e.key == 'message').value,
        content,
      );
      expect(fields.entries.singleWhere((e) => e.key == 'type').value, '0');
      expect(
        fields.entries.any(
          (e) =>
              ['username', 'subject', 'plid', 'pmid', 'touid'].contains(e.key),
        ),
        isFalse,
      );
      expect(fields.encode(), contains('users%5B%5D='));
      expect(() => receipt.usernames.add('mutated'), throwsUnsupportedError);
      expect(
        () => receipt.excludedUsernames.add('mutated'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'one recipient is confirmed; excluded batch remains aggregate only',
    () async {
      final single = await command.execute(_submission());
      expect(single.receiptOrNull!.confirmsSingleRecipient, isTrue);
      network.postBody = _success(1, excluded: 'B');
      final partial = await command.execute(_submission(users: ['A', 'B']));
      expect(
        partial,
        isA<DataCommandApplied<ForumPrivateMessageBatchReceipt>>(),
      );
      expect(partial.receiptOrNull!.excludedUsernames, ['B']);
      expect(partial.receiptOrNull!.confirmsSingleRecipient, isFalse);
    },
  );

  test(
    'preparing publicly does not permit reusing its formhash on execute',
    () async {
      expect(
        (await preparation.prepare(
          const ForumPrivateMessageBatchPreparationRequest(),
        )).isSuccess,
        isTrue,
      );
      network.getBody = _form.replaceAll('abcd1234', 'efgh5678');
      await command.execute(_submission());
      expect(network.requests.map((r) => r.method), [
        ForumRequestMethod.get,
        ForumRequestMethod.get,
        ForumRequestMethod.post,
      ]);
      final fields = network.requests.last.body! as ForumFormFields;
      expect(
        fields.entries.singleWhere((e) => e.key == 'formhash').value,
        'efgh5678',
      );
    },
  );

  test(
    'submission snapshots caller-owned recipients before async preparation',
    () async {
      final usernames = ['A'];
      final submission = ForumPrivateMessageBatchSubmission(
        usernames: usernames,
        message: 'hello',
      );
      usernames[0] = 'B';
      expect(() => submission.usernames.add('C'), throwsUnsupportedError);
      final result = await command.execute(submission);
      expect(result.receiptOrNull!.usernames, ['A']);
    },
  );

  test('invalid recipient/message sends no request', () async {
    for (final submission in [
      _submission(users: []),
      _submission(users: [' ']),
      _submission(users: ['A,B']),
      _submission(users: ['A\nB']),
      _submission(users: List.generate(21, (i) => 'user$i')),
      ForumPrivateMessageBatchSubmission(usernames: ['A'], message: ' \n'),
    ]) {
      expect(
        await command.execute(submission),
        isA<DataCommandNotSent<ForumPrivateMessageBatchReceipt>>(),
      );
    }
    expect(network.requests, isEmpty);
  });

  test('unsafe or ambiguous prepared form never dispatches POST', () async {
    for (final body in [
      '<html>login</html>',
      _form.replaceAll('home.php?', 'https://other.example/home.php?'),
      _form.replaceAll('&amp;touid=0', '&amp;touid=20'),
      _form.replaceAll('&amp;pmid=0', '&amp;pmid=80'),
      _form.replaceAll('&amp;pmid=0', '&amp;pmid=0&amp;mobile=2'),
      _form.replaceAll('&amp;pmid=0', '&amp;pmid=0&amp;op=delete'),
      _form.replaceAll('name="username"', 'name="subject"'),
      _form.replaceAll('</form>', '<input name="type" value="1"></form>'),
      _form.replaceAll(
        '</form>',
        '<input name="type" value="0"><input name="type" value="1"></form>',
      ),
      _form.replaceAll(
        '</form>',
        '<input name="formhash" value="abcd1234"></form>',
      ),
      _form.replaceAll('</form>', '<input name="seccodeverify"></form>'),
      '$_form$_form',
    ]) {
      network.requests.clear();
      network.getBody = body;
      expect(
        await command.execute(_submission()),
        isA<DataCommandNotSent<ForumPrivateMessageBatchReceipt>>(),
      );
      expect(network.requests.map((r) => r.method), [ForumRequestMethod.get]);
    }
  });

  test('cancellation before and during preparation prevents POST', () async {
    final cancelled = ForumRequestCancellation()..cancel();
    expect(
      await command.execute(_submission(cancellation: cancelled)),
      isA<DataCommandNotSent<ForumPrivateMessageBatchReceipt>>(),
    );
    expect(network.requests, isEmpty);
    final gate = Completer<void>();
    network.getGate = gate;
    final cancellation = ForumRequestCancellation();
    final pending = command.execute(_submission(cancellation: cancellation));
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    gate.complete();
    expect(
      await pending,
      isA<DataCommandNotSent<ForumPrivateMessageBatchReceipt>>(),
    );
    expect(network.requests, hasLength(1));
  });

  test('failure or cancellation after dispatch never retries a POST', () async {
    for (final kind in [
      ForumTransportFailureKind.timeout,
      ForumTransportFailureKind.cancelled,
      ForumTransportFailureKind.network,
    ]) {
      network.requests.clear();
      network.postFailure = kind;
      final result = await command.execute(_submission());
      expect(
        result,
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
      expect(
        result.failureOrNull!.retryPolicy,
        DataCommandRetryPolicy.explicitOnly,
      );
      expect(
        network.requests.where((r) => r.method == ForumRequestMethod.post),
        hasLength(1),
      );
    }
  });

  test(
    'only exact known JSON rejections are rejected; payload is never exposed',
    () async {
      network.postBody = jsonEncode({
        'message': '抱歉，用户不存在或被冻结，请检查用户名是否正确',
        'data': <Object?>[],
      });
      final result = await command.execute(_submission());
      expect(
        result,
        isA<DataCommandRejected<ForumPrivateMessageBatchReceipt>>(),
      );
      expect(result.failureOrNull!.code, 'message_bad_touser');
      expect(result.failureOrNull!.diagnosticMessage, 'message_bad_touser');
      network.postBody = jsonEncode({
        'message': 'private payload unknown',
        'data': <Object?>[],
      });
      final unknown = await command.execute(_submission());
      expect(
        unknown,
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
      expect(
        unknown.failureOrNull!.diagnosticMessage,
        isNot(contains('private payload')),
      );
    },
  );

  test('malformed or contradictory aggregates remain unknown', () async {
    for (final body in [
      _success(0),
      _success(3),
      _success(1),
      _success(1, excluded: 'C'),
      _success(1, excluded: 'B,B'),
      jsonEncode({
        'message': 'ok',
        'data': {'users': '', 'succeed': '2'},
      }),
      jsonEncode({
        'message': 'ok',
        'data': {'users': '', 'succeed': 2, 'pmid': 123},
      }),
      jsonEncode({
        'message': 'ok',
        'data': {'pmid': 123},
      }),
      '{"message":"ok","data":{"users":"","succeed":0,"succeed":2}}',
      '{"message":"ok","data":{"users":"","succeed":0},"data":{"users":"","succeed":2}}',
      r'{"message":"ok","data":{"users":"","succeed":0,"\u0073ucceed":2}}',
      '<root><![CDATA[<script>succeedhandle_pm()</script>]]></root>',
      '<html>challenge</html>',
    ]) {
      network.postBody = body;
      expect(
        await command.execute(_submission(users: ['A', 'B'])),
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
    }
  });

  test(
    'redirect, different final URI, and HTML content type cannot prove success',
    () async {
      network.postStatus = 302;
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
      network.postStatus = 200;
      network.postUri = Uri.parse('https://other.example/home.php');
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
      network.postUri = null;
      network.contentType = 'text/html';
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>>(),
      );
    },
  );

  test(
    'standard builder exposes batch and friends without changing old command',
    () {
      final client = YamiboForumClientBuilder(
        config: config,
        network: network,
      ).buildStandardClient();
      expect(client.friendDirectory, isNotNull);
      expect(client.privateMessageBatchPreparation, isNotNull);
      expect(client.privateMessageBatchCommand, isNotNull);
      expect(client.sourcePlan.privateMessageCommand, isNotNull);
    },
  );

  test('omitted new sources fail closed through facade', () async {
    final client = YamiboForumClient(config: config, network: network);
    expect(
      await client.sendPrivateMessageBatch(_submission()),
      isA<DataCommandUnsupported<ForumPrivateMessageBatchReceipt>>(),
    );
    expect(
      (await client.loadFriends(
        const ForumFriendDirectoryQuery(),
      )).failureOrNull!.kind,
      DataReadFailureKind.unsupported,
    );
    expect(
      (await client.preparePrivateMessageBatch(
        const ForumPrivateMessageBatchPreparationRequest(),
      )).failureOrNull!.kind,
      DataReadFailureKind.unsupported,
    );
  });
}

ForumPrivateMessageBatchSubmission _submission({
  List<String> users = const ['A'],
  ForumRequestCancellation? cancellation,
}) => ForumPrivateMessageBatchSubmission(
  usernames: users,
  message: 'hello',
  cancellation: cancellation,
);

String _success(int count, {String excluded = ''}) => jsonEncode({
  'message': 'fixture success',
  'data': {'users': excluded, 'succeed': count},
});

const _form = '''<html><body>
<form method="post" action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;touid=0&amp;pmid=0">
<input type="hidden" name="pmsubmit" value="true">
<input type="hidden" name="formhash" value="abcd1234">
<input name="username"><textarea name="message"></textarea>
</form></body></html>''';

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  String getBody = _form;
  String postBody = _success(1);
  Completer<void>? getGate;
  ForumTransportFailureKind? postFailure;
  int postStatus = 200;
  Uri? postUri;
  String contentType = 'application/json; charset=utf-8';

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (request.method == ForumRequestMethod.get) {
      await getGate?.future;
      return ForumTransportSuccess(
        ForumResponse(
          uri: request.uri,
          statusCode: 200,
          headers: const {},
          body: getBody,
        ),
      );
    }
    if (postFailure case final kind?) {
      return ForumTransportError(
        ForumTransportFailure(kind: kind, code: 'fixture'),
      );
    }
    return ForumTransportSuccess(
      ForumResponse(
        uri: postUri ?? request.uri,
        statusCode: postStatus,
        headers: {
          'content-type': [contentType],
        },
        body: postBody,
      ),
    );
  }
}
