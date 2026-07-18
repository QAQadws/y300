import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/config/app_storage_keys.dart';

void main() {
  test('phase-0 SharedPreferences keys remain stable', () {
    expect(AppStorageKeys.legacyComicCacheDirectory, 'comic_cache_dir');
    expect(AppStorageKeys.comicCacheDirectory, 'comic_cache_dir');
    expect(AppStorageKeys.imageCacheMaxBytes, 'image_cache_max_bytes');
    expect(AppStorageKeys.imageCacheCustomDirectory, 'image_cache_custom_dir');
    expect(AppStorageKeys.downloadStorageDirectory, 'download_storage_dir');
    expect(AppStorageKeys.appThemePreference, 'app_theme_preference');
    expect(AppStorageKeys.forumShellMode, 'forum_shell_mode');
    expect(
      AppStorageKeys.syncDiagnosticManualMode,
      'sync_diagnostic_manual_mode',
    );
    expect(
      AppStorageKeys.threadDetailScrollDiagnosticEnabled,
      'thread_detail_scroll_diagnostic_enabled',
    );
    expect(
      AppStorageKeys.threadDetailHtmlFirstRenderMode,
      'thread_detail_html_first_render_mode',
    );
    expect(
      AppStorageKeys.replyStickerLastGroupId,
      'reply_sticker_last_group_id',
    );
  });
}
