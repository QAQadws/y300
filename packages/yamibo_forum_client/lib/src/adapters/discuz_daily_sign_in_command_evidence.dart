import '../contracts/data_command_contract.dart';
import '../contracts/forum_daily_sign_in.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';

/// Keeps a sent sign-in command inconclusive until a verified postcondition is
/// available. Untrusted HTML, URLs, and transport diagnostics are never copied
/// into failures.
DataCommandOutcomeUnknown<ForumDailySignInReceipt>
unconfirmedDailySignInPostSend(
  ForumTransportResult<ForumResponse<String>> observation,
) {
  final (kind, code, statusCode) = switch (observation) {
    ForumTransportSuccess<ForumResponse<String>>(:final response) =>
      response.statusCode == 405
          ? (
              DataCommandFailureKind.securityChallenge,
              'daily_sign_in_security_challenge',
              response.statusCode,
            )
          : (
              DataCommandFailureKind.parse,
              'daily_sign_in_response_unconfirmed',
              response.statusCode,
            ),
    ForumTransportError<ForumResponse<String>>(:final failure) => (
      failure.statusCode == 405
          ? DataCommandFailureKind.securityChallenge
          : switch (failure.kind) {
              ForumTransportFailureKind.network =>
                DataCommandFailureKind.network,
              ForumTransportFailureKind.timeout =>
                DataCommandFailureKind.timeout,
              ForumTransportFailureKind.server => DataCommandFailureKind.server,
              ForumTransportFailureKind.unauthorized =>
                DataCommandFailureKind.unauthenticated,
              ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
              ForumTransportFailureKind.business ||
              ForumTransportFailureKind.unknown =>
                DataCommandFailureKind.unknown,
              ForumTransportFailureKind.cancelled =>
                DataCommandFailureKind.cancelled,
            },
      'daily_sign_in_transport_unconfirmed',
      failure.statusCode,
    ),
  };

  return DataCommandOutcomeUnknown<ForumDailySignInReceipt>(
    DataCommandFailure(
      kind: kind,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: code,
      statusCode: statusCode,
      diagnosticMessage: code,
    ),
  );
}
