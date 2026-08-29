import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../client/forum_client_config.dart';
import '../contracts/forum_resource.dart';
import '../logging/forum_client_logger.dart';
import '../session/forum_cookie_store.dart';
import '../waf/forum_waf.dart';
import 'forum_network.dart';
import 'forum_multipart.dart';
import 'forum_request.dart';
import 'forum_request_profile.dart';
import 'forum_response.dart';
import 'forum_transport.dart';

final class DioForumClientNetwork
    implements ForumClientNetwork, ForumResourceClient, ForumMultipartClient {
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
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) => _sendMultipart(request, recoveryAttempt: 0);

  Future<ForumTransportResult<ForumMultipartResponse>> _sendMultipart(
    ForumMultipartRequest request, {
    required int recoveryAttempt,
  }) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.cancelled,
          code: 'cancelled',
        ),
      );
    }
    if (!_sameResourceAuthority(request.uri, config.siteOrigin)) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.business,
          code: 'multipart_cross_site_rejected',
        ),
      );
    }
    final headers = <String, String>{
      'User-Agent': config.effectiveApiUserAgent,
      'Accept': 'text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      ...request.headers,
    };
    final stored = await cookies.read(request.uri);
    if (stored.isNotEmpty) headers['Cookie'] = _cookieHeader(stored);
    final cancelToken = CancelToken();
    final cancellation = request.cancellation;
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (!cancelToken.isCancelled) cancelToken.cancel('cancelled');
        }),
      );
    }
    final file = request.file;
    try {
      final data = FormData.fromMap(<String, Object>{
        ...request.fields,
        file.fieldName: MultipartFile.fromStream(
          file.openRead,
          file.contentLength,
          filename: file.fileName,
          contentType: DioMediaType.parse(file.contentType),
        ),
      });
      final response = await _dio.requestUri<String>(
        request.uri,
        data: data,
        options: Options(
          method: 'POST',
          headers: headers,
          responseType: ResponseType.plain,
          followRedirects: request.followRedirects,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          validateStatus: (status) => status != null,
        ),
        cancelToken: cancelToken,
        onSendProgress: request.onSendProgress,
      );
      final status = response.statusCode;
      if (_detectChallenge(response.realUri, status) != null) {
        if (recoveryAttempt > 0) {
          return const ForumTransportError(
            ForumTransportFailure(
              kind: ForumTransportFailureKind.server,
              code: 'security_challenge_persisted',
              statusCode: 405,
            ),
          );
        }
        final recovery = waf == null
            ? ForumWafRecoveryResult.unavailable
            : await waf!.recover(
                ForumWafRecoveryRequest(
                  uri: request.uri,
                  method: 'POST',
                  evidence: ForumWafEvidence.httpStatus405,
                  userAgent: headers['User-Agent']!,
                ),
              );
        if (recovery != ForumWafRecoveryResult.verified) {
          return ForumTransportError(
            ForumTransportFailure(
              kind: ForumTransportFailureKind.server,
              code: 'waf_${recovery.name}',
              statusCode: status,
            ),
          );
        }
        return _sendMultipart(request, recoveryAttempt: 1);
      }
      await cookies.mergeSetCookie(
        request.uri,
        response.headers.map['set-cookie'] ?? const <String>[],
      );
      if (status == null || status < 200 || status >= 300) {
        return ForumTransportError(
          ForumTransportFailure(
            kind: status == 401 || status == 403
                ? ForumTransportFailureKind.unauthorized
                : ForumTransportFailureKind.server,
            code: 'multipart_http_error',
            statusCode: status,
          ),
        );
      }
      return ForumTransportSuccess(
        ForumMultipartResponse(
          uri: response.realUri,
          statusCode: status,
          headers: response.headers.map,
          body: response.data ?? '',
        ),
      );
    } on DioException catch (error) {
      return ForumTransportError(_mapDioFailure(error));
    } on FormatException {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.business,
          code: 'multipart_content_type_invalid',
        ),
      );
    } catch (_) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.unknown,
          code: 'multipart_unknown',
        ),
      );
    }
  }

  static const int _resourceSignatureLimit = 512;
  static const int _maxResourceRedirects = 5;
  static const Duration _defaultResourceLifetime = Duration(days: 7);

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) async {
    final resolved =
        ForumResourceReferenceResolver(siteOrigin: config.siteOrigin).resolve(
          request.reference.uri.toString(),
          referer: request.reference.referer,
          kind: request.reference.kind,
        );
    if (resolved == null || resolved.kind != ForumResourceKind.image) {
      return const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.invalidReference,
          code: 'invalid_resource_reference',
        ),
      );
    }
    return _openResource(
      ForumResourceRequest(
        reference: resolved,
        ifNoneMatch: request.ifNoneMatch,
        cancellation: request.cancellation,
      ),
      uri: resolved.uri,
      redirectCount: 0,
      recoveryAttempt: 0,
      allowConditionalHeaders: true,
    );
  }

  Future<ForumResourceResult> _openResource(
    ForumResourceRequest request, {
    required Uri uri,
    required int redirectCount,
    required int recoveryAttempt,
    required bool allowConditionalHeaders,
  }) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.cancelled,
          code: 'cancelled',
        ),
      );
    }
    final effectiveReference =
        ForumResourceReferenceResolver(siteOrigin: config.siteOrigin).resolve(
          uri.toString(),
          referer: request.reference.referer,
          kind: request.reference.kind,
        );
    if (effectiveReference == null) {
      return const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.invalidReference,
          code: 'invalid_resource_reference',
        ),
      );
    }
    final sameSite = effectiveReference.origin == ForumResourceOrigin.sameSite;
    final headers = DefaultForumRequestProfileResolver(config)
        .resolve(
          ForumRequestProfileKind.resource,
          referer: effectiveReference.referer,
        )
        .headers
        .cast<String, String>();
    final eTag = request.ifNoneMatch?.trim();
    if (allowConditionalHeaders && eTag?.isNotEmpty == true) {
      headers['If-None-Match'] = eTag!;
    }
    if (sameSite) {
      final stored = await cookies.read(uri);
      if (stored.isNotEmpty) headers['Cookie'] = _cookieHeader(stored);
    }

    final cancelToken = CancelToken();
    final cancellation = request.cancellation;
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (!cancelToken.isCancelled) cancelToken.cancel('cancelled');
        }),
      );
    }
    try {
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: Options(
          method: 'GET',
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: false,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          validateStatus: (status) => status != null,
        ),
        cancelToken: cancelToken,
      );
      final status = response.statusCode ?? 0;
      final body = response.data;
      if (body == null) {
        return const ForumResourceError(
          ForumResourceFailure(
            kind: ForumResourceFailureKind.network,
            code: 'missing_resource_stream',
          ),
        );
      }
      if (_isRedirectStatus(status)) {
        await _cancelResourceBodyBestEffort(body.stream);
        final location = response.headers.value('location');
        final target = location == null ? null : uri.resolve(location);
        if (target == null ||
            !_isHttpResource(target) ||
            target.userInfo.isNotEmpty ||
            redirectCount >= _maxResourceRedirects ||
            (uri.scheme == 'https' && target.scheme == 'http')) {
          return ForumResourceError(
            ForumResourceFailure(
              kind: ForumResourceFailureKind.redirectRejected,
              code: 'resource_redirect_rejected',
              statusCode: status,
            ),
          );
        }
        return _openResource(
          request,
          uri: target.removeFragment(),
          redirectCount: redirectCount + 1,
          recoveryAttempt: recoveryAttempt,
          allowConditionalHeaders:
              allowConditionalHeaders && _sameResourceAuthority(uri, target),
        );
      }

      if (status == 304) {
        await _cancelResourceBodyBestEffort(body.stream);
        return ForumResourceSuccess(
          uri: response.realUri,
          statusCode: status,
          content: const Stream<List<int>>.empty(),
          validUntil: _resourceValidUntil(response.headers.map),
          contentType: response.headers.value('content-type'),
          eTag: response.headers.value('etag'),
          fileExtension: _resourceExtension(
            response.headers.value('content-type'),
            response.realUri,
          ),
        );
      }

      if (sameSite && status == 405) {
        await _cancelResourceBodyBestEffort(body.stream);
        if (recoveryAttempt > 0) {
          return const ForumResourceError(
            ForumResourceFailure(
              kind: ForumResourceFailureKind.securityChallenge,
              code: 'security_challenge_persisted',
              statusCode: 405,
            ),
          );
        }
        final recovery = waf == null
            ? ForumWafRecoveryResult.unavailable
            : await waf!.recover(
                ForumWafRecoveryRequest(
                  uri: uri,
                  method: 'GET',
                  evidence: ForumWafEvidence.httpStatus405,
                  userAgent: config.effectiveResourceUserAgent,
                ),
              );
        if (recovery != ForumWafRecoveryResult.verified) {
          return ForumResourceError(
            ForumResourceFailure(
              kind: ForumResourceFailureKind.securityChallenge,
              code: 'waf_${recovery.name}',
              statusCode: status,
            ),
          );
        }
        return _openResource(
          request,
          uri: uri,
          redirectCount: redirectCount,
          recoveryAttempt: recoveryAttempt + 1,
          allowConditionalHeaders: allowConditionalHeaders,
        );
      }

      if (sameSite) {
        await cookies.mergeSetCookie(
          uri,
          response.headers.map['set-cookie'] ?? const <String>[],
        );
      }

      if (status < 200 || status >= 300) {
        await _cancelResourceBodyBestEffort(body.stream);
        return ForumResourceError(_resourceStatusFailure(status));
      }

      final contentType = response.headers.value('content-type');
      if (_hasDeclaredImageContentType(contentType)) {
        return ForumResourceSuccess(
          uri: response.realUri,
          statusCode: status,
          content: _directResourceStream(body.stream),
          contentLength: body.contentLength,
          contentType: contentType,
          eTag: response.headers.value('etag'),
          validUntil: _resourceValidUntil(response.headers.map),
          fileExtension: _resourceExtension(contentType, response.realUri),
        );
      }

      final iterator = StreamIterator<List<int>>(body.stream);
      final prefix = await _readResourcePrefix(iterator);
      if (!_isSupportedImage(contentType, prefix.bytes)) {
        await _cancelResourceIteratorBestEffort(iterator);
        return ForumResourceError(
          ForumResourceFailure(
            kind: ForumResourceFailureKind.invalidContent,
            code: 'resource_is_not_image',
            statusCode: status,
          ),
        );
      }

      return ForumResourceSuccess(
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
      );
    } on DioException catch (error) {
      return ForumResourceError(_resourceDioFailure(error));
    } catch (_) {
      return const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.unknown,
          code: 'resource_unknown',
        ),
      );
    }
  }

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
          validateStatus: (status) => status != null,
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
      final body = response.data;
      final challenge = _detectChallenge(response.realUri, response.statusCode);
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
      await cookies.mergeSetCookie(
        request.uri,
        response.headers.map['set-cookie'] ?? const <String>[],
      );
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
          responseType: switch (request.responseType) {
            ForumResponseType.text => ResponseType.plain,
            ForumResponseType.json => ResponseType.json,
            ForumResponseType.bytes => ResponseType.bytes,
          },
          followRedirects: request.followRedirects,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          validateStatus: (status) => status != null,
        ),
      );
      if (_detectChallenge(response.realUri, response.statusCode) != null) {
        return const ForumTransportError<ForumResponse<Object?>>(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.server,
            code: 'security_challenge_persisted',
            statusCode: 405,
          ),
        );
      }
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

  ForumWafEvidence? _detectChallenge(Uri uri, int? status) {
    if (!_isManagedForumUri(uri) || status != 405) {
      return null;
    }
    return ForumWafEvidence.httpStatus405;
  }

  String _cookieHeader(Map<String, String> values) =>
      values.entries.map((e) => '${e.key}=${e.value}').join('; ');

  bool _isHttpResource(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  bool _isManagedForumUri(Uri uri) {
    bool sameAuthority(Uri origin) =>
        uri.scheme == origin.scheme &&
        uri.host.toLowerCase() == origin.host.toLowerCase() &&
        uri.port == origin.port;
    final apiOrigin = config.apiOrigin;
    return sameAuthority(config.siteOrigin) ||
        (apiOrigin != null && sameAuthority(apiOrigin));
  }

  bool _sameResourceAuthority(Uri first, Uri second) =>
      first.scheme == second.scheme &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;

  bool _isRedirectStatus(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  Future<_ResourcePrefix> _readResourcePrefix(
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
    return _ResourcePrefix(bytes: prefix, tail: tail);
  }

  Stream<List<int>> _resourceStream(
    _ResourcePrefix prefix,
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
      throw ForumResourceStreamException(
        failure: _resourceDioFailure(error),
        bytesReceived: received,
      );
    } catch (_) {
      throw ForumResourceStreamException(
        failure: const ForumResourceFailure(
          kind: ForumResourceFailureKind.network,
          code: 'resource_stream_failed',
        ),
        bytesReceived: received,
      );
    } finally {
      await _cancelResourceIteratorBestEffort(iterator);
    }
  }

  ForumResourceFailure _resourceStatusFailure(int status) {
    if (status == 401 || status == 403) {
      return ForumResourceFailure(
        kind: ForumResourceFailureKind.unauthorized,
        code: 'resource_unauthorized',
        statusCode: status,
      );
    }
    if (status == 404) {
      return const ForumResourceFailure(
        kind: ForumResourceFailureKind.notFound,
        code: 'resource_not_found',
        statusCode: 404,
      );
    }
    return ForumResourceFailure(
      kind: ForumResourceFailureKind.server,
      code: 'resource_http_error',
      statusCode: status,
    );
  }

  ForumResourceFailure _resourceDioFailure(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const ForumResourceFailure(
        kind: ForumResourceFailureKind.cancelled,
        code: 'cancelled',
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const ForumResourceFailure(
        kind: ForumResourceFailureKind.timeout,
        code: 'resource_timeout',
      );
    }
    final status = error.response?.statusCode;
    if (status != null) return _resourceStatusFailure(status);
    return const ForumResourceFailure(
      kind: ForumResourceFailureKind.network,
      code: 'resource_network',
    );
  }

  DateTime _resourceValidUntil(Map<String, List<String>> headers) {
    var lifetime = _defaultResourceLifetime;
    final cacheControl = _firstHeader(headers, 'cache-control');
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

  String? _firstHeader(Map<String, List<String>> headers, String name) {
    final expected = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == expected && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  bool _isSupportedImage(String? contentType, List<int> prefix) {
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
      throw ForumResourceStreamException(
        failure: _resourceDioFailure(error),
        bytesReceived: received,
      );
    } catch (_) {
      throw ForumResourceStreamException(
        failure: const ForumResourceFailure(
          kind: ForumResourceFailureKind.network,
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
      // Cleanup must not replace a classified response or completed stream.
    }
  }
}

final class _ResourcePrefix {
  const _ResourcePrefix({required this.bytes, required this.tail});

  final List<int> bytes;
  final List<int>? tail;
}
