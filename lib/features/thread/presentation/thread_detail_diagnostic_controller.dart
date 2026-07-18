import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/thread/data/repositories/thread_detail_diagnostic_settings_repository.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';

final threadDetailDiagnosticSettingsRepositoryProvider =
    Provider<ThreadDetailDiagnosticSettingsRepository>((ref) {
      return SharedPrefsThreadDetailDiagnosticSettingsRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final threadDetailDiagnosticRecorderProvider =
    Provider<ThreadDetailDiagnosticRecorder>((ref) {
      // release → const no-op (tree-shaken hot path); debug → in-memory.
      return ThreadDetailDiagnosticRecorder.forCurrentBuild();
    });

final threadDetailDiagnosticControllerProvider =
    AsyncNotifierProvider<ThreadDetailDiagnosticController, bool>(
      ThreadDetailDiagnosticController.new,
    );

class ThreadDetailDiagnosticController extends AsyncNotifier<bool> {
  ThreadDetailDiagnosticSettingsRepository get _repository =>
      ref.read(threadDetailDiagnosticSettingsRepositoryProvider);

  ThreadDetailDiagnosticRecorder get _recorder =>
      ref.read(threadDetailDiagnosticRecorderProvider);

  @override
  Future<bool> build() async {
    final enabled = await _repository.loadScrollDiagnosticEnabled();
    _recorder.setEnabled(enabled);
    return enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    final effective = kDebugMode && enabled;
    state = AsyncData(effective);
    _recorder.setEnabled(effective);
    try {
      await _repository.setScrollDiagnosticEnabled(effective);
      if (!effective) {
        _recorder.clear();
      }
    } catch (error, stackTrace) {
      final previous = !effective;
      _recorder.setEnabled(previous);
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String exportText() {
    return _recorder.exportText();
  }

  void clear() {
    _recorder.clear();
  }
}
