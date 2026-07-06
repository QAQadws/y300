import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/data/repositories/thread_detail_html_first_render_mode_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_html_first_render_mode.dart';

final threadDetailHtmlFirstRenderModeRepositoryProvider =
    Provider<ThreadDetailHtmlFirstRenderModeRepository>((ref) {
      return const SharedPrefsThreadDetailHtmlFirstRenderModeRepository();
    });

final threadDetailHtmlFirstRenderModeControllerProvider =
    AsyncNotifierProvider<
      ThreadDetailHtmlFirstRenderModeController,
      ThreadDetailHtmlFirstRenderMode
    >(ThreadDetailHtmlFirstRenderModeController.new);

class ThreadDetailHtmlFirstRenderModeController
    extends AsyncNotifier<ThreadDetailHtmlFirstRenderMode> {
  ThreadDetailHtmlFirstRenderModeRepository get _repository =>
      ref.read(threadDetailHtmlFirstRenderModeRepositoryProvider);

  @override
  Future<ThreadDetailHtmlFirstRenderMode> build() {
    return _repository.load();
  }

  Future<void> setMode(ThreadDetailHtmlFirstRenderMode mode) async {
    final previous = state.value ?? ThreadDetailHtmlFirstRenderMode.legacy;
    state = AsyncData(mode);
    try {
      await _repository.save(mode);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setHtmlFirstEnabled(bool enabled) {
    return setMode(
      enabled
          ? ThreadDetailHtmlFirstRenderMode.htmlFirst
          : ThreadDetailHtmlFirstRenderMode.legacy,
    );
  }
}
