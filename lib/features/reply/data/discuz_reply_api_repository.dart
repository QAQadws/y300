import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class DiscuzReplyApiRepository implements ReplyRepository {
  DiscuzReplyApiRepository({
    required ProfileRepository profileRepository,
    required CookieStore cookieStore,
    Dio? dio,
  }) : _profileRepository = profileRepository,
       _cookieStore = cookieStore,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookieHeader = await _cookieStore.readCookieHeader(options.uri);
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            options.headers['cookie'] = cookieHeader;
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookie = response.headers.map['set-cookie'] ?? <String>[];
          await _cookieStore.saveFromSetCookie(response.requestOptions.uri, setCookie);
          handler.next(response);
        },
      ),
    );
  }

  final ProfileRepository _profileRepository;
  final CookieStore _cookieStore;
  final Dio _dio;

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    final message = draft.message.trim();
    if (message.isEmpty) {
      return const ApiFailure<ReplySubmissionResult>(
        ApiError(type: ApiErrorType.business, message: '回复内容不能为空'),
      );
    }
    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ReplySubmissionResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;
    final endpoint = '${AppConfig.siteBaseUrl}/api/mobile/index.php';

    try {
      final response = await _dio.post<dynamic>(
        endpoint,
        queryParameters: const <String, String>{
          'module': 'sendreply',
          'version': '4',
        },
        data: <String, String>{
          'formhash': formhash,
          'fid': draft.fid,
          'tid': draft.tid,
          'message': message,
          'replysubmit': 'yes',
          'usesig': draft.useSignature ? '1' : '0',
          if ((draft.repPid ?? '').isNotEmpty) 'reppid': draft.repPid!,
          if ((draft.repPost ?? '').isNotEmpty) 'reppost': draft.repPost!,
          if ((draft.noticeAuthor ?? '').isNotEmpty) 'noticeauthor': draft.noticeAuthor!,
          if ((draft.noticeTrimStr ?? '').isNotEmpty) 'noticetrimstr': draft.noticeTrimStr!,
          if ((draft.noticeAuthorMsg ?? '').isNotEmpty) 'noticeauthormsg': draft.noticeAuthorMsg!,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'referer': '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=${draft.tid}&mobile=2',
            'accept': 'application/json, text/plain, */*',
          },
        ),
      );
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

  Future<ApiResult<String>> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          return const ApiFailure<String>(
            ApiError(type: ApiErrorType.business, message: 'formhash 为空，无法发送回复'),
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
      fallback: ParseUtils.asString(messageNode['messageval'], fallback: '回复结果未知'),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();

    final success = loweredCode.contains('succeed') ||
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
