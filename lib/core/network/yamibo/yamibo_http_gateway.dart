import 'dart:async';
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
import 'package:y300/core/network/yamibo/yamibo_resource_stream.dart';
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

  static const int _resourceSignatureLimit = 512;
  static const int _maxResourceRedirects = 5;
  static const Duration _defaultResourceLifetime = Duration(days: 7);

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

  /// Opens an image resource through the application-owned Cookie/WAF/Dio
  /// session without buffering the complete response in memory.
  Future<ApiResult<YamiboResourceStreamResponse>> openImageResource(
    Uri uri, {
    required Uri referer,
    required String userAgent,
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) {
    return _openImageResource(
      uri,
      referer: referer,
      userAgent: userAgent,
      ifNoneMatch: ifNoneMatch,
      cancelToken: cancelToken,
      redirectCount: 0,
      recoveryAttempt: 0,
      allowConditionalHeaders: true,
    );
  }

  Future<ApiResult<YamiboResourceStreamResponse>> _openImageResource(
    Uri uri, {
    required Uri referer,
    required String userAgent,
    required String? ifNoneMatch,
    required CancelToken? cancelToken,
    required int redirectCount,
    required int recoveryAttempt,
    required bool allowConditionalHeaders,
  }) async {
    if (!_isHttpResource(uri) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.business,
          message: 'invalid_resource_reference',
          code: 'invalid_resource_reference',
        ),
      );
    }
    final sameSite = _isSameSiteResource(uri);
    final effectiveReferer = _resourceReferer(referer, sameSite: sameSite);
    final headers = <String, String>{
      'User-Agent': userAgent.trim().isEmpty ? _defaultUserAgent : userAgent,
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': effectiveReferer.toString(),
      if (allowConditionalHeaders && ifNoneMatch?.trim().isNotEmpty == true)
        'If-None-Match': ifNoneMatch!.trim(),
    };
    if (sameSite) {
      final cookieHeader = await _cookieStore.readCookieHeader(uri);
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }
    }

    try {
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: Options(
          method: 'GET',
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null,
        ),
        cancelToken: cancelToken,
      );
      final body = response.data;
      if (body == null) {
        return const ApiFailure(
          ApiError(
            type: ApiErrorType.network,
            message: 'missing_resource_stream',
            code: 'missing_resource_stream',
          ),
        );
      }
      final status = response.statusCode ?? 0;

      if (_isResourceRedirect(status)) {
        await _cancelResourceBodyBestEffort(body.stream);
        final location = response.headers.value('location');
        final target = location == null ? null : uri.resolve(location);
        if (target == null ||
            !_isHttpResource(target) ||
            target.userInfo.isNotEmpty ||
            redirectCount >= _maxResourceRedirects ||
            (uri.scheme == 'https' && target.scheme == 'http')) {
          return ApiFailure(
            ApiError(
              type: ApiErrorType.server,
              message: 'resource_redirect_rejected',
              code: 'resource_redirect_rejected',
              statusCode: status,
            ),
          );
        }
        return _openImageResource(
          target.removeFragment(),
          referer: referer,
          userAgent: userAgent,
          ifNoneMatch: ifNoneMatch,
          cancelToken: cancelToken,
          redirectCount: redirectCount + 1,
          recoveryAttempt: recoveryAttempt,
          allowConditionalHeaders:
              allowConditionalHeaders && _sameResourceAuthority(uri, target),
        );
      }

      if (status == 304) {
        await _cancelResourceBodyBestEffort(body.stream);
        return ApiSuccess(
          YamiboResourceStreamResponse(
            uri: response.realUri,
            statusCode: status,
            content: const Stream<List<int>>.empty(),
            contentType: response.headers.value('content-type'),
            eTag: response.headers.value('etag'),
            validUntil: _resourceValidUntil(response.headers.map),
            fileExtension: _resourceExtension(
              response.headers.value('content-type'),
              response.realUri,
            ),
          ),
        );
      }

      final challenge = sameSite
          ? WafChallengeDetector.detect(statusCode: status)
          : null;
      if (challenge != null) {
        await _cancelResourceBodyBestEffort(body.stream);
        if (recoveryAttempt > 0) {
          return ApiFailure(
            ApiError(
              type: ApiErrorType.server,
              message: 'network.security_challenge_persisted',
              code: 'security_challenge_persisted',
              statusCode: status,
            ),
          );
        }
        final recovery = await _recoverSecurityChallenge(
          uri: uri,
          method: 'GET',
          evidence: challenge,
          userAgent: userAgent,
        );
        if (recovery != WafChallengeRecoveryResult.verified) {
          return ApiFailure(
            ApiError(
              type: ApiErrorType.server,
              message: 'network.security_verification_not_completed',
              code: 'security_verification_not_completed',
              statusCode: status,
            ),
          );
        }
        return _openImageResource(
          uri,
          referer: referer,
          userAgent: userAgent,
          ifNoneMatch: ifNoneMatch,
          cancelToken: cancelToken,
          redirectCount: redirectCount,
          recoveryAttempt: recoveryAttempt + 1,
          allowConditionalHeaders: allowConditionalHeaders,
        );
      }

      if (sameSite) await _saveCookies(response);

      if (status < 200 || status >= 300) {
        await _cancelResourceBodyBestEffort(body.stream);
        return ApiFailure(_resourceStatusError(status));
      }

      final contentType = response.headers.value('content-type');
      if (_hasDeclaredImageContentType(contentType)) {
        return ApiSuccess(
          YamiboResourceStreamResponse(
            uri: response.realUri,
            statusCode: status,
            content: _directResourceStream(body.stream),
            contentLength: body.contentLength,
            contentType: contentType,
            eTag: response.headers.value('etag'),
            validUntil: _resourceValidUntil(response.headers.map),
            fileExtension: _resourceExtension(contentType, response.realUri),
          ),
        );
      }

      final iterator = StreamIterator<List<int>>(body.stream);
      final prefix = await _readResourcePrefix(iterator);
      if (!_isSupportedImageResource(contentType, prefix.bytes)) {
        await _cancelResourceIteratorBestEffort(iterator);
        return ApiFailure(
          ApiError(
            type: ApiErrorType.parse,
            message: 'resource_is_not_image',
            code: 'resource_is_not_image',
            statusCode: status,
          ),
        );
      }

      return ApiSuccess(
        YamiboResourceStreamResponse(
          uri: response.realUri,
          statusCode: status,
          content: _resourceStream(prefix, iterator),
          contentLength: body.contentLength,
          contentType: contentType,
          eTag: response.headers.value('etag'),
          validUntil: _resourceValidUntil(response.headers.map),
          fileExtension: _resourceExtension(
            contentType,
            response.realUri,
            signature: prefix.bytes,
          ),
        ),
      );
    } on DioException catch (error) {
      return ApiFailure(_mapDioError(error));
    } catch (_) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.unknown,
          message: 'resource_unknown',
          code: 'resource_unknown',
        ),
      );
    }
  }

  /// Checks whether the shared native cookie jar can now access a same-site
  /// page without the WAF challenge.
  ///
  /// This intentionally bypasses [_request]'s recovery hook. It is called
  /// while the background recovery WebView is still mounted; routing the probe
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
        statusCode: response.statusCode,
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
          statusCode: response.statusCode,
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
        uri: response.requestOptions.uri,
        statusCode: response.statusCode,
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
        uri: error.requestOptions.uri,
        statusCode: response?.statusCode,
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
    required Uri uri,
    required int? statusCode,
  }) {
    if (!_isSameSite(uri)) {
      return null;
    }
    return WafChallengeDetector.detect(statusCode: statusCode);
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

    if (error.type == DioExceptionType.cancel) {
      return ApiError(
        type: ApiErrorType.network,
        message: '请求已取消',
        code: 'request_cancelled',
        statusCode: statusCode,
        raw: rawError,
      );
    }

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

  bool _isHttpResource(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  bool _isSameSiteResource(Uri uri) =>
      _isHttpResource(uri) &&
      uri.host.toLowerCase() == _siteUri.host.toLowerCase() &&
      uri.port == _siteUri.port;

  bool _sameResourceAuthority(Uri first, Uri second) =>
      first.scheme == second.scheme &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;

  Uri _resourceReferer(Uri referer, {required bool sameSite}) {
    final fallback = _siteUri.replace(path: '/', query: null, fragment: null);
    if (!_isHttpResource(referer) || !_isSameSiteResource(referer)) {
      return fallback;
    }
    if (sameSite) return referer.removeFragment();
    return _uriWithoutQueryOrFragment(referer);
  }

  Uri _uriWithoutQueryOrFragment(Uri uri) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );

  bool _isResourceRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  Future<_YamiboResourcePrefix> _readResourcePrefix(
    StreamIterator<List<int>> iterator,
  ) async {
    final prefix = <int>[];
    List<int>? tail;
    while (prefix.length < _resourceSignatureLimit &&
        await iterator.moveNext()) {
      final chunk = iterator.current;
      final remaining = _resourceSignatureLimit - prefix.length;
      if (chunk.length <= remaining) {
        prefix.addAll(chunk);
      } else {
        prefix.addAll(chunk.take(remaining));
        tail = chunk.sublist(remaining);
      }
      if (tail != null) break;
    }
    return _YamiboResourcePrefix(bytes: prefix, tail: tail);
  }

  Stream<List<int>> _resourceStream(
    _YamiboResourcePrefix prefix,
    StreamIterator<List<int>> iterator,
  ) async* {
    var received = 0;
    try {
      if (prefix.bytes.isNotEmpty) {
        received += prefix.bytes.length;
        yield prefix.bytes;
      }
      final tail = prefix.tail;
      if (tail != null && tail.isNotEmpty) {
        received += tail.length;
        yield tail;
      }
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        received += chunk.length;
        yield chunk;
      }
    } on DioException catch (error) {
      throw YamiboResourceStreamException(
        error: _mapDioError(error),
        bytesReceived: received,
      );
    } catch (_) {
      throw YamiboResourceStreamException(
        error: const ApiError(
          type: ApiErrorType.network,
          message: 'resource_stream_failed',
          code: 'resource_stream_failed',
        ),
        bytesReceived: received,
      );
    } finally {
      await _cancelResourceIteratorBestEffort(iterator);
    }
  }

  ApiError _resourceStatusError(int status) {
    if (status == 401 || status == 403) {
      return ApiError(
        type: ApiErrorType.unauthorized,
        message: 'resource_unauthorized',
        code: 'resource_unauthorized',
        statusCode: status,
      );
    }
    if (status == 404) {
      return const ApiError(
        type: ApiErrorType.business,
        message: 'resource_not_found',
        code: 'resource_not_found',
        statusCode: 404,
      );
    }
    return ApiError(
      type: ApiErrorType.server,
      message: 'resource_http_error',
      code: 'resource_http_error',
      statusCode: status,
    );
  }

  DateTime _resourceValidUntil(Map<String, List<String>> headers) {
    var lifetime = _defaultResourceLifetime;
    final cacheControl = _firstResponseHeader(headers, 'cache-control');
    if (cacheControl != null) {
      for (final setting in cacheControl.split(',')) {
        final value = setting.trim().toLowerCase();
        if (value == 'no-cache' || value == 'no-store') {
          lifetime = Duration.zero;
        } else if (value.startsWith('max-age=')) {
          final seconds = int.tryParse(value.substring('max-age='.length));
          if (seconds != null && seconds >= 0) {
            lifetime = Duration(seconds: seconds);
          }
        }
      }
    }
    return DateTime.now().add(lifetime);
  }

  String? _firstResponseHeader(Map<String, List<String>> headers, String name) {
    final expected = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == expected && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  bool _isSupportedImageResource(String? contentType, List<int> prefix) {
    final mime = contentType?.split(';').first.trim().toLowerCase();
    return _hasImageSignature(prefix) || mime?.startsWith('image/') == true;
  }

  bool _hasDeclaredImageContentType(String? contentType) {
    final mime = contentType?.split(';').first.trim().toLowerCase();
    return mime?.startsWith('image/') == true;
  }

  bool _hasImageSignature(List<int> bytes) =>
      _resourceExtensionFromSignature(bytes).isNotEmpty;

  String _resourceExtension(
    String? contentType,
    Uri uri, {
    List<int>? signature,
  }) {
    final fromSignature = signature == null
        ? ''
        : _resourceExtensionFromSignature(signature);
    if (fromSignature.isNotEmpty) return fromSignature;
    final mime = contentType?.split(';').first.trim().toLowerCase();
    final fromMime = switch (mime) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/avif' => '.avif',
      'image/svg+xml' => '.svg',
      'image/bmp' => '.bmp',
      'image/x-icon' || 'image/vnd.microsoft.icon' => '.ico',
      _ => '',
    };
    if (fromMime.isNotEmpty) return fromMime;
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = segment.lastIndexOf('.');
    if (dot < 0) return '';
    final extension = segment.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension) ? extension : '';
  }

  String _resourceExtensionFromSignature(List<int> bytes) {
    bool starts(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index += 1) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    if (starts(const <int>[0xff, 0xd8, 0xff])) return '.jpg';
    if (starts(const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return '.png';
    }
    if (starts(const <int>[0x47, 0x49, 0x46, 0x38])) return '.gif';
    if (starts(const <int>[0x42, 0x4d])) return '.bmp';
    if (starts(const <int>[0x00, 0x00, 0x01, 0x00])) return '.ico';
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return '.webp';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      final brand = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (brand == 'avif' || brand == 'avis') return '.avif';
      if (const <String>{
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return '.heic';
      }
    }
    final text = utf8
        .decode(bytes.take(1024).toList(growable: false), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return text.startsWith('<svg') ||
            (text.startsWith('<?xml') && text.contains('<svg'))
        ? '.svg'
        : '';
  }

  Stream<List<int>> _directResourceStream(Stream<List<int>> source) async* {
    var received = 0;
    try {
      await for (final chunk in source) {
        received += chunk.length;
        yield chunk;
      }
    } on DioException catch (error) {
      throw YamiboResourceStreamException(
        error: _mapDioError(error),
        bytesReceived: received,
      );
    } catch (_) {
      throw YamiboResourceStreamException(
        error: const ApiError(
          type: ApiErrorType.network,
          message: 'resource_stream_failed',
          code: 'resource_stream_failed',
        ),
        bytesReceived: received,
      );
    }
  }

  Future<void> _cancelResourceBodyBestEffort(Stream<List<int>> source) async {
    final iterator = StreamIterator<List<int>>(source);
    await _cancelResourceIteratorBestEffort(iterator);
  }

  Future<void> _cancelResourceIteratorBestEffort(
    StreamIterator<List<int>> iterator,
  ) async {
    try {
      await iterator.cancel();
    } catch (_) {
      // Resource cleanup must not replace the already classified response.
    }
  }
}

class _YamiboResourcePrefix {
  const _YamiboResourcePrefix({required this.bytes, required this.tail});

  final List<int> bytes;
  final List<int>? tail;
}
