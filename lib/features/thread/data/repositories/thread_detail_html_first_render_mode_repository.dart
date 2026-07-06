import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/thread/domain/models/thread_detail_html_first_render_mode.dart';

abstract class ThreadDetailHtmlFirstRenderModeRepository {
  Future<ThreadDetailHtmlFirstRenderMode> load();

  Future<void> save(ThreadDetailHtmlFirstRenderMode mode);
}

class SharedPrefsThreadDetailHtmlFirstRenderModeRepository
    implements ThreadDetailHtmlFirstRenderModeRepository {
  const SharedPrefsThreadDetailHtmlFirstRenderModeRepository();

  @override
  Future<ThreadDetailHtmlFirstRenderMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppStorageKeys.threadDetailHtmlFirstRenderMode);
    for (final mode in ThreadDetailHtmlFirstRenderMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return ThreadDetailHtmlFirstRenderMode.legacy;
  }

  @override
  Future<void> save(ThreadDetailHtmlFirstRenderMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppStorageKeys.threadDetailHtmlFirstRenderMode,
      mode.name,
    );
  }
}
