import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';

DataReadFailure<T, C> dataReadFailureFromApiError<T, C>(ApiError error) {
  return DataReadFailure<T, C>(
    kind: error.code == 'request_cancelled'
        ? DataReadFailureKind.cancelled
        : switch (error.type) {
            ApiErrorType.network => DataReadFailureKind.network,
            ApiErrorType.timeout => DataReadFailureKind.timeout,
            ApiErrorType.unauthorized => DataReadFailureKind.unauthorized,
            ApiErrorType.server => DataReadFailureKind.server,
            ApiErrorType.parse => DataReadFailureKind.parse,
            ApiErrorType.business => DataReadFailureKind.business,
            ApiErrorType.unknown => DataReadFailureKind.unknown,
          },
    code: error.code,
    statusCode: error.statusCode,
    diagnosticMessage: error.message,
  );
}

DataReadResult<T, C> dataReadResultFromApiResult<T, C>(
  ApiResult<T> result, {
  required C capabilities,
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) {
  return switch (result) {
    ApiSuccess<T>(:final data) => DataReadSuccess<T, C>(
      data: data,
      capabilities: capabilities,
      metadata: metadata,
    ),
    ApiFailure<T>(:final error) => dataReadFailureFromApiError<T, C>(error),
  };
}

DataReadFailure<T, C> unsupportedDataReadFailure<T, C>({
  required String code,
  required String diagnosticMessage,
}) {
  return DataReadFailure<T, C>(
    kind: DataReadFailureKind.unsupported,
    code: code,
    diagnosticMessage: diagnosticMessage,
  );
}
