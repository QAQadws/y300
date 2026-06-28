import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';

class SyncCacheDiagnosticRecorder implements CacheDiagnosticRecorder {
  const SyncCacheDiagnosticRecorder(this._recorder);

  final SyncDiagnosticRecorder _recorder;

  @override
  void record(CacheDiagnosticEvent event) {
    _recorder.record(
      scope: 'cache',
      event: event.event,
      fields: event.toFields(),
    );
  }
}
