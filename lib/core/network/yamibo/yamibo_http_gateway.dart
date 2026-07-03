import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_diagnostic_recorder.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/core/network/yamibo/yamibo_http_response.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_request_logger.dart';
import 'package:y300/core/network/yamibo/yamibo_session_extractor.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/utils/parse_utils.dart';

class YamiboHttpGateway {
  YamiboHttpGateway({
    required CookieStore cookieStore,
    required Logger logger,
    NetworkDiagnosticRecorder? diagnosticRecorder,
    YamiboSessionStore? sessionStore,
    YamiboSessionExtractor? sessionExtractor,
    WafChallengeResolver? wafChallengeResolver,
    Dio? dio,
    bool enableLog = true,
    String defaultUserAgent = BrowserUserAgents.mobile,
  }) : _cookieStore = cookieStore,
       _sessionStore = sessionStore,
       _sessionExtractor = sessionExtractor,
       _wafChallengeResolver = wafChallengeResolver,
       _defaultUserAgent = defaultUserAgent,
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
  final WafChallengeResolver? _wafChallengeResolver;
  final String _defaultUserAgent;
  final NetworkDiagnosticRecorder _diagnosticRecorder;
  final YamiboRequestLogger _requestLogger;
  final Dio _dio;
  int _nextRequestSequence = 0;

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

  Future<ApiResult<YamiboHttpResponse<Object?>>> getJson(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    return _request<Object?>(
      method: 'GET',
      uri,
      context: context,
      headers: headers,
      responseType: ResponseType.json,
      cancelToken: cancelToken,
      normalizeBody: (data) => data,
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

  Future<ApiResult<YamiboHttpResponse<String>>> postFormFields(
    Uri uri, {
    required YamiboRequestContext context,
    required List<MapEntry<String, String>> data,
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
      data: _encodeFormFields(data),
      contentType: options?.contentType ?? Headers.formUrlEncodedContentType,
      followRedirects: followRedirects ?? options?.followRedirects,
      validateStatus: validateStatus ?? options?.validateStatus,
      normalizeBody: (responseData) => responseData?.toString() ?? '',
    );
  }

  Future<ApiResult<YamiboHttpResponse<Object?>>> postFormJson(
    Uri uri, {
    required YamiboRequestContext context,
    required Map<String, String> data,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    Options? options,
    bool? followRedirects,
    ValidateStatus? validateStatus,
  }) async {
    return _request<Object?>(
      uri,
      method: 'POST',
      context: context,
      headers: headers,
      responseType: ResponseType.json,
      cancelToken: cancelToken,
      data: data,
      contentType: options?.contentType ?? Headers.formUrlEncodedContentType,
      followRedirects: followRedirects ?? options?.followRedirects,
      validateStatus: validateStatus ?? options?.validateStatus,
      normalizeBody: (responseData) => responseData,
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
    int attempt = 0,
  }) async {
    final startedAt = DateTime.now();
    final requestId = _generateRequestId();
    final requestHeaders = <String, String>{...?headers};
    // The forum's WAF answers non-browser requests with a JS challenge instead
    // of JSON/HTML. Guarantee a browser User-Agent on every request here at the
    // single transport chokepoint, so no caller (e.g. the mobile JSON API) can
    // accidentally omit it. Callers that set their own UA are left untouched.
    if (!_hasHeader(requestHeaders, 'user-agent')) {
      requestHeaders['User-Agent'] = _defaultUserAgent;
    }
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      requestHeaders['Cookie'] = cookieHeader;
    }

    try {
      final response = await _dio.requestUri<dynamic>(
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

      // 阿里云 WAF 挑战检测：正文看起来是 arg1 挑战脚本时，让 resolver
      // 用 headless WebView 跑一遍挑战、把 acw_sc__v2 回灌 dio，然后重发
      // 一次同一请求。只在第一次尝试上做检测，避免死循环。若刷新失败
      // （已在放行窗口内 / passer 抛错），把这次响应作为失败结果返回。
      final resolver = _wafChallengeResolver;
      if (attempt == 0 &&
          resolver != null &&
          WafChallengeDetector.isChallenge(body)) {
        final refreshed = await resolver.ensureFreshPass(triggeringUri: uri);
        _requestLogger.logWafChallenge(
          context: context,
          requestId: requestId,
          method: response.requestOptions.method,
          uri: response.requestOptions.uri,
          willRetry: refreshed,
        );
        if (refreshed) {
          return _request<T>(
            uri,
            method: method,
            context: context,
            responseType: responseType,
            normalizeBody: normalizeBody,
            headers: headers,
            cancelToken: cancelToken,
            data: data,
            contentType: contentType,
            followRedirects: followRedirects,
            validateStatus: validateStatus,
            onSendProgress: onSendProgress,
            attempt: attempt + 1,
          );
        }
        // 刷新未发生（窗口内 / passer 失败）——把这次响应视为错误返回。
        final elapsedMs = _elapsedMs(startedAt);
        _diagnosticRecorder.recordHttpRequest(
          method: response.requestOptions.method,
          uri: response.requestOptions.uri,
          startedAt: startedAt,
          elapsedMs: elapsedMs,
          statusCode: response.statusCode,
          succeeded: false,
          error: 'waf_challenge',
          kind: context.kind.name,
          operation: context.operation,
          module: context.module,
          pageKind: context.pageKind,
          requestId: requestId,
        );
        return ApiFailure(
          ApiError(
            type: ApiErrorType.server,
            message: '被 WAF 挑战拦截，请稍后重试',
            statusCode: response.statusCode,
            raw: body,
          ),
        );
      }

      _saveExtractedSession(body: body, context: context);
      final elapsedMs = _elapsedMs(startedAt);
      _recordSuccess(
        context: context,
        requestId: requestId,
        response: response,
        startedAt: startedAt,
        elapsedMs: elapsedMs,
      );
      _requestLogger.logSuccess(
        context: context,
        requestId: requestId,
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
      _recordFailure(
        context: context,
        requestId: requestId,
        error: error,
        startedAt: startedAt,
        elapsedMs: elapsedMs,
      );
      _requestLogger.logFailure(
        context: context,
        requestId: requestId,
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

  void _saveExtractedSession({
    required Object? body,
    required YamiboRequestContext context,
  }) {
    final store = _sessionStore;
    final extractor = _sessionExtractor;
    if (store == null || extractor == null) {
      return;
    }
    final snapshot = switch (context.kind) {
      YamiboRequestKind.api => _extractApiSession(
        body: body,
        context: context,
        extractor: extractor,
      ),
      YamiboRequestKind.html =>
        body is String
            ? extractor.extractFromHtml(
                body,
                source: 'html:${context.operation}',
              )
            : null,
      YamiboRequestKind.resource || YamiboRequestKind.imageProbe => null,
    };
    if (snapshot != null) {
      store.saveExtracted(snapshot);
    }
  }

  YamiboSessionSnapshot? _extractApiSession({
    required Object? body,
    required YamiboRequestContext context,
    required YamiboSessionExtractor extractor,
  }) {
    try {
      final decoded = body is String
          ? jsonDecode(_normalizeJsonText(body))
          : body;
      final variables = ParseUtils.asMap(
        ParseUtils.asMap(decoded)['Variables'],
      );
      if (variables.isEmpty) {
        return null;
      }
      return extractor.extractFromApiVariables(
        variables,
        source: 'api:${context.module ?? context.operation}',
      );
    } catch (_) {
      // Session extraction is best-effort; API parsing still belongs to YamiboApiClient.
      return null;
    }
  }

  String _normalizeJsonText(String data) {
    var text = data;
    while (text.isNotEmpty) {
      final trimmed = text.trimLeft();
      if (trimmed.length != text.length) {
        text = trimmed;
        continue;
      }
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
        continue;
      }
      // Some servers/proxies expose UTF-8 BOM bytes after a lossy decode.
      if (text.startsWith('ï»¿')) {
        text = text.substring(3);
        continue;
      }
      break;
    }
    return text;
  }

  void _recordSuccess({
    required YamiboRequestContext context,
    required String requestId,
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
      kind: context.kind.name,
      operation: context.operation,
      module: context.module,
      pageKind: context.pageKind,
      requestId: requestId,
    );
  }

  void _recordFailure({
    required YamiboRequestContext context,
    required String requestId,
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
      kind: context.kind.name,
      operation: context.operation,
      module: context.module,
      pageKind: context.pageKind,
      requestId: requestId,
    );
  }

  ApiError _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    final rawError = responseData ?? error.error;

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiError(
        type: ApiErrorType.timeout,
        message: '请求超时，请稍后重试',
        statusCode: statusCode,
        raw: rawError,
      );
    }

    if (statusCode == 401 || statusCode == 403) {
      return ApiError(
        type: ApiErrorType.unauthorized,
        message: '登录态失效，请重新登录',
        statusCode: statusCode,
        raw: rawError,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        type: ApiErrorType.server,
        message: '服务端异常($statusCode)',
        statusCode: statusCode,
        raw: rawError,
      );
    }

    if (error.type == DioExceptionType.badResponse) {
      return ApiError(
        type: ApiErrorType.server,
        message: '请求失败($statusCode)',
        statusCode: statusCode,
        raw: rawError,
      );
    }

    return ApiError(
      type: ApiErrorType.network,
      message: '网络异常: ${error.message ?? 'unknown'}',
      statusCode: statusCode,
      raw: rawError,
    );
  }

  int _elapsedMs(DateTime startedAt) {
    return DateTime.now().difference(startedAt).inMilliseconds;
  }

  /// Case-insensitive header presence check. HTTP header names are
  /// case-insensitive, so a caller-supplied `User-Agent` / `user-agent` must
  /// suppress the fallback regardless of casing.
  bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    return headers.keys.any((key) => key.toLowerCase() == lower);
  }

  String _generateRequestId() {
    _nextRequestSequence += 1;
    return 'yhttp-$_nextRequestSequence';
  }

  String _encodeFormFields(List<MapEntry<String, String>> fields) {
    return fields
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }
}
