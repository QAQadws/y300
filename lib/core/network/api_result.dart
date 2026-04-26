enum ApiErrorType {
  network,
  timeout,
  unauthorized,
  server,
  parse,
  business,
  unknown,
}

/// 网络层统一错误对象
class ApiError {
  const ApiError({
    required this.type,
    required this.message,
    this.code,
    this.statusCode,
    this.raw,
  });

  final ApiErrorType type;
  final String message;
  final String? code;
  final int? statusCode;
  final dynamic raw;
}

/// 统一结果容器：上层只处理 success/failure 两种路径
sealed class ApiResult<T> {
  const ApiResult();

  bool get isSuccess => this is ApiSuccess<T>;

  bool get isFailure => this is ApiFailure<T>;

  T? get dataOrNull {
    if (this case ApiSuccess<T>(:final data)) {
      return data;
    }
    return null;
  }

  ApiError? get errorOrNull {
    if (this case ApiFailure<T>(:final error)) {
      return error;
    }
    return null;
  }

  R when<R>({
    required R Function(T data) success,
    required R Function(ApiError error) failure,
  }) {
    if (this case ApiSuccess<T>(:final data)) {
      return success(data);
    }
    if (this case ApiFailure<T>(:final error)) {
      return failure(error);
    }
    throw StateError('Unexpected ApiResult state');
  }
}

class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);

  final T data;
}

class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(this.error);

  final ApiError error;
}
