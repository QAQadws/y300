import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';
import 'package:y300/features/reply/data/services/discuz_reply_remote_data_source.dart';
import 'package:y300/features/reply/data/services/reply_form_preparation_data_source.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_draft_validator.dart';

class DiscuzReplyApiRepository implements ReplyRepository {
  DiscuzReplyApiRepository({
    required ProfileRepository profileRepository,
    required CookieStore cookieStore,
    YamiboHttpGateway? gateway,
    Dio? dio,
    DiscuzReplyRemoteDataSource? remoteDataSource,
    ReplyFormPreparationDataSource? preparationDataSource,
    ReplyDraftValidator validator = const ReplyDraftValidator(),
  }) : _profileRepository = profileRepository,
       _remoteDataSource =
           remoteDataSource ??
           DiscuzReplyDioRemoteDataSource(
             gateway:
                 gateway ??
                 YamiboHttpGateway(
                   cookieStore: cookieStore,
                   logger: Logger(level: Level.off),
                   dio: dio,
                   enableLog: false,
                 ),
           ),
       _preparationDataSource =
           preparationDataSource ??
           DiscuzReplyFormPreparationDataSource(
             gateway:
                 gateway ??
                 YamiboHttpGateway(
                   cookieStore: cookieStore,
                   logger: Logger(level: Level.off),
                   dio: dio,
                   enableLog: false,
                 ),
           ),
       _validator = validator;

  final ProfileRepository _profileRepository;
  final DiscuzReplyRemoteDataSource _remoteDataSource;
  final ReplyFormPreparationDataSource _preparationDataSource;
  final ReplyDraftValidator _validator;

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    final message = draft.message.trim();
    final validation = _validator.validate(draft);
    if (!validation.isValid) {
      return ApiFailure<ReplySubmissionResult>(
        ApiError(
          type: ApiErrorType.business,
          message: validation.message ?? '回复内容不能为空',
        ),
      );
    }
    final formhashResult = await _resolveFormhash(draft.formHash);
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ReplySubmissionResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;
    final payload = ReplySubmitPayload.fromDraft(
      draft: draft,
      formHash: formhash,
      message: message,
    );

    try {
      final response = await _remoteDataSource.sendReply(payload);
      final parsed = _parseReplyResponse(response.data);
      if (!parsed.success) {
        return ApiFailure<ReplySubmissionResult>(
          ApiError(
            type: ApiErrorType.business,
            message: parsed.message,
            code: parsed.code,
            raw: response.data,
            statusCode: response.statusCode,
          ),
        );
      }
      return ApiSuccess<ReplySubmissionResult>(
        ReplySubmissionResult(message: parsed.message),
      );
    } on DioException catch (error) {
      return ApiFailure<ReplySubmissionResult>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '网络异常',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure<ReplySubmissionResult>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '发送回复失败：$error',
          raw: error,
        ),
      );
    }
  }

  @override
  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  }) async {
    try {
      final preparation = await _preparationDataSource.fetchReplyPreparation(
        replyFormUri,
      );
      return ApiSuccess<ReplyPreparation>(preparation);
    } on DioException catch (error) {
      return ApiFailure<ReplyPreparation>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '获取楼层回复表单失败',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } on ReplyFormParseException catch (error) {
      return ApiFailure<ReplyPreparation>(
        ApiError(type: ApiErrorType.parse, message: error.message),
      );
    } catch (error) {
      return ApiFailure<ReplyPreparation>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '准备楼层回复失败：$error',
          raw: error,
        ),
      );
    }
  }

  Future<ApiResult<String>> _resolveFormhash(String? preparedFormhash) async {
    final normalized = preparedFormhash?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return ApiSuccess<String>(normalized);
    }
    return _loadFormhash();
  }

  Future<ApiResult<String>> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          return const ApiFailure<String>(
            ApiError(
              type: ApiErrorType.business,
              message: 'formhash 为空，无法发送回复',
            ),
          );
        }
        return ApiSuccess<String>(formhash);
      },
      failure: (error) => ApiFailure<String>(
        ApiError(
          type: error.type,
          message: '获取 formhash 失败：${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      ),
    );
  }

  _ReplyResponseParseResult _parseReplyResponse(dynamic data) {
    final root = _asJsonMap(data);
    final messageNode = ParseUtils.asMap(root['Message']);
    final message = ParseUtils.asString(
      messageNode['messagestr'],
      fallback: ParseUtils.asString(
        messageNode['messageval'],
        fallback: '回复结果未知',
      ),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();

    final success =
        loweredCode.contains('succeed') ||
        loweredCode.contains('success') ||
        loweredMessage.contains('成功');
    return _ReplyResponseParseResult(
      success: success,
      message: message,
      code: code,
    );
  }

  JsonMap _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      final decoded = jsonDecode(data);
      return ParseUtils.asMap(decoded);
    }
    return <String, dynamic>{};
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

class _ReplyResponseParseResult {
  const _ReplyResponseParseResult({
    required this.success,
    required this.message,
    required this.code,
  });

  final bool success;
  final String message;
  final String code;
}
