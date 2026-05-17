import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/thread/data/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

class DiscuzThreadFavoriteApiRepository implements ThreadFavoriteRepository {
  DiscuzThreadFavoriteApiRepository({
    required ProfileRepository profileRepository,
    required CookieStore cookieStore,
    Dio? dio,
  })  : _profileRepository = profileRepository,
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
    final endpoint = '${AppConfig.siteBaseUrl}/api/mobile/index.php';

    try {
      final response = await _dio.post<dynamic>(
        endpoint,
        queryParameters: const <String, String>{
          'module': 'favthread',
          'version': '4',
        },
        data: <String, String>{
          'formhash': formhash,
          'id': tid,
          'favoritesubmit': '1',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'referer': '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid&mobile=2',
            'accept': 'application/json, text/plain, */*',
          },
        ),
      );

      final parsed = _parseFavoriteResponse(response.data);
      if (!parsed.success) {
        return ApiFailure<ThreadFavoriteResult>(
          ApiError(
            type: ApiErrorType.business,
            message: parsed.message,
            code: parsed.code,
            raw: response.data,
            statusCode: response.statusCode,
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

  Future<ApiResult<String>> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          return const ApiFailure<String>(
            ApiError(type: ApiErrorType.business, message: 'formhash 为空，无法收藏帖子'),
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
      fallback: ParseUtils.asString(messageNode['messageval'], fallback: '收藏结果未知'),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();
    final alreadyFavorited = _isAlreadyFavorited(loweredCode, loweredMessage);
    final success = alreadyFavorited ||
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
