import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/cookie_store.dart';
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
    YamiboSessionStore? sessionStore,
    YamiboSessionExtractor? sessionExtractor,
    WafChallengeRecoveryCoordinator? wafChallengeRecoveryCoordinator,
    Dio? dio,
    bool enableLog = true,
    String defaultUserAgent = BrowserUserAgents.mobile,
    Uri? siteUri,
  }) : _cookieStore = cookieStore,
       _sessionStore = sessionStore,
       _sessionExtractor = sessionExtractor,
       _wafChallengeRecoveryCoordinator = wafChallengeRecoveryCoordinator,
       _defaultUserAgent = defaultUserAgent,
       _siteUri = siteUri ?? Uri.parse(AppConfig.siteBaseUrl),
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
  final WafChallengeRecoveryCoordinator? _wafChallengeRecoveryCoordinator;
  final String _defaultUserAgent;
  final Uri _siteUri;
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

  /// Checks whether the shared native cookie jar can now access a same-site
  /// page without the WAF challenge.
  ///
  /// This intentionally bypasses [_request]'s recovery hook. It is called
  /// while the foreground recovery route is still open; routing the probe
  /// through the coordinator would make it await itself forever. Challenge
  /// responses are not persisted or used for session extraction.
  Future<WafChallengeClearance> probeWafChallengeClearance(
    Uri uri, {
    required String userAgent,
    CancelToken? cancelToken,
  }) async {
    if (!_isSameSite(uri)) {
      return WafChallengeClearance.inconclusive;
    }

    final headers = <String, String>{
      'User-Agent': userAgent.trim().isEmpty ? _defaultUserAgent : userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Referer': _siteUri
          .replace(
            path: '/',
            queryParameters: const <String, String>{},
            fragment: '',
          )
          .toString(),
    };
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    try {
      final response = await _dio.requestUri<dynamic>(
        uri,
        options: Options(
          method: 'GET',
          headers: headers,
          responseType: ResponseType.plain,
          followRedirects: true,
          // A 405 is evidence, not a Dio transport exception, so the probe
          // must inspect every HTTP status itself.
          validateStatus: (status) => status != null,
        ),
        cancelToken: cancelToken,
      );
      if (!_isSameSite(response.realUri)) {
        return WafChallengeClearance.inconclusive;
      }
      final evidence = WafChallengeDetector.detect(
        body: response.data,
        statusCode: response.statusCode,
        method: 'GET',
      );
      if (evidence != null) {
        return WafChallengeClearance.challenged;
      }
      final statusCode = response.statusCode;
      if (statusCode != null && statusCode >= 200 && statusCode < 400) {
        return WafChallengeClearance.cleared;
      }
      return WafChallengeClearance.inconclusive;
    } on DioException catch (error) {
      final response = error.response;
      if (response != null) {
        final evidence = WafChallengeDetector.detect(
          body: response.data,
          statusCode: response.statusCode,
          method: 'GET',
        );
        if (evidence != null) {
          return WafChallengeClearance.challenged;
        }
      }
      return WafChallengeClearance.inconclusive;
    } catch (_) {
      return WafChallengeClearance.inconclusive;
    }
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
    // The forum fronting layer treats non-browser requests differently, so we
    // guarantee a browser User-Agent on every request here at the single
    // transport chokepoint — no caller (e.g. the mobile JSON API) can
    // accidentally omit it. Callers that set their own UA are left untouched.
    if (!_hasHeader(requestHeaders, 'user-agent')) {
      requestHeaders['User-Agent'] = _defaultUserAgent;
    }
    final effectiveUserAgent = _headerValue(requestHeaders, 'user-agent');
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
      final body = normalizeBody(response.data);

      final challengeEvidence = _detectSecurityChallenge(
        context: context,
        uri: response.requestOptions.uri,
        method: response.requestOptions.method,
        statusCode: response.statusCode,
        body: body,
      );
      if (challengeEvidence != null) {
        final recovery = attempt == 0
            ? await _recoverSecurityChallenge(
                uri: response.requestOptions.uri,
                method: response.requestOptions.method,
                evidence: challengeEvidence,
                userAgent: effectiveUserAgent,
              )
            : null;
        final recovered = recovery == WafChallengeRecoveryResult.verified;
        _requestLogger.logSecurityChallenge(
          context: context,
          requestId: requestId,
          method: response.requestOptions.method,
          uri: response.requestOptions.uri,
          statusCode: response.statusCode,
          evidence: challengeEvidence.name,
          willRetry: recovered,
          recovery: recovery?.name ?? 'retryLimitReached',
        );
        if (recovered) {
          return _request<T>(
            uri,
            method: method,
            context: context,
            responseType: responseType,
            normalizeBody: normalizeBody,
            headers: headers,
            cancelToken: cancelToken,
            data: _cloneRequestData(data),
            contentType: contentType,
            followRedirects: followRedirects,
            validateStatus: validateStatus,
            onSendProgress: onSendProgress,
            attempt: attempt + 1,
          );
        }
        return ApiFailure(
          _securityChallengeError(
            statusCode: response.statusCode,
            body: body,
            alreadyRetried: attempt > 0,
          ),
        );
      }

      await _saveCookies(response);

      _saveExtractedSession(body: body, context: context);
      final elapsedMs = _elapsedMs(startedAt);
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
      final challengeEvidence = _detectSecurityChallenge(
        context: context,
        uri: error.requestOptions.uri,
        method: error.requestOptions.method,
        statusCode: response?.statusCode,
        body: response?.data,
      );
      if (challengeEvidence != null) {
        final recovery = attempt == 0
            ? await _recoverSecurityChallenge(
                uri: error.requestOptions.uri,
                method: error.requestOptions.method,
                evidence: challengeEvidence,
                userAgent: effectiveUserAgent,
              )
            : null;
        final recovered = recovery == WafChallengeRecoveryResult.verified;
        _requestLogger.logSecurityChallenge(
          context: context,
          requestId: requestId,
          method: error.requestOptions.method,
          uri: error.requestOptions.uri,
          statusCode: response?.statusCode,
          evidence: challengeEvidence.name,
          willRetry: recovered,
          recovery: recovery?.name ?? 'retryLimitReached',
        );
        if (recovered) {
          return _request<T>(
            uri,
            method: method,
            context: context,
            responseType: responseType,
            normalizeBody: normalizeBody,
            headers: headers,
            cancelToken: cancelToken,
            data: _cloneRequestData(data),
            contentType: contentType,
            followRedirects: followRedirects,
            validateStatus: validateStatus,
            onSendProgress: onSendProgress,
            attempt: attempt + 1,
          );
        }
        return ApiFailure(
          _securityChallengeError(
            statusCode: response?.statusCode,
            body: response?.data,
            alreadyRetried: attempt > 0,
          ),
        );
      }
      if (response != null) {
        await _saveCookies(response);
      }
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

  WafChallengeEvidence? _detectSecurityChallenge({
    required YamiboRequestContext context,
    required Uri uri,
    required String method,
    required int? statusCode,
    required Object? body,
  }) {
    if (!_isSameSite(uri)) {
      return null;
    }
    final evidence = WafChallengeDetector.detect(
      body: body,
      statusCode: statusCode,
      method: method,
    );
    if (evidence == WafChallengeEvidence.httpMethodNotAllowed &&
        (context.kind == YamiboRequestKind.resource ||
            context.kind == YamiboRequestKind.imageProbe)) {
      return null;
    }
    return evidence;
  }

  Future<WafChallengeRecoveryResult> _recoverSecurityChallenge({
    required Uri uri,
    required String method,
    required WafChallengeEvidence evidence,
    required String? userAgent,
  }) async {
    final coordinator = _wafChallengeRecoveryCoordinator;
    if (coordinator == null) {
      return WafChallengeRecoveryResult.unavailable;
    }
    return coordinator.recover(
      WafChallengeRecoveryRequest(
        triggeringUri: uri,
        method: method,
        evidence: evidence,
        userAgent: userAgent ?? _defaultUserAgent,
      ),
    );
  }

  ApiError _securityChallengeError({
    required int? statusCode,
    required Object? body,
    required bool alreadyRetried,
  }) {
    return ApiError(
      type: ApiErrorType.server,
      message: alreadyRetried
          ? 'network.security_challenge_persisted'
          : 'network.security_verification_not_completed',
      code: alreadyRetried
          ? 'security_challenge_persisted'
          : 'security_verification_not_completed',
      statusCode: statusCode,
      raw: body,
    );
  }

  Object? _cloneRequestData(Object? data) {
    return data is FormData ? data.clone() : data;
  }

  bool _isSameSite(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }
    return uri.host.toLowerCase() == _siteUri.host.toLowerCase();
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

  String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
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
