import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preference_keys.dart';

void main() {
  test('active SharedPreferences compatibility aliases remain stable', () {
    expect(AppStorageKeys.imageCacheMaxBytes, 'image_cache_max_bytes');
    expect(AppStorageKeys.cacheMaxBytesV1, 'storage.cache.max_bytes.v1');
    expect(AppStorageKeys.downloadStorageDirectory, 'download_storage_dir');
    expect(AppStorageKeys.appThemePreference, 'app_theme_preference');
    expect(AppStorageKeys.forumShellMode, 'forum_shell_mode');
    expect(
      AppStorageKeys.replyStickerLastGroupId,
      'reply_sticker_last_group_id',
    );
  });

  test('runtime credentials and rate limits use technical storage keys', () {
    expect(TechnicalStorageKeys.networkCookiesV1, 'network.cookies.v1');
    expect(
      TechnicalStorageKeys.searchLastSearchAtMs,
      'search.last_search_at_ms',
    );
  });

  test('typed registry owns scalar, legacy, and snapshot names', () {
    expect(PreferenceKeys.appThemeFamily.name, 'app_theme_family');
    expect(PreferenceKeys.appThemePreference.name, 'app_theme_preference');
    expect(
      PreferenceKeys.appNavigationSnapshotV1.name,
      'app.navigation.snapshot.v1',
    );
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
    expect(
      PreferenceKeys.forumHtmlReaderMigrationVersion.name,
      'forum_html_reader_migration_version',
    );
    expect(
      PreferenceKeys.composerDefaultsSnapshotV1.name,
      'composer.defaults.v1',
    );
    expect(
      PreferenceKeys.composerDraftMigrationVersion.name,
      'composer.drafts.migration_version',
    );
    expect(
      PreferenceKeys.legacyCacheRootMigrationVersion.name,
      'storage.cache_root.migration_version',
    );
  });
}
