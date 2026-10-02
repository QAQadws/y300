import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://forum.example.test'),
    apiOrigin: Uri.parse('https://forum.example.test/api/mobile/index.php'),
    userAgent: 'fixture',
  );
  late _Network network;
  late _Formhash formhash;
  late ForumPrivateMessageCommand command;
  setUp(() {
    network = _Network();
    formhash = _Formhash();
    command = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createPrivateMessageCommand(formhash);
  });

  for (final recipient in [
    const ForumPrivateMessageRecipient.user('20'),
    const ForumPrivateMessageRecipient.username('收件人 & A'),
    const ForumPrivateMessageRecipient.group(
      conversationId: '91',
      replyMessageId: '81',
    ),
  ]) {
    test(
      'sends ${recipient.kind.name} via a single v1 POST without private URL parameters',
      () async {
        const content = '繁體 & 简体\n[quote]hello[/quote] + = ?';
        final result = await command.execute(
          ForumPrivateMessageSubmission(recipient: recipient, message: content),
        );
        expect(result, isA<DataCommandApplied<ForumPrivateMessageReceipt>>());
        expect(result.receiptOrNull!.messageId, '900');
        expect(result.receiptOrNull!.recipient, same(recipient));
        expect(formhash.calls, 1);
        final request = network.requests.single;
        expect(request.method, ForumRequestMethod.post);
        expect(request.uri.queryParameters, {
          'module': 'sendpm',
          'version': '1',
        });
        expect(request.body, {
          'formhash': 'fixture-hash',
          'pmsubmit': 'true',
          'message': content,
          switch (recipient.kind) {
            ForumPrivateMessageRecipientKind.user => 'touid',
            ForumPrivateMessageRecipientKind.username => 'username',
            ForumPrivateMessageRecipientKind.group => 'plid',
          }: recipient.value,
          if (recipient.kind == ForumPrivateMessageRecipientKind.group)
            'pmid': '81',
        });
        expect(
          request.headers['Content-Type'],
          'application/x-www-form-urlencoded',
        );
      },
    );
  }

  for (final recipient in [
    const ForumPrivateMessageRecipient.user('0'),
    const ForumPrivateMessageRecipient.user('2&x=1'),
    const ForumPrivateMessageRecipient.username('a,b'),
    const ForumPrivateMessageRecipient.username('  '),
    const ForumPrivateMessageRecipient.username('a\nb'),
    const ForumPrivateMessageRecipient.group(
      conversationId: '91',
      replyMessageId: '',
    ),
    const ForumPrivateMessageRecipient.group(
      conversationId: '',
      replyMessageId: '81',
    ),
  ]) {
    test(
      'rejects invalid ${recipient.kind.name} destination before preparation: ${recipient.value}',
      () async {
        final result = await command.execute(
          ForumPrivateMessageSubmission(recipient: recipient, message: 'hello'),
        );
        expect(result, isA<DataCommandNotSent<ForumPrivateMessageReceipt>>());
        expect(formhash.calls, 0);
        expect(network.requests, isEmpty);
      },
    );
  }

  test('empty input does not load formhash or submit', () async {
    final result = await command.execute(
      const ForumPrivateMessageSubmission(
        recipient: ForumPrivateMessageRecipient.user('20'),
        message: ' \n ',
      ),
    );
    expect(result, isA<DataCommandNotSent<ForumPrivateMessageReceipt>>());
    expect(formhash.calls, 0);
    expect(network.requests, isEmpty);
  });

  test(
    'accepts only exact success with a positive returned message ID',
    () async {
      for (final body in [
        _envelope(code: 'do_success', id: '0'),
        _envelope(code: 'do_success', id: ''),
        _envelope(code: 'do_success//1'),
        _envelope(code: 'do_success_other'),
        _envelope(code: 'message_send_result'),
        _envelope(code: ''),
        _envelope(version: '4'),
        '<html>do_success</html>',
      ]) {
        network.body = body;
        final result = await command.execute(_submission);
        expect(
          result,
          isA<DataCommandOutcomeUnknown<ForumPrivateMessageReceipt>>(),
          reason: '$body',
        );
        expect(
          result.failureOrNull!.retryPolicy,
          DataCommandRetryPolicy.explicitOnly,
        );
      }
      network.body = _envelope(code: 'mobile:do_success');
      expect(
        await command.execute(_submission),
        isA<DataCommandApplied<ForumPrivateMessageReceipt>>(),
      );
    },
  );

  test('known rejections are safe and never replay the command', () async {
    final cases = {
      'to_login//1': DataCommandFailureKind.unauthenticated,
      'submit_invalid': DataCommandFailureKind.staleFormhash,
      'no_privilege_sendpm': DataCommandFailureKind.permissionDenied,
      'is_blacklist': DataCommandFailureKind.permissionDenied,
      'message_can_not_send_onlyfriend':
          DataCommandFailureKind.permissionDenied,
      'message_bad_touser': DataCommandFailureKind.validation,
      'message_can_not_send_to_self': DataCommandFailureKind.validation,
      for (var index = 1; index <= 16; index++)
        'message_can_not_send_$index': DataCommandFailureKind.validation,
    };
    for (final entry in cases.entries) {
      network.requests.clear();
      network.body = _envelope(code: entry.key);
      final result = await command.execute(_submission);
      expect(
        result,
        isA<DataCommandRejected<ForumPrivateMessageReceipt>>(),
        reason: entry.key,
      );
      expect(result.failureOrNull!.kind, entry.value, reason: entry.key);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private payload')),
      );
      expect(network.requests, hasLength(1));
    }
  });

  test('preparation failure and cancellation send no write', () async {
    formhash.result = const ForumFormhashError(
      ForumTransportFailure(
        kind: ForumTransportFailureKind.unauthorized,
        code: 'session_expired',
      ),
    );
    expect(
      await command.execute(_submission),
      isA<DataCommandNotSent<ForumPrivateMessageReceipt>>(),
    );
    formhash.result = const ForumFormhashSuccess('');
    expect(
      await command.execute(_submission),
      isA<DataCommandNotSent<ForumPrivateMessageReceipt>>(),
    );
    formhash.throws = true;
    expect(
      await command.execute(_submission),
      isA<DataCommandNotSent<ForumPrivateMessageReceipt>>(),
    );
    expect(network.requests, isEmpty);
  });

  test(
    'cancelling during formhash preparation prevents a later POST',
    () async {
      final cancellation = ForumRequestCancellation();
      formhash.pending = Completer<void>();
      final result = command.execute(
        ForumPrivateMessageSubmission(
          recipient: _submission.recipient,
          message: _submission.message,
          cancellation: cancellation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      formhash.pending!.complete();
      expect(
        await result,
        isA<DataCommandNotSent<ForumPrivateMessageReceipt>>(),
      );
      expect(network.requests, isEmpty);
      final calls = formhash.calls;
      await command.execute(
        ForumPrivateMessageSubmission(
          recipient: _submission.recipient,
          message: _submission.message,
          cancellation: cancellation,
        ),
      );
      expect(formhash.calls, calls);
    },
  );

  test(
    'transport timeout, cancellation and exceptions remain inconclusive',
    () async {
      for (final kind in [
        ForumTransportFailureKind.timeout,
        ForumTransportFailureKind.cancelled,
        ForumTransportFailureKind.network,
      ]) {
        network.requests.clear();
        network.failure = ForumTransportFailure(
          kind: kind,
          code: 'fixture_failure',
        );
        final result = await command.execute(_submission);
        expect(
          result,
          isA<DataCommandOutcomeUnknown<ForumPrivateMessageReceipt>>(),
        );
        expect(
          result.failureOrNull!.retryPolicy,
          DataCommandRetryPolicy.explicitOnly,
        );
        expect(network.requests, hasLength(1));
      }
      network.failure = null;
      network.throws = true;
      expect(
        await command.execute(_submission),
        isA<DataCommandOutcomeUnknown<ForumPrivateMessageReceipt>>(),
      );
    },
  );

  test(
    'cancellation after send does not erase explicit success evidence',
    () async {
      final cancellation = ForumRequestCancellation();
      network.pending = Completer<void>();
      final result = command.execute(
        ForumPrivateMessageSubmission(
          recipient: _submission.recipient,
          message: _submission.message,
          cancellation: cancellation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(network.requests.single.cancellation, same(cancellation));
      cancellation.cancel();
      network.pending!.complete();
      expect(
        await result,
        isA<DataCommandApplied<ForumPrivateMessageReceipt>>(),
      );
    },
  );

  test(
    'facade handles missing commands and preserves source overlays',
    () async {
      final missing = YamiboForumClient(config: config, network: network);
      expect(
        await missing.sendPrivateMessage(_submission),
        isA<DataCommandUnsupported<ForumPrivateMessageReceipt>>(),
      );
      final installed = YamiboForumClientBuilder(
        config: config,
        network: network,
        formhashProvider: formhash,
      ).buildStandardClient();
      expect(
        await installed.sendPrivateMessage(_submission),
        isA<DataCommandApplied<ForumPrivateMessageReceipt>>(),
      );
      final plan = ForumClientSourcePlan(privateMessageCommand: command);
      expect(
        plan.overlay(const ForumClientSourcePlan()).privateMessageCommand,
        same(command),
      );
      expect(
        const ForumClientSourcePlan().overlay(plan).privateMessageCommand,
        same(command),
      );
    },
  );
}

const _submission = ForumPrivateMessageSubmission(
  recipient: ForumPrivateMessageRecipient.user('20'),
  message: 'hello',
);

Map<String, Object?> _envelope({
  String code = 'do_success',
  String id = '900',
  String version = '1',
}) => {
  'Version': version,
  'Variables': {'pmid': id},
  'Message': {'messageval': code, 'messagestr': 'private payload'},
};

final class _Network implements ForumClientNetwork {
  Object? body = _envelope();
  ForumTransportFailure? failure;
  bool throws = false;
  Completer<void>? pending;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await pending?.future;
    if (throws) throw StateError('private payload');
    final error = failure;
    if (error != null) return ForumTransportError(error);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}

final class _Formhash implements ForumFormhashProvider {
  int calls = 0;
  bool throws = false;
  Completer<void>? pending;
  ForumFormhashResult result = const ForumFormhashSuccess('fixture-hash');

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async {
    calls++;
    await pending?.future;
    if (throws) throw StateError('private payload');
    return result;
  }
}
