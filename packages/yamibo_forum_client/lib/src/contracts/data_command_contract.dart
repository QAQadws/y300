/// Source-neutral command outcomes and retry guidance.
library;

/// Stable failure categories for a command that can have side effects.
enum DataCommandFailureKind {
  /// The command input failed validation locally or at the remote endpoint.
  ///
  /// The surrounding result type distinguishes a local `notSent` validation
  /// failure from a server-confirmed `rejected` validation failure.
  validation,

  /// The current session is explicitly unauthenticated.
  unauthenticated,

  /// The authenticated user is not allowed to perform the command.
  permissionDenied,

  /// The server rejected an expired or invalid formhash.
  staleFormhash,

  /// The transport failed before a conclusive response was available.
  network,

  /// The command timed out.
  timeout,

  /// The server returned a non-business failure.
  server,

  /// The response could not be safely interpreted.
  parse,

  /// A managed-site security challenge could not be completed.
  securityChallenge,

  /// The caller cancelled the command.
  cancelled,

  /// The configured source cannot perform this command.
  unsupported,

  /// No more precise safe category is available.
  unknown,
}

/// Guidance for the Host before explicitly retrying a command.
enum DataCommandRetryPolicy {
  /// Retrying the same command is not useful or safe.
  never,

  /// Retry only after an explicit user or Host action.
  explicitOnly,

  /// Retry only after the user changes submitted input.
  afterInputChange,

  /// Retry only after refreshing the authenticated session/formhash.
  afterSessionRefresh,
}

/// Safe failure details shared by non-successful command outcomes.
final class DataCommandFailure {
  /// Creates a failure that deliberately excludes response payloads/secrets.
  const DataCommandFailure({
    required this.kind,
    required this.retryPolicy,
    required this.diagnosticMessage,
    this.code,
    this.statusCode,
  });

  /// Stable failure category.
  final DataCommandFailureKind kind;

  /// Whether and when an explicit retry is appropriate.
  final DataCommandRetryPolicy retryPolicy;

  /// Optional protocol-safe diagnostic code.
  final String? code;

  /// Optional HTTP status associated with the failure.
  final int? statusCode;

  /// Safe diagnostic text that must not contain credentials or response data.
  final String diagnosticMessage;
}

/// Result envelope for a command that may have server-side effects.
sealed class DataCommandResult<T> {
  const DataCommandResult();

  /// Applied receipt, or `null` when the command was not confirmed applied.
  T? get receiptOrNull => switch (this) {
    DataCommandApplied<T>(:final receipt) => receipt,
    _ => null,
  };

  /// Safe failure details, or `null` for an applied command.
  DataCommandFailure? get failureOrNull => switch (this) {
    DataCommandApplied<T>() => null,
    DataCommandRejected<T>(:final failure) ||
    DataCommandNotSent<T>(:final failure) ||
    DataCommandOutcomeUnknown<T>(:final failure) ||
    DataCommandUnsupported<T>(:final failure) => failure,
  };
}

/// The server effect and its postcondition were both confirmed.
final class DataCommandApplied<T> extends DataCommandResult<T> {
  /// Creates an applied command result.
  const DataCommandApplied(this.receipt);

  /// Source-neutral proof returned to the caller.
  final T receipt;
}

/// The server explicitly rejected the command without applying it.
final class DataCommandRejected<T> extends DataCommandResult<T> {
  /// Creates an explicitly rejected command result.
  const DataCommandRejected(this.failure);

  /// Safe rejection details.
  final DataCommandFailure failure;
}

/// The command was rejected locally before any request was sent.
final class DataCommandNotSent<T> extends DataCommandResult<T> {
  /// Creates a locally rejected command result.
  const DataCommandNotSent(this.failure);

  /// Safe validation/session details.
  final DataCommandFailure failure;
}

/// A request was sent but its final server-side effect cannot be proved.
final class DataCommandOutcomeUnknown<T> extends DataCommandResult<T> {
  /// Creates an inconclusive command result.
  const DataCommandOutcomeUnknown(this.failure);

  /// Safe diagnostic details; callers must not assume rollback.
  final DataCommandFailure failure;
}

/// The selected source does not implement this command.
final class DataCommandUnsupported<T> extends DataCommandResult<T> {
  /// Creates an unsupported command result.
  const DataCommandUnsupported([
    this.failure = const DataCommandFailure(
      kind: DataCommandFailureKind.unsupported,
      retryPolicy: DataCommandRetryPolicy.never,
      code: 'command_not_installed',
      diagnosticMessage: 'command_not_installed',
    ),
  ]);

  /// Safe unsupported details.
  final DataCommandFailure failure;
}
