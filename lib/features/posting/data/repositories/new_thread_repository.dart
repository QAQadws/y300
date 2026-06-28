import 'package:dio/dio.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/posting/data/services/new_thread_remote_data_source.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_response_parser.dart';

abstract class NewThreadRepository {
  Future<ApiResult<NewThreadSubmissionResult>> submit({
    required NewThreadDraftPayload payload,
  });
}

/// Discuz 站点上的实现。
///
/// 仅负责"业务字段 → form 提交 → 响应解析 → ApiResult 错误映射"，
/// 校验（标题/正文非空、必选分类）由 controller 在 preflight 完成。
class DiscuzNewThreadRepository implements NewThreadRepository {
  DiscuzNewThreadRepository({
    required NewThreadRemoteDataSource remoteDataSource,
    NewThreadResponseParser parser = const NewThreadResponseParser(),
  })  : _remoteDataSource = remoteDataSource,
        _parser = parser;

  final NewThreadRemoteDataSource _remoteDataSource;
  final NewThreadResponseParser _parser;

  @override
  Future<ApiResult<NewThreadSubmissionResult>> submit({
    required NewThreadDraftPayload payload,
  }) async {
    final form = NewThreadSubmitForm(payload: payload);
    try {
      final response = await _remoteDataSource.submit(form);
      final parsed = _parser.parse(response.data);
      if (!parsed.success) {
        return ApiFailure<NewThreadSubmissionResult>(
          ApiError(
            type: ApiErrorType.business,
            code: parsed.code,
            message: parsed.message,
            raw: response.data,
            statusCode: response.statusCode,
          ),
        );
      }
      return ApiSuccess<NewThreadSubmissionResult>(parsed.result!);
    } on DioException catch (error) {
      return ApiFailure<NewThreadSubmissionResult>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '网络异常',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure<NewThreadSubmissionResult>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '发帖失败：$error',
          raw: error,
        ),
      );
    }
  }

  ApiErrorType _mapDioErrorType(DioException error) {
    final statusCode = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiErrorType.timeout;
    }
    if (statusCode == 401 || statusCode == 403) {
      return ApiErrorType.unauthorized;
    }
    if (statusCode != null && statusCode >= 500) {
      return ApiErrorType.server;
    }
    return ApiErrorType.network;
  }
}
