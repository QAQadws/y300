import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  final origin = Uri.parse('https://forum.example.test');
  final pageUri = Uri.parse(
    'https://forum.example.test/plugin.php?id=zqlj_sign&mobile=2',
  );
  final unsigned = File(
    'test/fixtures/daily_sign_in/unsigned.html',
  ).readAsStringSync(encoding: utf8);
  final signed = File(
    'test/fixtures/daily_sign_in/signed.html',
  ).readAsStringSync(encoding: utf8);
  final config = ForumClientConfig(siteOrigin: origin, userAgent: 'test-agent');

  YamiboForumClient client(_QueueNetwork network) => YamiboForumClientBuilder(
    config: config,
    network: network,
  ).buildStandardClient();

  test('standard facade reads a network-only unsigned snapshot', () async {
    final network = _QueueNetwork([_page(pageUri, unsigned)]);
    final forum = client(network);

    final result = await forum.loadDailySignIn(
      const ForumDailySignInQuery(userId: '42'),
    );

    expect(forum.dailySignIn, isNotNull);
    expect(forum.dailySignInCommand, isNotNull);
    final success =
        result
            as DataReadSuccess<
              ForumDailySignInSnapshot,
              ForumDailySignInReadCapabilities
            >;
    expect(success.data.userId, '42');
    expect(success.data.forumDay, '20300412');
    expect(success.data.status, ForumDailySignInStatus.unsigned);
    expect(success.metadata.origin, DataReadOrigin.network);
    expect(success.metadata.freshness, DataReadFreshness.current);
    expect(
      success.capabilities.supports(
        ForumDailySignInReadCapability.orderedStatistics,
      ),
      isTrue,
    );
    expect(network.requests, hasLength(1));
    expect(network.requests.single.uri, pageUri);
    expect(network.requests.single.method, ForumRequestMethod.get);
    expect(network.requests.single.followRedirects, isFalse);
    expect(network.requests.single.headers['User-Agent'], 'test-agent');
  });

  test('signed preparation sends no command GET', () async {
    final network = _QueueNetwork([_page(pageUri, signed)]);

    final result = await client(network).signInToday(
      const ForumDailySignInRequest(userId: '42', expectedForumDay: '20300412'),
    );

    expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
    expect(result.failureOrNull?.code, 'daily_sign_in_already_signed');
    expect(network.requests, hasLength(1));
    expect(network.requests.single.uri, pageUri);
  });

  test('unsigned preparation sends one guarded GET and a readback', () async {
    final network = _QueueNetwork([
      _page(pageUri, unsigned),
      _page(pageUri, '<html>synthetic response, not calibrated</html>'),
      _page(pageUri, signed),
    ]);

    final result = await client(network).signInToday(
      const ForumDailySignInRequest(userId: '42', expectedForumDay: '20300412'),
    );

    expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
    expect(result.receiptOrNull, isNull);
    expect(
      result.failureOrNull?.retryPolicy,
      DataCommandRetryPolicy.explicitOnly,
    );
    expect(network.requests, hasLength(3));
    expect(network.requests[0].uri, pageUri);
    expect(network.requests[2].uri, pageUri);
    expect(network.requests[0].followRedirects, isFalse);
    expect(network.requests[2].followRedirects, isFalse);
    final submission = network.requests[1];
    expect(submission.uri.queryParameters.keys.toSet(), {'id', 'sign'});
    expect(submission.uri.queryParameters['sign'], 'fixtureToken0001');
    expect(submission.followRedirects, isFalse);
    expect(submission.allowWafReplay, isFalse);
    expect(submission.context.silent, isTrue);
    expect(submission.headers['Referer'], pageUri.toString());
    expect(
      result.failureOrNull?.diagnosticMessage,
      isNot(contains('fixtureToken')),
    );
  });

  test(
    'send gate receives only verified identity and day before GET',
    () async {
      final network = _QueueNetwork([
        _page(pageUri, unsigned),
        _page(pageUri, '<html>synthetic response, not calibrated</html>'),
        _page(pageUri, signed),
      ]);
      ForumDailySignInPreparedAttempt? prepared;

      final result = await client(network).signInToday(
        ForumDailySignInRequest(
          userId: '42',
          expectedForumDay: '20300412',
          beforeSend: (attempt) async {
            expect(network.requests, hasLength(1));
            expect(network.requests.single.uri, pageUri);
            prepared = attempt;
            return ForumDailySignInSendAuthorization.allow;
          },
        ),
      );

      expect(prepared?.userId, '42');
      expect(prepared?.forumDay, '20300412');
      expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
      expect(network.requests, hasLength(3));
      expect(
        network.requests.where(
          (request) => request.uri.queryParameters.containsKey('sign'),
        ),
        hasLength(1),
      );
    },
  );

  test('send gate suppression and failure prevent command GET', () async {
    for (final (gate, code) in <(ForumDailySignInBeforeSend, String)>[
      (
        (_) async => ForumDailySignInSendAuthorization.suppress,
        'daily_sign_in_send_suppressed',
      ),
      (
        (_) async => ForumDailySignInSendAuthorization.unavailable,
        'daily_sign_in_send_gate_failed',
      ),
      (
        (_) async => throw StateError('secret detail'),
        'daily_sign_in_send_gate_failed',
      ),
    ]) {
      final network = _QueueNetwork([_page(pageUri, unsigned)]);
      final result = await client(
        network,
      ).signInToday(ForumDailySignInRequest(userId: '42', beforeSend: gate));

      expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
      expect(result.failureOrNull?.code, code);
      expect(
        result.failureOrNull?.diagnosticMessage,
        isNot(contains('secret')),
      );
      expect(network.requests, hasLength(1));
      expect(network.requests.single.uri, pageUri);
    }
  });

  test('gate is not invoked for signed or changed-day preparation', () async {
    var calls = 0;
    Future<ForumDailySignInSendAuthorization> gate(
      ForumDailySignInPreparedAttempt _,
    ) async {
      calls++;
      return ForumDailySignInSendAuthorization.allow;
    }

    for (final request in [
      ForumDailySignInRequest(userId: '42', beforeSend: gate),
      ForumDailySignInRequest(
        userId: '42',
        expectedForumDay: '20300411',
        beforeSend: gate,
      ),
    ]) {
      final network = _QueueNetwork([
        _page(pageUri, request.expectedForumDay == null ? signed : unsigned),
      ]);
      final result = await client(network).signInToday(request);
      expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
      expect(network.requests, hasLength(1));
    }
    expect(calls, 0);
  });

  test('cancellation while gate awaits prevents command GET', () async {
    final cancellation = ForumRequestCancellation();
    final network = _QueueNetwork([_page(pageUri, unsigned)]);

    final result = await client(network).signInToday(
      ForumDailySignInRequest(
        userId: '42',
        cancellation: cancellation,
        beforeSend: (_) async {
          cancellation.cancel();
          return ForumDailySignInSendAuthorization.allow;
        },
      ),
    );

    expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
    expect(result.failureOrNull?.code, 'daily_sign_in_cancelled_before_send');
    expect(network.requests, hasLength(1));
  });

  test(
    'changed forum day after fresh preparation prevents submission',
    () async {
      final network = _QueueNetwork([_page(pageUri, unsigned)]);

      final result = await client(network).signInToday(
        const ForumDailySignInRequest(
          userId: '42',
          expectedForumDay: '20300411',
        ),
      );

      expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
      expect(result.failureOrNull?.code, 'daily_sign_in_forum_day_changed');
      expect(network.requests, hasLength(1));
      expect(network.requests.single.uri, pageUri);
      expect(network.requests.single.followRedirects, isFalse);
    },
  );

  test(
    'bad action, wrong account, and redirected preparation never submit',
    () async {
      final badAction = unsigned.replaceFirst(
        'plugin.php?id=zqlj_sign&amp;sign=fixtureToken0001',
        'https://outside.example.test/plugin.php?id=zqlj_sign&amp;sign=fixtureToken0001',
      );
      for (final response in [
        _page(pageUri, badAction),
        _page(
          pageUri,
          unsigned.replaceFirst("discuz_uid = '42'", "discuz_uid = '43'"),
        ),
        _page(
          Uri.parse('https://forum.example.test/member.php?mod=logging'),
          unsigned,
        ),
      ]) {
        final network = _QueueNetwork([response]);
        final result = await client(
          network,
        ).signInToday(const ForumDailySignInRequest(userId: '42'));
        expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
        expect(network.requests, hasLength(1));
      }
    },
  );

  test(
    'cross-site Location is not followed for status or preparation',
    () async {
      final redirect = ForumTransportSuccess<ForumResponse<Object?>>(
        ForumResponse(
          uri: pageUri,
          statusCode: 302,
          headers: const {
            'location': [
              'https://outside.example.test/plugin.php?id=zqlj_sign',
            ],
          },
          body: unsigned,
        ),
      );
      final readNetwork = _QueueNetwork([redirect]);
      final read = await client(
        readNetwork,
      ).loadDailySignIn(const ForumDailySignInQuery(userId: '42'));
      expect(
        read,
        isA<
          DataReadFailure<
            ForumDailySignInSnapshot,
            ForumDailySignInReadCapabilities
          >
        >(),
      );
      expect(readNetwork.requests, hasLength(1));
      expect(readNetwork.requests.single.followRedirects, isFalse);

      final commandNetwork = _QueueNetwork([redirect]);
      final command = await client(
        commandNetwork,
      ).signInToday(const ForumDailySignInRequest(userId: '42'));
      expect(command, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
      expect(commandNetwork.requests, hasLength(1));
      expect(commandNetwork.requests.single.followRedirects, isFalse);
    },
  );

  test(
    'invalid UID and cancellation before preparation send nothing',
    () async {
      final cancellation = ForumRequestCancellation()..cancel();
      final network = _QueueNetwork([]);
      final forum = client(network);

      expect(
        await forum.signInToday(const ForumDailySignInRequest(userId: '0')),
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
      );
      expect(
        await forum.signInToday(
          ForumDailySignInRequest(userId: '42', cancellation: cancellation),
        ),
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
      );
      expect(network.requests, isEmpty);
    },
  );

  test(
    'missing plugin and login failures do not become unsigned state',
    () async {
      for (final (status, kind) in [
        (404, DataReadFailureKind.unsupported),
        (401, DataReadFailureKind.unauthorized),
      ]) {
        final network = _QueueNetwork([
          ForumTransportError(
            ForumTransportFailure(
              kind: ForumTransportFailureKind.server,
              code: 'untrusted-source-error',
              statusCode: status,
            ),
          ),
        ]);
        final result = await client(
          network,
        ).loadDailySignIn(const ForumDailySignInQuery(userId: '42'));
        expect(result.failureOrNull?.kind, kind);
        expect(result.dataOrNull, isNull);
        expect(
          result.failureOrNull?.diagnosticMessage,
          isNot(contains('untrusted')),
        );
      }
    },
  );

  test('405, redirect, timeout and cancelled post-send stay unknown', () async {
    for (final observation in <ForumTransportResult<ForumResponse<Object?>>>[
      const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.server,
          code: 'raw-sign-token',
          statusCode: 405,
        ),
      ),
      _page(pageUri, '<html>redirect</html>', statusCode: 302),
      const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'raw-sign-token',
        ),
      ),
      const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.cancelled,
          code: 'raw-sign-token',
        ),
      ),
    ]) {
      final network = _QueueNetwork([
        _page(pageUri, unsigned),
        observation,
        _page(pageUri, unsigned),
      ]);
      final result = await client(
        network,
      ).signInToday(const ForumDailySignInRequest(userId: '42'));
      expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
      expect(
        result.failureOrNull?.retryPolicy,
        DataCommandRetryPolicy.explicitOnly,
      );
      expect(
        result.failureOrNull?.diagnosticMessage,
        isNot(contains('raw-sign-token')),
      );
      expect(
        network.requests.where(
          (request) => request.uri.queryParameters.containsKey('sign'),
        ),
        hasLength(1),
      );
    }
  });
}

ForumTransportSuccess<ForumResponse<Object?>> _page(
  Uri uri,
  String body, {
  int statusCode = 200,
}) => ForumTransportSuccess(
  ForumResponse(
    uri: uri,
    statusCode: statusCode,
    headers: const {},
    body: body,
  ),
);

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(this._responses);

  final List<ForumTransportResult<ForumResponse<Object?>>> _responses;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('Unexpected forum request');
    }
    return _responses.removeAt(0);
  }
}
