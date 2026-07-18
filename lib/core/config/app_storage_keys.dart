import 'package:y300/core/preferences/preference_key_names.dart';

/// Shared storage keys used across features.
///
/// Compatibility aliases for code that has not moved to typed preference keys.
/// New preference repositories should use the typed preference registry.
abstract final class AppStorageKeys {
  static const String legacyComicCacheDirectory =
      PreferenceKeyNames.legacyComicCacheDirectory;
  static const String comicCacheDirectory = legacyComicCacheDirectory;
  static const String imageCacheMaxBytes =
      PreferenceKeyNames.imageCacheMaxBytes;
  static const String imageCacheCustomDirectory =
      PreferenceKeyNames.imageCacheCustomDirectory;
  static const String downloadStorageDirectory =
      PreferenceKeyNames.downloadStorageDirectory;
  static const String appThemePreference =
      PreferenceKeyNames.appThemePreference;
  static const String forumShellMode = PreferenceKeyNames.forumShellMode;
  static const String syncDiagnosticManualMode =
      PreferenceKeyNames.syncDiagnosticManualMode;
  static const String threadDetailScrollDiagnosticEnabled =
      PreferenceKeyNames.threadDetailScrollDiagnosticEnabled;
  static const String replyStickerLastGroupId =
      PreferenceKeyNames.replyStickerLastGroupId;
}
