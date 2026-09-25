import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_daily_sign_in_command_evidence.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  // These are synthetic outcomes, not observed Yamibo sign-in responses.
  final syntheticResponses =
      <({String name, int statusCode, String body, String uri})>[
        (
          name: 'invalid sign falling through to ordinary homepage',
          statusCode: 200,
          body: '<html><div id="nv_forum">Forum home</div></html>',
          uri: 'https://bbs.yamibo.com/forum.php',
        ),
        (
          name: 'unverified redirect',
          statusCode: 302,
          body: '<html><title>Redirecting</title></html>',
          uri: 'https://bbs.yamibo.com/member.php?mod=logging',
        ),
        (
          name: 'WAF challenge page',
          statusCode: 200,
          body: '<html><title>Security challenge</title></html>',
          uri: 'https://bbs.yamibo.com/plugin.php?id=zqlj_sign',
        ),
        (
          name: 'apparent success showmessage without fresh confirmation',
          statusCode: 200,
          body: '<div id="messagetext">Sign-in succeeded</div>',
          uri: 'https://bbs.yamibo.com/plugin.php?id=zqlj_sign',
        ),
      ];

  for (final scenario in syntheticResponses) {
    test('${scenario.name} remains outcome unknown', () {
      final result = unconfirmedDailySignInPostSend(
        ForumTransportSuccess<ForumResponse<String>>(
          ForumResponse<String>(
            uri: Uri.parse(scenario.uri),
            statusCode: scenario.statusCode,
            headers: const {},
            body: scenario.body,
          ),
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
      expect(result.receiptOrNull, isNull);
      expect(result.failure.retryPolicy, DataCommandRetryPolicy.explicitOnly);
      expect(
        result.failure.diagnosticMessage,
        'daily_sign_in_response_unconfirmed',
      );
      expect(result.failure.diagnosticMessage, isNot(contains(scenario.body)));
      expect(result.failure.diagnosticMessage, isNot(contains(scenario.uri)));
    });
  }

  test('timeout and disconnect after send remain outcome unknown', () {
    for (final (kind, expected) in [
      (ForumTransportFailureKind.timeout, DataCommandFailureKind.timeout),
      (ForumTransportFailureKind.network, DataCommandFailureKind.network),
    ]) {
      final result = unconfirmedDailySignInPostSend(
        ForumTransportError<ForumResponse<String>>(
          ForumTransportFailure(
            kind: kind,
            code: 'synthetic-secret-sign-value',
          ),
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
      expect(result.failure.kind, expected);
      expect(result.failure.retryPolicy, DataCommandRetryPolicy.explicitOnly);
      expect(
        result.failure.diagnosticMessage,
        'daily_sign_in_transport_unconfirmed',
      );
      expect(
        result.failure.diagnosticMessage,
        isNot(contains('synthetic-secret')),
      );
    }
  });

  test(
    'HTTP 405 WAF outcome is inconclusive and never retried automatically',
    () {
      final result = unconfirmedDailySignInPostSend(
        ForumTransportError<ForumResponse<String>>(
          const ForumTransportFailure(
            kind: ForumTransportFailureKind.server,
            code: 'untrusted-raw-challenge',
            statusCode: 405,
          ),
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>());
      expect(result.failure.kind, DataCommandFailureKind.securityChallenge);
      expect(result.failure.statusCode, 405);
      expect(result.failure.retryPolicy, DataCommandRetryPolicy.explicitOnly);
      expect(
        result.failure.diagnosticMessage,
        isNot(contains('untrusted-raw')),
      );
    },
  );
}
