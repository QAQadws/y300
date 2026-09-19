import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';

abstract interface class ThreadQuickScrollPreferencesRepository {
  Future<ThreadQuickScrollDockSide> loadSide();

  Future<void> saveSide(ThreadQuickScrollDockSide side);
}
