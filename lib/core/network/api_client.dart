import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/network/network_diagnostic_recorder.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';

/// Backward-compatible API facade for existing repositories.
///
/// N-4 moves Discuz mobile API transport into [YamiboApiClient] while keeping
/// this class as the stable adapter used by feature repositories.
class ApiClient {
  ApiClient({
    required CookieStore cookieStore,
    required Logger logger,
    NetworkDiagnosticRecorder? diagnosticRecorder,
    YamiboSessionStore? sessionStore,
    YamiboSessionExtractor? sessionExtractor,
    Dio? dio,
    bool enableLog = true,
    YamiboApiClient? yamiboApiClient,
  }) : _cookieStore = cookieStore,
       _sessionStore = sessionStore,
       _yamiboApiClient =
           yamiboApiClient ??
           YamiboApiClient(
             gateway: YamiboHttpGateway(
               cookieStore: cookieStore,
               logger: logger,
               diagnosticRecorder: diagnosticRecorder,
               sessionStore: sessionStore,
               sessionExtractor: sessionExtractor,
               dio:
                   dio ??
                   Dio(
                     BaseOptions(
                       baseUrl: AppConfig.apiBaseUrl,
                       connectTimeout: AppConfig.connectTimeout,
                       receiveTimeout: AppConfig.receiveTimeout,
                       followRedirects: true,
                       validateStatus: (status) =>
                           status != null && status >= 200 && status < 400,
                     ),
                   ),
               enableLog: enableLog,
             ),
           );

  final CookieStore _cookieStore;
  final YamiboSessionStore? _sessionStore;
  final YamiboApiClient _yamiboApiClient;

  Future<void> clearSession() async {
    await _cookieStore.clear();
    _sessionStore?.clear();
  }

  /// 返回 Discuz 原始通用结构，供上层按需二次解析
  Future<ApiResult<DiscuzResponse>> getDiscuz({
    required String module,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool treatMessageAsBusinessError = true,
  }) {
    return _yamiboApiClient.getDiscuz(
      module: module,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      treatMessageAsBusinessError: treatMessageAsBusinessError,
    );
  }

  /// 以 `application/x-www-form-urlencoded` 提交 Discuz 移动端表单。
  Future<ApiResult<DiscuzResponse>> postDiscuzForm({
    required String module,
    required Map<String, String> data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return _yamiboApiClient.postDiscuzForm(
      module: module,
      data: data,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: options,
    );
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
}
