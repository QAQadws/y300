import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

class DiscuzThreadFavoriteApiRepository implements ThreadFavoriteRepository {
  DiscuzThreadFavoriteApiRepository({
    required ProfileRepository profileRepository,
    required YamiboHttpGateway gateway,
  }) : _profileRepository = profileRepository,
       _gateway = gateway;

  final ProfileRepository _profileRepository;
  final YamiboHttpGateway _gateway;

  @override
  Future<ApiResult<ThreadFavoriteResult>> favoriteThread({
    required ThreadFavoriteRequest request,
  }) async {
    final tid = request.tid.trim();
    if (tid.isEmpty) {
      return const ApiFailure<ThreadFavoriteResult>(
        ApiError(type: ApiErrorType.business, message: '帖子 tid 不能为空'),
      );
    }

    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ThreadFavoriteResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;
    final endpoint = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: const <String, String>{
        'module': 'favthread',
        'version': '4',
      },
    );

    try {
      final response = await _gateway.postForm(
        endpoint,
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.api,
          operation: 'thread.favorite.add',
          module: 'favthread',
        ),
        data: <String, String>{
          'formhash': formhash,
          'id': tid,
          'favoritesubmit': '1',
        },
        headers: <String, String>{
          'referer':
              '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid&mobile=2',
          'accept': 'application/json, text/plain, */*',
        },
      );
      if (response case ApiFailure(:final error)) {
        throw _toDioException(error, endpoint);
      }
      final data = response.dataOrNull;

      final parsed = _parseFavoriteResponse(data?.body);
      if (!parsed.success) {
        return ApiFailure<ThreadFavoriteResult>(
          ApiError(
            type: ApiErrorType.business,
            message: parsed.message,
            code: parsed.code,
            raw: data?.body,
            statusCode: data?.statusCode,
          ),
        );
      }
      return ApiSuccess<ThreadFavoriteResult>(
        ThreadFavoriteResult(
          message: parsed.message,
          alreadyFavorited: parsed.alreadyFavorited,
        ),
      );
    } on DioException catch (error) {
      return ApiFailure<ThreadFavoriteResult>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '网络异常',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure<ThreadFavoriteResult>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '收藏帖子失败：$error',
          raw: error,
        ),
      );
    }
  }

  @override
  Future<ApiResult<ThreadUnfavoriteResult>> unfavoriteThread({
    required ThreadUnfavoriteRequest request,
  }) async {
    final tid = request.tid.trim();
    if (tid.isEmpty) {
      return const ApiFailure<ThreadUnfavoriteResult>(
        ApiError(type: ApiErrorType.business, message: '帖子 tid 不能为空'),
      );
    }

    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ThreadUnfavoriteResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;
    final endpoint = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: <String, String>{
        'module': 'favthread',
        'version': '4',
        'op': 'delete',
        'type': 'thread',
        'id': tid,
      },
    );

    try {
      // 删除以 tid 为键：`op=delete&type=thread&id=<tid>`，与添加收藏的
      // `favoritesubmit` 路径同构，只是把提交字段换成 `deletesubmit`。
      final response = await _gateway.postForm(
        endpoint,
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.api,
          operation: 'thread.favorite.delete',
          module: 'favthread',
        ),
        data: <String, String>{'formhash': formhash, 'deletesubmit': 'true'},
        headers: <String, String>{
          'referer':
              '${AppConfig.siteBaseUrl}/home.php?mod=spacecp&ac=favorite&mobile=2',
          'accept': 'application/json, text/plain, */*',
        },
      );
      if (response case ApiFailure(:final error)) {
        throw _toDioException(error, endpoint);
      }
      final data = response.dataOrNull;

      final parsed = _parseUnfavoriteResponse(data?.body);
      if (!parsed.success) {
        return ApiFailure<ThreadUnfavoriteResult>(
          ApiError(
            type: ApiErrorType.business,
            message: parsed.message,
            code: parsed.code,
            raw: data?.body,
            statusCode: data?.statusCode,
          ),
        );
      }
      return ApiSuccess<ThreadUnfavoriteResult>(
        ThreadUnfavoriteResult(
          message: parsed.message,
          alreadyRemoved: parsed.alreadyRemoved,
        ),
      );
    } on DioException catch (error) {
      return ApiFailure<ThreadUnfavoriteResult>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '网络异常',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure<ThreadUnfavoriteResult>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '取消收藏失败：$error',
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
            ApiError(
              type: ApiErrorType.business,
              message: 'formhash 为空，无法收藏帖子',
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

  _ThreadFavoriteResponseParseResult _parseFavoriteResponse(dynamic data) {
    final root = _asJsonMap(data);
    final messageNode = ParseUtils.asMap(root['Message']);
    final message = ParseUtils.asString(
      messageNode['messagestr'],
      fallback: ParseUtils.asString(
        messageNode['messageval'],
        fallback: '收藏结果未知',
      ),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();
    final alreadyFavorited = _isAlreadyFavorited(loweredCode, loweredMessage);
    final success =
        alreadyFavorited ||
        loweredCode.contains('succeed') ||
        loweredCode.contains('success') ||
        loweredCode == 'favorite_do_success' ||
        loweredMessage.contains('成功');
    return _ThreadFavoriteResponseParseResult(
      success: success,
      alreadyFavorited: alreadyFavorited,
      message: message,
      code: code,
    );
  }

  bool _isAlreadyFavorited(String loweredCode, String loweredMessage) {
    return loweredCode.contains('favorite_repeat') ||
        loweredCode.contains('favorite_already') ||
        loweredCode.contains('favorite_exists') ||
        loweredCode.contains('already') ||
        loweredCode.contains('exist') ||
        loweredMessage.contains('已收藏') ||
        loweredMessage.contains('已经收藏') ||
        loweredMessage.contains('收藏过');
  }

  _ThreadUnfavoriteResponseParseResult _parseUnfavoriteResponse(dynamic data) {
    final root = _asJsonMap(data);
    final messageNode = ParseUtils.asMap(root['Message']);
    final message = ParseUtils.asString(
      messageNode['messagestr'],
      fallback: ParseUtils.asString(
        messageNode['messageval'],
        fallback: '取消收藏结果未知',
      ),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();
    // 删除一个本就不存在的收藏视为幂等成功：上层逐个 tid 取消整部作品时，
    // 历史残留 / 重复点击都不该当成失败。
    final alreadyRemoved = _isAlreadyUnfavorited(loweredCode, loweredMessage);
    final success =
        alreadyRemoved ||
        loweredCode.contains('succeed') ||
        loweredCode.contains('success') ||
        loweredCode == 'do_success' ||
        loweredMessage.contains('成功');
    return _ThreadUnfavoriteResponseParseResult(
      success: success,
      alreadyRemoved: alreadyRemoved,
      message: message,
      code: code,
    );
  }

  bool _isAlreadyUnfavorited(String loweredCode, String loweredMessage) {
    return loweredCode.contains('favorite_does_not_exist') ||
        loweredCode.contains('not_exist') ||
        loweredCode.contains('noexist') ||
        loweredCode.contains('notfound') ||
        loweredMessage.contains('未收藏') ||
        loweredMessage.contains('不存在') ||
        loweredMessage.contains('没有收藏');
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

  DioException _toDioException(ApiError error, Uri endpoint) {
    final requestOptions = RequestOptions(path: endpoint.toString());
    return DioException(
      requestOptions: requestOptions,
      response: Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: error.statusCode,
        data: error.raw,
      ),
      message: error.message,
    );
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

class _ThreadFavoriteResponseParseResult {
  const _ThreadFavoriteResponseParseResult({
    required this.success,
    required this.alreadyFavorited,
    required this.message,
    required this.code,
  });

  final bool success;
  final bool alreadyFavorited;
  final String message;
  final String code;
}

class _ThreadUnfavoriteResponseParseResult {
  const _ThreadUnfavoriteResponseParseResult({
    required this.success,
    required this.alreadyRemoved,
    required this.message,
    required this.code,
  });

  final bool success;
  final bool alreadyRemoved;
  final String message;
  final String code;
}
