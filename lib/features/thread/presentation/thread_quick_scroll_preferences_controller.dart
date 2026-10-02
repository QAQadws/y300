import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/data/providers/thread_quick_scroll_preferences_providers.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';

final threadQuickScrollPreferencesControllerProvider =
    AsyncNotifierProvider<
      ThreadQuickScrollPreferencesController,
      ThreadQuickScrollDockSide
    >(ThreadQuickScrollPreferencesController.new);

final class ThreadQuickScrollPreferencesController
    extends AsyncNotifier<ThreadQuickScrollDockSide> {
  Future<void> _writes = Future<void>.value();
  ThreadQuickScrollDockSide _savedSide = ThreadQuickScrollDockSide.right;
  int _revision = 0;

  @override
  Future<ThreadQuickScrollDockSide> build() async {
    final repository = ref.watch(
      threadQuickScrollPreferencesRepositoryProvider,
    );
    try {
      return _savedSide = await repository.loadSide();
    } on Object {
      return _savedSide = ThreadQuickScrollDockSide.right;
    }
  }

  /// Returns false only when the latest choice failed and was rolled back.
  Future<bool> setSide(ThreadQuickScrollDockSide side) {
    if (state.value == null || state.value == side) {
      return Future<bool>.value(true);
    }
    final repository = ref.read(threadQuickScrollPreferencesRepositoryProvider);
    final revision = ++_revision;
    state = AsyncData(side);

    // Serial writes protect the stored value too, not just the optimistic UI.
    final result = _writes.then((_) async {
      try {
        await repository.saveSide(side);
        _savedSide = side;
        return true;
      } on Object {
        if (ref.mounted && revision == _revision) {
          state = AsyncData(_savedSide);
          return false;
        }
        return true;
      }
    });
    _writes = result.then<void>((_) {});
    return result;
  }
}
