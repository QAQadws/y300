import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';
import 'package:y300/features/thread/domain/repositories/thread_quick_scroll_preferences_repository.dart';

final class SharedPreferencesThreadQuickScrollRepository
    implements ThreadQuickScrollPreferencesRepository {
  const SharedPreferencesThreadQuickScrollRepository(this._store);

  final PreferencesStore _store;

  @override
  Future<ThreadQuickScrollDockSide> loadSide() async {
    final raw = await _store.read(PreferenceKeys.threadQuickScrollDockSide);
    return raw == ThreadQuickScrollDockSide.left.name
        ? ThreadQuickScrollDockSide.left
        : ThreadQuickScrollDockSide.right;
  }

  @override
  Future<void> saveSide(ThreadQuickScrollDockSide side) =>
      _store.write(PreferenceKeys.threadQuickScrollDockSide, side.name);
}
