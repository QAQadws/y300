import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_key_names.dart';

/// Canonical registry for fixed-size device preference keys.
///
/// Existing scalar names remain unchanged for compatibility. New multi-field
/// snapshots use a domain-scoped, versioned name.
abstract final class PreferenceKeys {
  static const appThemePreference = PreferenceKey<String>(
    PreferenceKeyNames.appThemePreference,
  );
  static const forumShellMode = PreferenceKey<String>(
    PreferenceKeyNames.forumShellMode,
  );

  static const forumHtmlReaderFontScale = PreferenceKey<double>(
    PreferenceKeyNames.forumHtmlReaderFontScale,
  );
  static const forumHtmlReaderLineHeightScale = PreferenceKey<double>(
    PreferenceKeyNames.forumHtmlReaderLineHeightScale,
  );
  static const forumHtmlReaderConversionMode = PreferenceKey<String>(
    PreferenceKeyNames.forumHtmlReaderConversionMode,
  );
  static const forumHtmlReaderPreserveAuthorFontSize = PreferenceKey<bool>(
    PreferenceKeyNames.forumHtmlReaderPreserveAuthorFontSize,
  );
  static const forumHtmlReaderMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.forumHtmlReaderMigrationVersion,
  );

  static const imageReaderSnapshotV1 = PreferenceKey<String>(
    PreferenceKeyNames.imageReaderSnapshotV1,
  );
  static const legacyImageReaderMode = PreferenceKey<String>(
    PreferenceKeyNames.legacyImageReaderMode,
  );
  static const legacyImageReaderPageFit = PreferenceKey<String>(
    PreferenceKeyNames.legacyImageReaderPageFit,
  );
  static const legacyImageReaderBackground = PreferenceKey<String>(
    PreferenceKeyNames.legacyImageReaderBackground,
  );
  static const legacyImageReaderPageSpacing = PreferenceKey<double>(
    PreferenceKeyNames.legacyImageReaderPageSpacing,
  );
  static const legacyImageReaderShowPageIndicator = PreferenceKey<bool>(
    PreferenceKeyNames.legacyImageReaderShowPageIndicator,
  );

  static const novelReaderSnapshotV1 = PreferenceKey<String>(
    PreferenceKeyNames.novelReaderSnapshotV1,
  );
  static const novelReaderMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.novelReaderMigrationVersion,
  );
  static const novelChapterOpenModeV1 = PreferenceKey<String>(
    PreferenceKeyNames.novelChapterOpenModeV1,
  );
  static const novelChapterOpenModeMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.novelChapterOpenModeMigrationVersion,
  );

  static const libraryShelfComicSnapshotV1 = PreferenceKey<String>(
    PreferenceKeyNames.libraryShelfComicSnapshotV1,
  );
  static const libraryShelfNovelSnapshotV1 = PreferenceKey<String>(
    PreferenceKeyNames.libraryShelfNovelSnapshotV1,
  );
  static const libraryShelfFavoriteSnapshotV1 = PreferenceKey<String>(
    PreferenceKeyNames.libraryShelfFavoriteSnapshotV1,
  );
  static const libraryShelfComicMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.libraryShelfComicMigrationVersion,
  );
  static const libraryShelfNovelMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.libraryShelfNovelMigrationVersion,
  );
  static const libraryShelfFavoriteMigrationVersion = PreferenceKey<int>(
    PreferenceKeyNames.libraryShelfFavoriteMigrationVersion,
  );

  static const imageCacheMaxBytes = PreferenceKey<int>(
    PreferenceKeyNames.imageCacheMaxBytes,
  );
  static const imageCacheCustomDirectory = PreferenceKey<String>(
    PreferenceKeyNames.imageCacheCustomDirectory,
  );
  static const legacyComicCacheDirectory = PreferenceKey<String>(
    PreferenceKeyNames.legacyComicCacheDirectory,
  );
  static const downloadStorageDirectory = PreferenceKey<String>(
    PreferenceKeyNames.downloadStorageDirectory,
  );

  static const replyStickerLastGroupId = PreferenceKey<String>(
    PreferenceKeyNames.replyStickerLastGroupId,
  );
  static const syncDiagnosticManualMode = PreferenceKey<bool>(
    PreferenceKeyNames.syncDiagnosticManualMode,
  );
  static const threadDetailScrollDiagnosticEnabled = PreferenceKey<bool>(
    PreferenceKeyNames.threadDetailScrollDiagnosticEnabled,
  );

  static const legacyThreadTextFontScale = PreferenceKey<double>(
    PreferenceKeyNames.legacyThreadTextFontScale,
  );
  static const legacyThreadTextLineHeightScale = PreferenceKey<double>(
    PreferenceKeyNames.legacyThreadTextLineHeightScale,
  );
}
