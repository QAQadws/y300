import '../contracts/data_read_contract.dart';

/// Stable transport failure categories mapped into read failures by adapters.
enum ForumTransportFailureKind {
  network,
  timeout,
  server,
  unauthorized,
  parse,
  business,
  cancelled,
  unknown,
}

/// Safe transport failure that excludes response bodies and secrets.
final class ForumTransportFailure {
  /// Creates a transport failure.
  const ForumTransportFailure({
    required this.kind,
    required this.code,
    this.statusCode,
  });

  /// Stable failure category.
  final ForumTransportFailureKind kind;

  /// Protocol-safe diagnostic code.
  final String code;

  /// Optional HTTP status code.
  final int? statusCode;
}

/// Transport result before source-specific parsing and capability mapping.
sealed class ForumTransportResult<T> {
  const ForumTransportResult();
}

/// Successful transport response.
final class ForumTransportSuccess<T> extends ForumTransportResult<T> {
  /// Creates a successful transport result.
  const ForumTransportSuccess(this.response);

  /// Typed response value.
  final T response;
}

/// Failed transport response.
final class ForumTransportError<T> extends ForumTransportResult<T> {
  /// Creates a failed transport result.
  const ForumTransportError(this.failure);

  /// Safe transport failure.
  final ForumTransportFailure failure;
}

/// Maps a transport failure category to its source-neutral read equivalent.
DataReadFailureKind toReadFailureKind(ForumTransportFailureKind kind) =>
    switch (kind) {
      ForumTransportFailureKind.network => DataReadFailureKind.network,
      ForumTransportFailureKind.timeout => DataReadFailureKind.timeout,
      ForumTransportFailureKind.server => DataReadFailureKind.server,
      ForumTransportFailureKind.unauthorized =>
        DataReadFailureKind.unauthorized,
      ForumTransportFailureKind.parse => DataReadFailureKind.parse,
      ForumTransportFailureKind.business => DataReadFailureKind.business,
      ForumTransportFailureKind.cancelled => DataReadFailureKind.cancelled,
      ForumTransportFailureKind.unknown => DataReadFailureKind.unknown,
    };
