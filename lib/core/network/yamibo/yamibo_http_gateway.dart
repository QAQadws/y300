import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_diagnostic_recorder.dart';
import 'package:y300/core/network/yamibo/yamibo_http_response.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_request_logger.dart';
import 'package:y300/core/network/yamibo/yamibo_session_extractor.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';

class YamiboHttpGateway {
  YamiboHttpGateway({
    required CookieStore cookieStore,
    required Logger logger,
    NetworkDiagnosticRecorder? diagnosticRecorder,
    YamiboSessionStore? sessionStore,
    YamiboSessionExtractor? sessionExtractor,
    Dio? dio,
    bool enableLog = true,
  }) : _cookieStore = cookieStore,
       _sessionStore = sessionStore,
       _sessionExtractor = sessionExtractor,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopNetworkDiagnosticRecorder(),
       _requestLogger = YamiboRequestLogger(
         logger: logger,
         enableLog: enableLog,
       ),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.siteBaseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
               followRedirects: true,
               validateStatus: (status) =>
                   status != null && status >= 200 && status < 400,
             ),
           );

  final CookieStore _cookieStore;
  final YamiboSessionStore? _sessionStore;
  final YamiboSessionExtractor? _sessionExtractor;
  final NetworkDiagnosticRecorder _diagnosticRecorder;
  final YamiboRequestLogger _requestLogger;
  final Dio _dio;

  Future<ApiResult<YamiboHttpResponse<String>>> getText(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    bool? followRedirects,
    ValidateStatus? validateStatus,
  }) async {
    return _request<String>(
      method: 'GET',
      uri,
      context: context,
      headers: headers,
      responseType: ResponseType.plain,
      cancelToken: cancelToken,
      followRedirects: followRedirects,
      validateStatus: validateStatus,
      normalizeBody: (data) => data?.toString() ?? '',
    );
  }

  Future<ApiResult<YamiboHttpResponse<List<int>>>> getBytes(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    return _request<List<int>>(
      method: 'GET',
      uri,
      context: context,
      headers: headers,
      responseType: ResponseType.bytes,
      cancelToken: cancelToken,
      normalizeBody: (data) {
        if (data is List<int>) {
          return data;
        }
        return const <int>[];
      },
    );
  }

  Future<ApiResult<YamiboHttpResponse<String>>> postForm(
    Uri uri, {
    required YamiboRequestContext context,
    required Map<String, String> data,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    Options? options,
    bool? followRedirects,
    ValidateStatus? validateStatus,
  }) async {
    return _request<String>(
      uri,
      method: 'POST',
      context: context,
      headers: headers,
      responseType: ResponseType.plain,
      cancelToken: cancelToken,
      data: data,
      contentType: options?.contentType ?? Headers.formUrlEncodedContentType,
      followRedirects: followRedirects ?? options?.followRedirects,
      validateStatus: validateStatus ?? options?.validateStatus,
      normalizeBody: (responseData) => responseData?.toString() ?? '',
    );
  }

  Future<ApiResult<YamiboHttpResponse<Object?>>> postMultipart(
    Uri uri, {
    required YamiboRequestContext context,
    required FormData data,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
  }) async {
    return _request<Object?>(
      uri,
      method: 'POST',
      context: context,
      headers: headers,
      responseType: options?.responseType ?? ResponseType.json,
      cancelToken: cancelToken,
      data: data,
      contentType: options?.contentType,
      followRedirects: options?.followRedirects,
      validateStatus: options?.validateStatus,
      onSendProgress: onSendProgress,
      normalizeBody: (responseData) => responseData,
    );
  }

  Future<ApiResult<YamiboHttpResponse<T>>> _request<T>(
    Uri uri, {
    required String method,
    required YamiboRequestContext context,
    required ResponseType responseType,
    required T Function(Object? data) normalizeBody,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    Object? data,
    String? contentType,
    bool? followRedirects,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
  }) async {
    final startedAt = DateTime.now();
    final requestHeaders = <String, String>{...?headers};
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      requestHeaders['Cookie'] = cookieHeader;
    }

    try {
      final response = await _dio.requestUri<Object?>(
        uri,
        data: data,
        options: Options(
          method: method,
          headers: requestHeaders,
          responseType: responseType,
          contentType: contentType,
          followRedirects: followRedirects,
          validateStatus: validateStatus,
        ),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
      await _saveCookies(response);
      final body = normalizeBody(response.data);
      _saveExtractedHtmlSession(body: body, context: context);
      final elapsedMs = _elapsedMs(startedAt);
      _recordSuccess(
        response: response,
        startedAt: startedAt,
        elapsedMs: elapsedMs,
      );
      _requestLogger.logSuccess(
        context: context,
        method: response.requestOptions.method,
        uri: response.requestOptions.uri,
        statusCode: response.statusCode,
        elapsedMs: elapsedMs,
        body: body,
      );
      return ApiSuccess(
        YamiboHttpResponse<T>(
          uri: response.requestOptions.uri,
          statusCode: response.statusCode,
          headers: response.headers.map,
          body: body,
        ),
      );
    } on DioException catch (error) {
      final elapsedMs = _elapsedMs(startedAt);
      final response = error.response;
      if (response != null) {
        await _saveCookies(response);
      }
      _recordFailure(error: error, startedAt: startedAt, elapsedMs: elapsedMs);
      _requestLogger.logFailure(
        context: context,
        method: error.requestOptions.method,
        uri: error.requestOptions.uri,
        statusCode: error.response?.statusCode,
        elapsedMs: elapsedMs,
        error: error,
      );
      return ApiFailure(_mapDioError(error));
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

  Future<void> _saveCookies(Response<dynamic> response) async {
    final setCookie = response.headers.map['set-cookie'] ?? const <String>[];
    await _cookieStore.saveFromSetCookie(
      response.requestOptions.uri,
      setCookie,
    );
  }

  void _saveExtractedHtmlSession({
    required Object? body,
    required YamiboRequestContext context,
  }) {
    final store = _sessionStore;
    final extractor = _sessionExtractor;
    if (store == null || extractor == null || body is! String) {
      return;
    }
    final snapshot = extractor.extractFromHtml(
      body,
      source: 'html:${context.operation}',
    );
    if (snapshot != null) {
      store.saveExtracted(snapshot);
    }
  }

  void _recordSuccess({
    required Response<Object?> response,
    required DateTime startedAt,
    required int elapsedMs,
  }) {
    _diagnosticRecorder.recordHttpRequest(
      method: response.requestOptions.method,
      uri: response.requestOptions.uri,
      startedAt: startedAt,
      elapsedMs: elapsedMs,
      statusCode: response.statusCode,
      succeeded: true,
    );
  }

  void _recordFailure({
    required DioException error,
    required DateTime startedAt,
    required int elapsedMs,
  }) {
    final request = error.requestOptions;
    _diagnosticRecorder.recordHttpRequest(
      method: request.method,
      uri: request.uri,
      startedAt: startedAt,
      elapsedMs: elapsedMs,
      statusCode: error.response?.statusCode,
      succeeded: false,
      error: error.message,
    );
  }

  ApiError _mapDioError(DioException error) {
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
        message: '请求失败($statusCode)',
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

  int _elapsedMs(DateTime startedAt) {
    return DateTime.now().difference(startedAt).inMilliseconds;
  }
}
