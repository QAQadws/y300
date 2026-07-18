import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/core/preferences/preference_keys.dart';

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

  test('typed registry owns scalar, legacy, and snapshot names', () {
    expect(PreferenceKeys.appThemePreference.name, 'app_theme_preference');
    expect(PreferenceKeys.forumShellMode.name, 'forum_shell_mode');
    expect(PreferenceKeys.imageReaderSnapshotV1.name, 'reader.image.v1');
    expect(
      PreferenceKeys.libraryShelfComicSnapshotV1.name,
      'library.shelf.comic.v1',
    );
    expect(
      PreferenceKeys.libraryShelfNovelSnapshotV1.name,
      'library.shelf.novel.v1',
    );
    expect(
      PreferenceKeys.libraryShelfFavoriteSnapshotV1.name,
      'library.shelf.favorite.v1',
    );
    expect(PreferenceKeys.legacyImageReaderMode.name, 'reader_pref_mode');
    expect(
      PreferenceKeys.forumHtmlReaderFontScale.name,
      'forum_html_reader_font_scale',
    );
    expect(
      PreferenceKeys.legacyThreadTextFontScale.name,
      'thread_text_font_scale',
    );
  });
}
