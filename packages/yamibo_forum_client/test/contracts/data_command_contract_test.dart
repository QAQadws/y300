import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  test('command outcomes expose only confirmed receipts or safe failures', () {
    const failure = DataCommandFailure(
      kind: DataCommandFailureKind.validation,
      retryPolicy: DataCommandRetryPolicy.afterInputChange,
      code: 'fixture_validation',
      diagnosticMessage: 'fixture_validation',
    );
    const applied = DataCommandApplied<String>('receipt');
    const results = <DataCommandResult<String>>[
      applied,
      DataCommandRejected<String>(failure),
      DataCommandNotSent<String>(failure),
      DataCommandOutcomeUnknown<String>(failure),
      DataCommandUnsupported<String>(),
    ];

    expect(applied.receiptOrNull, 'receipt');
    expect(applied.failureOrNull, isNull);
    for (final result in results.skip(1)) {
      expect(result.receiptOrNull, isNull);
      expect(result.failureOrNull, isNotNull);
    }
  });

  test('safe failure has no payload, credentials, or transport raw fields', () {
    const failure = DataCommandFailure(
      kind: DataCommandFailureKind.timeout,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: 'fixture_timeout',
      diagnosticMessage: 'fixture_timeout',
    );

    expect(failure.toString(), isNot(contains('password')));
    expect(failure.toString(), isNot(contains('cookie')));
    expect(failure.toString(), isNot(contains('formhash')));
    expect(failure.toString(), isNot(contains('raw')));
  });
}
