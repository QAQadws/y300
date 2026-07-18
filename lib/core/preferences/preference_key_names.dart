/// Raw names behind the typed preference registry and compatibility aliases.
abstract final class PreferenceKeyNames {
  static const appThemePreference = 'app_theme_preference';
  static const forumShellMode = 'forum_shell_mode';

  static const forumHtmlReaderFontScale = 'forum_html_reader_font_scale';
  static const forumHtmlReaderLineHeightScale =
      'forum_html_reader_line_height_scale';
  static const forumHtmlReaderConversionMode =
      'forum_html_reader_conversion_mode';
  static const forumHtmlReaderPreserveAuthorFontSize =
      'forum_html_reader_preserve_author_font_size';
  static const forumHtmlReaderMigrationVersion =
      'forum_html_reader_migration_version';

  static const imageReaderSnapshotV1 = 'reader.image.v1';
  static const legacyImageReaderMode = 'reader_pref_mode';
  static const legacyImageReaderPageFit = 'reader_pref_page_fit';
  static const legacyImageReaderBackground = 'reader_pref_background';
  static const legacyImageReaderPageSpacing = 'reader_pref_page_spacing';
  static const legacyImageReaderShowPageIndicator =
      'reader_pref_show_page_indicator';

  static const novelReaderSnapshotV1 = 'reader.novel.v1';
  static const novelReaderMigrationVersion = 'reader.novel.migration_version';
  static const novelChapterOpenModeV1 = 'novel.chapter_open_mode.v1';
  static const novelChapterOpenModeMigrationVersion =
      'novel.chapter_open_mode.migration_version';

  static const composerDefaultsSnapshotV1 = 'composer.defaults.v1';
  static const composerDraftMigrationVersion =
      'composer.drafts.migration_version';

  static const libraryShelfComicSnapshotV1 = 'library.shelf.comic.v1';
  static const libraryShelfNovelSnapshotV1 = 'library.shelf.novel.v1';
  static const libraryShelfFavoriteSnapshotV1 = 'library.shelf.favorite.v1';
  static const libraryShelfComicMigrationVersion =
      'library.shelf.comic.migration_version';
  static const libraryShelfNovelMigrationVersion =
      'library.shelf.novel.migration_version';
  static const libraryShelfFavoriteMigrationVersion =
      'library.shelf.favorite.migration_version';

  static const imageCacheMaxBytes = 'image_cache_max_bytes';
  static const imageCacheCustomDirectory = 'image_cache_custom_dir';
  static const legacyComicCacheDirectory = 'comic_cache_dir';
  static const downloadStorageDirectory = 'download_storage_dir';

  static const replyStickerLastGroupId = 'reply_sticker_last_group_id';
  static const syncDiagnosticManualMode = 'sync_diagnostic_manual_mode';
  static const threadDetailScrollDiagnosticEnabled =
      'thread_detail_scroll_diagnostic_enabled';

  static const legacyThreadTextFontScale = 'thread_text_font_scale';
  static const legacyThreadTextLineHeightScale =
      'thread_text_line_height_scale';
}
