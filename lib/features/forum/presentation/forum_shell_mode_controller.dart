import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/data/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';

final forumModeSettingsRepositoryProvider =
    Provider<ForumModeSettingsRepository>((ref) {
  return SharedPrefsForumModeSettingsRepository();
});

final forumShellModeControllerProvider =
    AsyncNotifierProvider<ForumShellModeController, ForumShellMode>(
  ForumShellModeController.new,
);

class ForumShellModeController extends AsyncNotifier<ForumShellMode> {
  ForumModeSettingsRepository get _repository =>
      ref.read(forumModeSettingsRepositoryProvider);

  @override
  Future<ForumShellMode> build() {
    return _repository.loadMode();
  }

  Future<void> setMode(ForumShellMode mode) async {
    final previous = state.value ?? ForumShellMode.webview;
    if (previous == mode) {
      return;
    }

    state = AsyncData(mode);
    try {
      await _repository.saveMode(mode);
    } catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
