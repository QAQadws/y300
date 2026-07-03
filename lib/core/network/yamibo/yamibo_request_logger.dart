import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

class YamiboRequestLogger {
  const YamiboRequestLogger({required Logger logger, bool enableLog = true})
    : _logger = logger,
      _enableLog = enableLog;

  final Logger _logger;
  final bool _enableLog;

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
      '$method $uri -> ${statusCode ?? 'unknown'} ${elapsedMs}ms '
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
      '$method $uri -> failed ${statusCode ?? 'unknown'} ${elapsedMs}ms '
      'requestId=$requestId '
      'error=${error.type.name}',
    );
  }

  /// 记录一次 WAF 挑战检出。用 warn 级别落日志，方便在无控制台的手机上通过
  /// 应用内诊断面板追溯"某个业务失败其实是被 WAF 顶回来了"。
  void logWafChallenge({
    required YamiboRequestContext context,
    required String requestId,
    required String method,
    required Uri uri,
    required bool willRetry,
  }) {
    if (!_enableLog || context.silent) {
      return;
    }
    _logger.w(
      '[YamiboHTTP][${_kindName(context.kind)}][${context.operation}] '
      '$method $uri -> waf challenge '
      '${willRetry ? 'refreshing pass and retrying once' : 'refresh skipped or failed'} '
      'requestId=$requestId',
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
