import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/providers/sync_diagnostic_providers.dart';
import 'package:y300/features/library_shared/data/repositories/sync_diagnostic_settings_repository.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';

final syncDiagnosticModeControllerProvider = AsyncNotifierProvider<
    SyncDiagnosticModeController,
    bool>(SyncDiagnosticModeController.new);

class SyncDiagnosticModeController extends AsyncNotifier<bool> {
  SyncDiagnosticSettingsRepository get _settingsRepository =>
      ref.read(syncDiagnosticSettingsRepositoryProvider);

  SyncDiagnosticRecorder get _recorder =>
      ref.read(syncDiagnosticRecorderProvider);

  @override
  Future<bool> build() async {
    final enabled = await _settingsRepository.loadManualModeEnabled();
    if (_recorder.isManualModeEnabled != enabled) {
      await _recorder.setManualModeEnabled(enabled);
    }
    return enabled;
  }

  Future<bool> toggle() async {
    final current = state.value ?? false;
    final next = !current;
    await _recorder.setManualModeEnabled(next);
    state = AsyncData(next);
    return next;
  }
}
