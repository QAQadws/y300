/// Source-neutral forum client logger.
abstract interface class ForumClientLogger {
  /// Records the start of a sanitized request.
  void requestStarted({
    required String operation,
    required String method,
    required Uri uri,
  });

  /// Records successful completion without sensitive payloads.
  void requestFinished({
    required String operation,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
  });

  /// Records a sanitized request failure.
  void requestFailed({
    required String operation,
    required String method,
    required Uri uri,
    required String code,
    required int? statusCode,
  });
}

/// Source-neutral noop forum client logger.
final class NoopForumClientLogger implements ForumClientLogger {
  /// Creates a [NoopForumClientLogger].
  const NoopForumClientLogger();
  @override
  void requestStarted({
    required String operation,
    required String method,
    required Uri uri,
  }) {}
  @override
  void requestFinished({
    required String operation,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
  }) {}
  @override
  void requestFailed({
    required String operation,
    required String method,
    required Uri uri,
    required String code,
    required int? statusCode,
  }) {}
}
