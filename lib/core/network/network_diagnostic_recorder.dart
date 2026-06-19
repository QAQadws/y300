abstract class NetworkDiagnosticRecorder {
  void recordHttpRequest({
    required String method,
    required Uri uri,
    required DateTime startedAt,
    required int elapsedMs,
    int? statusCode,
    bool succeeded = true,
    String? error,
    String? kind,
    String? operation,
    String? module,
    String? pageKind,
    String? requestId,
  });
}

class NoopNetworkDiagnosticRecorder implements NetworkDiagnosticRecorder {
  const NoopNetworkDiagnosticRecorder();

  @override
  void recordHttpRequest({
    required String method,
    required Uri uri,
    required DateTime startedAt,
    required int elapsedMs,
    int? statusCode,
    bool succeeded = true,
    String? error,
    String? kind,
    String? operation,
    String? module,
    String? pageKind,
    String? requestId,
  }) {}
}
