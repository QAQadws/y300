import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';

void main() {
  test('forwards cache diagnostic events to sync diagnostic recorder', () {
    final sync = _RecordingSyncDiagnosticRecorder();
    final recorder = SyncCacheDiagnosticRecorder(sync);

    recorder.record(
      const CacheDiagnosticEvent(
        event: 'hit',
        namespace: CacheNamespace.snapshot,
        bucket: StorageBucket.pageCache,
        cacheKey: 'snapshot|thread',
        ownerType: CacheOwnerType.thread,
        ownerId: 'tid=1&page=1',
        hit: true,
        reason: 'fresh_snapshot',
      ),
    );

    expect(sync.records, hasLength(1));
    expect(sync.records.single.scope, 'cache');
    expect(sync.records.single.event, 'hit');
    expect(sync.records.single.fields['namespace'], 'snapshot');
    expect(sync.records.single.fields['bucket'], 'page_cache');
    expect(sync.records.single.fields['reason'], 'fresh_snapshot');
  });
}

class _DiagnosticRecord {
  const _DiagnosticRecord({
    required this.scope,
    required this.event,
    required this.fields,
  });

  final String scope;
  final String event;
  final Map<String, Object?> fields;
}

class _RecordingSyncDiagnosticRecorder implements SyncDiagnosticRecorder {
  final records = <_DiagnosticRecord>[];

  @override
  String? get currentLogPath => null;

  @override
  bool get isManualModeEnabled => true;

  @override
  void activateFavoriteFirstSync() {}

  @override
  Future<bool> setManualModeEnabled(bool enabled) async => enabled;

  @override
  void record({
    required String scope,
    required String event,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    records.add(_DiagnosticRecord(scope: scope, event: event, fields: fields));
  }

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
