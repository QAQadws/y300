abstract interface class ForumClientLogger {
  void requestStarted({
    required String operation,
    required String method,
    required Uri uri,
  });
  void requestFinished({
    required String operation,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
  });
  void requestFailed({
    required String operation,
    required String method,
    required Uri uri,
    required String code,
    required int? statusCode,
  });
}

final class NoopForumClientLogger implements ForumClientLogger {
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
