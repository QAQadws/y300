import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/utils/parse_utils.dart';

/// 统一网络入口：负责请求基础能力，不承担具体业务字段解析
class ApiClient {
  ApiClient({
    required CookieStore cookieStore,
    required Logger logger,
    Dio? dio,
    bool enableLog = true,
  }) : _cookieStore = cookieStore,
       _logger = logger,
       _enableLog = enableLog,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.apiBaseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 统一注入公共参数，调用层可覆盖 version
          options.queryParameters = {
            ...options.queryParameters,
            'version':
                options.queryParameters['version'] ??
                AppConfig.defaultApiVersion,
          };

          // 自动补齐本地会话 Cookie
          final cookieHeader = await _cookieStore.readCookieHeader(options.uri);
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            options.headers['cookie'] = cookieHeader;
          }

          handler.next(options);
        },
        onResponse: (response, handler) async {
          // 自动接收并持久化服务端下发的 Cookie
          final setCookie = response.headers.map['set-cookie'] ?? <String>[];
          await _cookieStore.saveFromSetCookie(
            response.requestOptions.uri,
            setCookie,
          );

          if (_enableLog) {
            _logger.i(
              '[HTTP ${response.statusCode}] ${response.requestOptions.uri}\\n'
              'body=${response.data}',
            );
          }

          handler.next(response);
        },
      ),
    );
  }

  final Dio _dio;
  final CookieStore _cookieStore;
  final Logger _logger;
  final bool _enableLog;

  Future<void> clearSession() async {
    await _cookieStore.clear();
  }

  /// 返回 Discuz 原始通用结构，供上层按需二次解析
  Future<ApiResult<DiscuzResponse>> getDiscuz({
    required String module,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '',
        queryParameters: {'module': module, ...?queryParameters},
        cancelToken: cancelToken,
      );

      final json = _toJsonMap(response.data);
      final discuzResponse = DiscuzResponse.fromJson(json);
      if (discuzResponse.hasBusinessError) {
        return ApiFailure(
          ApiError(
            type: ApiErrorType.business,
            code: discuzResponse.businessCode,
            message: discuzResponse.businessMessage,
            raw: json,
            statusCode: response.statusCode,
          ),
        );
      }

      return ApiSuccess(discuzResponse);
    } on DioException catch (error) {
      return ApiFailure(_mapDioError(error));
    } on FormatException catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '响应格式错误: ${error.message}',
          raw: error.source,
        ),
      );
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.unknown,
          message: '未知错误: $error',
          raw: error,
        ),
      );
    }
  }

  /// 模板化解析：网络成功后把 variables 转成具体业务模型
  Future<ApiResult<T>> getParsed<T>({
    required String module,
    required T Function(DiscuzResponse response) parser,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final result = await getDiscuz(
      module: module,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );

    return result.when(
      success: (response) {
        try {
          return ApiSuccess<T>(parser(response));
        } catch (error) {
          return ApiFailure<T>(
            ApiError(
              type: ApiErrorType.parse,
              message: '业务解析失败: $error',
              raw: response.variables,
            ),
          );
        }
      },
      failure: ApiFailure.new,
    );
  }

  JsonMap _toJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, dynamic value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('响应不是JSON对象', null);
    }
    throw FormatException('无法解析响应类型: ${data.runtimeType}', data);
  }

  ApiError _mapDioError(DioException error) {
    // 统一映射为可消费的错误类型，避免上层耦合 Dio 细节。
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiError(
        type: ApiErrorType.timeout,
        message: '请求超时，请稍后重试',
        statusCode: statusCode,
        raw: responseData,
      );
    }

    if (statusCode == 401 || statusCode == 403) {
      return ApiError(
        type: ApiErrorType.unauthorized,
        message: '登录态失效，请重新登录',
        statusCode: statusCode,
        raw: responseData,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        type: ApiErrorType.server,
        message: '服务端异常($statusCode)',
        statusCode: statusCode,
        raw: responseData,
      );
    }

    if (error.type == DioExceptionType.badResponse) {
      return ApiError(
        type: ApiErrorType.server,
        message: '接口请求失败($statusCode)',
        statusCode: statusCode,
        raw: responseData,
      );
    }

    return ApiError(
      type: ApiErrorType.network,
      message: '网络异常: ${error.message ?? 'unknown'}',
      statusCode: statusCode,
      raw: responseData,
    );
  }
}
