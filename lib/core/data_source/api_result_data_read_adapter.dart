import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';

DataReadFailure<T, C> dataReadFailureFromApiError<T, C>(ApiError error) {
  return DataReadFailure<T, C>(
    kind: switch (error.type) {
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

/// Transitional bridge for legacy feature services that have not yet adopted
/// source capabilities. New repository contracts must return DataReadResult.
ApiResult<T> apiResultFromDataRead<T, C>(DataReadResult<T, C> result) {
  return switch (result) {
    DataReadSuccess<T, C>(:final data) => ApiSuccess<T>(data),
    DataReadFailure<T, C>(
      :final kind,
      :final code,
      :final statusCode,
      :final diagnosticMessage,
    ) => ApiFailure<T>(
      ApiError(
        type: switch (kind) {
          DataReadFailureKind.network => ApiErrorType.network,
          DataReadFailureKind.timeout => ApiErrorType.timeout,
          DataReadFailureKind.unauthorized => ApiErrorType.unauthorized,
          DataReadFailureKind.server => ApiErrorType.server,
          DataReadFailureKind.parse => ApiErrorType.parse,
          DataReadFailureKind.business ||
          DataReadFailureKind.unsupported => ApiErrorType.business,
          DataReadFailureKind.cancelled ||
          DataReadFailureKind.unknown => ApiErrorType.unknown,
        },
        message: diagnosticMessage,
        code: code,
        statusCode: statusCode,
      ),
    ),
  };
}
