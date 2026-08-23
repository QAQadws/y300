import '../contracts/data_read_contract.dart';

enum ForumTransportFailureKind {
  network,
  timeout,
  server,
  unauthorized,
  business,
  cancelled,
  unknown,
}

final class ForumTransportFailure {
  const ForumTransportFailure({
    required this.kind,
    required this.code,
    this.statusCode,
  });
  final ForumTransportFailureKind kind;
  final String code;
  final int? statusCode;
}

sealed class ForumTransportResult<T> {
  const ForumTransportResult();
}

final class ForumTransportSuccess<T> extends ForumTransportResult<T> {
  const ForumTransportSuccess(this.response);
  final T response;
}

final class ForumTransportError<T> extends ForumTransportResult<T> {
  const ForumTransportError(this.failure);
  final ForumTransportFailure failure;
}

DataReadFailureKind toReadFailureKind(ForumTransportFailureKind kind) =>
    switch (kind) {
      ForumTransportFailureKind.network => DataReadFailureKind.network,
      ForumTransportFailureKind.timeout => DataReadFailureKind.timeout,
      ForumTransportFailureKind.server => DataReadFailureKind.server,
      ForumTransportFailureKind.unauthorized =>
        DataReadFailureKind.unauthorized,
      ForumTransportFailureKind.business => DataReadFailureKind.business,
      ForumTransportFailureKind.cancelled => DataReadFailureKind.cancelled,
      ForumTransportFailureKind.unknown => DataReadFailureKind.unknown,
    };
