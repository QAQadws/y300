import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_uri_redactor.dart';

class YamiboRequestLogger {
  const YamiboRequestLogger({
    required Logger logger,
    bool enableLog = true,
    YamiboUriRedactor uriRedactor = const YamiboUriRedactor(),
  }) : _logger = logger,
       _enableLog = enableLog,
       _uriRedactor = uriRedactor;

  final Logger _logger;
  final bool _enableLog;
  final YamiboUriRedactor _uriRedactor;

  void logSuccess({
    required YamiboRequestContext context,
    required String requestId,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
    required Object? body,
  }) {
    if (!_enableLog || context.silent) {
      return;
    }
    _logger.i(
      '[YamiboHTTP][${_kindName(context.kind)}][${context.operation}] '
      '$method ${_uriRedactor.redact(uri)} -> '
      '${statusCode ?? 'unknown'} ${elapsedMs}ms '
      'requestId=$requestId '
      'body=${describeBody(body)}',
    );
  }

  void logFailure({
    required YamiboRequestContext context,
    required String requestId,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
    required DioException error,
  }) {
    if (!_enableLog || context.silent) {
      return;
    }
    _logger.w(
      '[YamiboHTTP][${_kindName(context.kind)}][${context.operation}] '
      '$method ${_uriRedactor.redact(uri)} -> failed '
      '${statusCode ?? 'unknown'} ${elapsedMs}ms '
      'requestId=$requestId '
      'error=${error.type.name}',
    );
  }

  String describeBody(Object? body) {
    if (body == null) {
      return 'null';
    }
    if (body is String) {
      return 'String(length=${body.length})';
    }
    if (body is List<int>) {
      return 'Bytes(length=${body.length})';
    }
    if (body is Map) {
      return 'Map(length=${body.length})';
    }
    if (body is Iterable) {
      return '${body.runtimeType}(length=${body.length})';
    }
    return body.runtimeType.toString();
  }

  String _kindName(YamiboRequestKind kind) {
    return switch (kind) {
      YamiboRequestKind.api => 'api',
      YamiboRequestKind.html => 'html',
      YamiboRequestKind.resource => 'resource',
      YamiboRequestKind.imageProbe => 'imageProbe',
    };
  }
}
