import 'package:y300/core/network/network_diagnostic_recorder.dart';

abstract class SyncDiagnosticRecorder implements NetworkDiagnosticRecorder {
  String? get currentLogPath;

  bool get isManualModeEnabled;

  void activateFavoriteFirstSync();

  Future<bool> setManualModeEnabled(bool enabled);

  void record({
    required String scope,
    required String event,
    Map<String, Object?> fields,
  });

}

class NoopSyncDiagnosticRecorder implements SyncDiagnosticRecorder {
  const NoopSyncDiagnosticRecorder();

  @override
  String? get currentLogPath => null;

  @override
  bool get isManualModeEnabled => false;

  @override
  void activateFavoriteFirstSync() {}

  @override
  Future<bool> setManualModeEnabled(bool enabled) async => false;

  @override
  void record({
    required String scope,
    required String event,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}

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
