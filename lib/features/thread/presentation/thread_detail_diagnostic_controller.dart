import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/data/thread_detail_diagnostic_settings_repository.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';

final threadDetailDiagnosticSettingsRepositoryProvider =
    Provider<ThreadDetailDiagnosticSettingsRepository>((ref) {
      return const SharedPrefsThreadDetailDiagnosticSettingsRepository();
    });

final threadDetailDiagnosticRecorderProvider =
    Provider<InMemoryThreadDetailDiagnosticRecorder>((ref) {
      return InMemoryThreadDetailDiagnosticRecorder();
    });

final threadDetailDiagnosticControllerProvider =
    AsyncNotifierProvider<ThreadDetailDiagnosticController, bool>(
      ThreadDetailDiagnosticController.new,
    );

class ThreadDetailDiagnosticController extends AsyncNotifier<bool> {
  ThreadDetailDiagnosticSettingsRepository get _repository =>
      ref.read(threadDetailDiagnosticSettingsRepositoryProvider);

  InMemoryThreadDetailDiagnosticRecorder get _recorder =>
      ref.read(threadDetailDiagnosticRecorderProvider);

  @override
  Future<bool> build() async {
    final enabled = await _repository.loadScrollDiagnosticEnabled();
    _recorder.enabledState = enabled;
    return enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    _recorder.enabledState = enabled;
    try {
      await _repository.setScrollDiagnosticEnabled(enabled);
      if (!enabled) {
        _recorder.clear();
      }
    } catch (error, stackTrace) {
      final previous = !enabled;
      _recorder.enabledState = previous;
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
