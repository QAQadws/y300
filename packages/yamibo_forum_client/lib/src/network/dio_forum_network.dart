import 'dart:async';

import 'package:dio/dio.dart';

import '../client/forum_client_config.dart';
import '../logging/forum_client_logger.dart';
import '../session/forum_cookie_store.dart';
import '../waf/forum_waf.dart';
import 'forum_network.dart';
import 'forum_request.dart';
import 'forum_response.dart';
import 'forum_transport.dart';

final class DioForumClientNetwork implements ForumClientNetwork {
  DioForumClientNetwork({
    required this.config,
    required this.cookies,
    this.waf,
    ForumClientLogger? logger,
    Dio? dio,
  }) : logger = logger ?? const NoopForumClientLogger(),
       _dio = dio ?? Dio();

  final ForumClientConfig config;
  final ForumCookieStore cookies;
  final ForumWafRecoveryDelegate? waf;
  final ForumClientLogger logger;
  final Dio _dio;
  int _sequence = 0;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.cancelled,
          code: 'cancelled',
        ),
      );
    }
    final requestId = (++_sequence).toString();
    final started = DateTime.now();
    final headers = <String, String>{
      'User-Agent': config.userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Referer': config.siteOrigin.toString(),
      ...request.headers,
    };
    final stored = await cookies.read(request.uri);
    if (stored.isNotEmpty) headers['Cookie'] = _cookieHeader(stored);
    logger.requestStarted(
      operation: request.context.operation,
      method: request.method.name.toUpperCase(),
      uri: request.uri,
    );

    try {
      final cancelToken = CancelToken();
      final cancellation = request.cancellation;
      final responseFuture = _dio.requestUri<Object?>(
        request.uri,
        data: request.body,
        options: Options(
          method: request.method.name.toUpperCase(),
          headers: headers,
          responseType: switch (request.responseType) {
            ForumResponseType.text => ResponseType.plain,
            ForumResponseType.json => ResponseType.json,
            ForumResponseType.bytes => ResponseType.bytes,
          },
          followRedirects: request.followRedirects,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken,
      );
      final response = cancellation == null
          ? await responseFuture
          : await Future.any<Response<Object?>>(<Future<Response<Object?>>>[
              responseFuture,
              cancellation.whenCancelled.then<Response<Object?>>((_) {
                cancelToken.cancel('cancelled');
                throw DioException.requestCancelled(
                  requestOptions: RequestOptions(path: request.uri.toString()),
                  reason: 'cancelled',
                );
              }),
            ]);
      await cookies.mergeSetCookie(
        request.uri,
        response.headers.map['set-cookie'] ?? const <String>[],
      );
      final body = response.data;
      final challenge = _detectChallenge(
        body,
        response.statusCode,
        request.method,
      );
      if (challenge != null) {
        final recovery = waf == null
            ? ForumWafRecoveryResult.unavailable
            : await waf!.recover(
                ForumWafRecoveryRequest(
                  uri: request.uri,
                  method: request.method.name.toUpperCase(),
                  evidence: challenge,
                  userAgent: config.userAgent,
                ),
              );
        if (recovery == ForumWafRecoveryResult.verified) {
          return _sendOnce(
            request,
            requestId: requestId,
            started: started,
            retry: true,
          );
        }
        return ForumTransportError<ForumResponse<Object?>>(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.server,
            code: 'waf_${recovery.name}',
            statusCode: response.statusCode,
          ),
        );
      }
      final result = _statusResult(
        response.statusCode,
        body,
        request.uri,
        headers: response.headers.map,
      );
      logger.requestFinished(
        operation: request.context.operation,
        method: request.method.name.toUpperCase(),
        uri: request.uri,
        statusCode: response.statusCode,
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
      return result;
    } on DioException catch (error) {
      final failure = _mapDioFailure(error);
      logger.requestFailed(
        operation: request.context.operation,
        method: request.method.name.toUpperCase(),
        uri: request.uri,
        code: failure.code,
        statusCode: failure.statusCode,
      );
      return ForumTransportError<ForumResponse<Object?>>(failure);
    } on StateError catch (_) {
      return const ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.cancelled,
          code: 'cancelled',
        ),
      );
    } catch (_) {
      return const ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.unknown,
          code: 'unknown',
        ),
      );
    }
  }

  Future<ForumTransportResult<ForumResponse<Object?>>> _sendOnce(
    ForumRequest request, {
    required String requestId,
    required DateTime started,
    required bool retry,
  }) async {
    final retryRequest = ForumRequest(
      method: request.method,
      uri: request.uri,
      context: request.context,
      headers: request.headers,
      body: request.body,
      responseType: request.responseType,
      followRedirects: request.followRedirects,
      cancellation: request.cancellation,
    );
    // A verified challenge permits exactly one replay. The recursive call is
    // intentionally isolated from challenge recovery to prevent a loop.
    return _sendWithoutRecovery(
      retryRequest,
      requestId: requestId,
      started: started,
    );
  }

  Future<ForumTransportResult<ForumResponse<Object?>>> _sendWithoutRecovery(
    ForumRequest request, {
    required String requestId,
    required DateTime started,
  }) async {
    final headers = <String, String>{
      'User-Agent': config.userAgent,
      'Accept': '*/*',
      'Referer': config.siteOrigin.toString(),
      ...request.headers,
    };
    final stored = await cookies.read(request.uri);
    if (stored.isNotEmpty) headers['Cookie'] = _cookieHeader(stored);
    try {
      final response = await _dio.requestUri<Object?>(
        request.uri,
        data: request.body,
        options: Options(
          method: request.method.name.toUpperCase(),
          headers: headers,
          responseType: request.responseType == ForumResponseType.json
              ? ResponseType.json
              : ResponseType.plain,
          followRedirects: request.followRedirects,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      await cookies.mergeSetCookie(
        request.uri,
        response.headers.map['set-cookie'] ?? const <String>[],
      );
      return _statusResult(
        response.statusCode,
        response.data,
        request.uri,
        headers: response.headers.map,
      );
    } on DioException catch (error) {
      return ForumTransportError<ForumResponse<Object?>>(_mapDioFailure(error));
    } catch (_) {
      return const ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.unknown,
          code: 'unknown',
        ),
      );
    }
  }

  ForumTransportResult<ForumResponse<Object?>> _statusResult(
    int? status,
    Object? body,
    Uri uri, {
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) {
    if (status == 401 || status == 403) {
      return ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.unauthorized,
          code: 'unauthorized',
          statusCode: status,
        ),
      );
    }
    if (status != null && status >= 400 && status < 500) {
      return ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.business,
          code: 'http_client_error',
          statusCode: status,
        ),
      );
    }
    if (status != null && status >= 500) {
      return ForumTransportError<ForumResponse<Object?>>(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.server,
          code: 'http_server_error',
          statusCode: status,
        ),
      );
    }
    return ForumTransportSuccess<ForumResponse<Object?>>(
      ForumResponse(uri: uri, statusCode: status, headers: headers, body: body),
    );
  }

  ForumTransportFailure _mapDioFailure(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const ForumTransportFailure(
        kind: ForumTransportFailureKind.cancelled,
        code: 'cancelled',
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const ForumTransportFailure(
        kind: ForumTransportFailureKind.timeout,
        code: 'timeout',
      );
    }
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return ForumTransportFailure(
        kind: ForumTransportFailureKind.unauthorized,
        code: 'unauthorized',
        statusCode: status,
      );
    }
    if (status != null && status >= 500) {
      return ForumTransportFailure(
        kind: ForumTransportFailureKind.server,
        code: 'http_server_error',
        statusCode: status,
      );
    }
    return ForumTransportFailure(
      kind: ForumTransportFailureKind.network,
      code: 'network',
      statusCode: status,
    );
  }

  ForumWafEvidence? _detectChallenge(
    Object? body,
    int? status,
    ForumRequestMethod method,
  ) {
    if (_isChallengeBody(body)) {
      return ForumWafEvidence.scriptBody;
    }
    if (status == 405 && method == ForumRequestMethod.get) {
      return ForumWafEvidence.methodNotAllowed;
    }
    return null;
  }

  bool _isChallengeBody(Object? body) {
    final text = switch (body) {
      String value => value.length <= 8192 ? value : value.substring(0, 8192),
      List<int> value => String.fromCharCodes(
        value.take(8192).map((byte) => byte & 0xff),
      ),
      _ => '',
    };
    final normalized = text.trimLeft().toLowerCase();
    final scriptStart = normalized.indexOf('<script');
    final shell =
        (normalized.startsWith('<html') ||
            normalized.startsWith('<!doctype') ||
            normalized.startsWith('<script')) &&
        scriptStart >= 0 &&
        scriptStart <= 512;
    if (!shell) {
      return false;
    }
    final scriptEnd = normalized.indexOf('</script>', scriptStart);
    final script = normalized.substring(
      scriptStart,
      scriptEnd < 0 ? normalized.length : scriptEnd,
    );
    return RegExp(
          r'''\bvar\s+arg1\s*=\s*['"]''',
          caseSensitive: false,
        ).hasMatch(script) ||
        (script.contains('document.cookie') && script.contains('acw_sc__v2'));
  }

  String _cookieHeader(Map<String, String> values) =>
      values.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
