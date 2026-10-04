import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/domain/repositories/forum_html_reader_preferences_repository.dart';
import 'package:y300/features/content_rendering_shared/domain/services/forum_html_reader_preference_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

class SharedPrefsForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  SharedPrefsForumHtmlReaderPreferencesRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  static const int migrationVersion = 1;

  @override
  Future<ForumHtmlReaderPreferences> load() async {
    await _migrateLegacyTypographyIfNeeded();
    final defaults = ForumHtmlReaderPreferences.defaults();
    final defaultTypography = defaults.typography;
    return ForumHtmlReaderPreferences(
      typography: RichTextTypography(
        fontScale: ForumHtmlReaderPreferencePolicy.clampFontScale(
          await _preferencesStore.read(
                PreferenceKeys.forumHtmlReaderFontScale,
              ) ??
              defaultTypography.fontScale,
        ),
        lineHeightScale: ForumHtmlReaderPreferencePolicy.clampLineHeight(
          await _preferencesStore.read(
                PreferenceKeys.forumHtmlReaderLineHeightScale,
              ) ??
              defaultTypography.lineHeightScale,
        ),
        paragraphSpacing: ForumHtmlReaderPreferences.defaultParagraphSpacing,
      ),
      conversionMode: _parseConversionMode(
        await _preferencesStore.read(
          PreferenceKeys.forumHtmlReaderConversionMode,
        ),
      ),
      preserveAuthorFontSize:
          await _preferencesStore.read(
            PreferenceKeys.forumHtmlReaderPreserveAuthorFontSize,
          ) ??
          defaults.preserveAuthorFontSize,
    );
  }

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    final typography = preferences.typography;
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderFontScale,
      ForumHtmlReaderPreferencePolicy.clampFontScale(typography.fontScale),
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderLineHeightScale,
      ForumHtmlReaderPreferencePolicy.clampLineHeight(
        typography.lineHeightScale,
      ),
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderConversionMode,
      preferences.conversionMode.name,
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderPreserveAuthorFontSize,
      preferences.preserveAuthorFontSize,
    );
  }

  Future<void> _migrateLegacyTypographyIfNeeded() async {
    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.forumHtmlReaderMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return;
    }

    await _migrateLegacyDouble(
      target: PreferenceKeys.forumHtmlReaderFontScale,
      legacy: PreferenceKeys.legacyThreadTextFontScale,
      normalize: ForumHtmlReaderPreferencePolicy.clampFontScale,
    );
    await _migrateLegacyDouble(
      target: PreferenceKeys.forumHtmlReaderLineHeightScale,
      legacy: PreferenceKeys.legacyThreadTextLineHeightScale,
      normalize: ForumHtmlReaderPreferencePolicy.clampLineHeight,
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderMigrationVersion,
      migrationVersion,
    );
  }

  Future<void> _migrateLegacyDouble({
    required PreferenceKey<double> target,
    required PreferenceKey<double> legacy,
    required double Function(double value) normalize,
  }) async {
    if (await _preferencesStore.contains(target)) {
      return;
    }
    final legacyValue = await _preferencesStore.read(legacy);
    if (legacyValue == null) {
      return;
    }
    await _preferencesStore.write(target, normalize(legacyValue));
  }

  static TextConversionMode _parseConversionMode(String? raw) {
    for (final mode in TextConversionMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return TextConversionMode.none;
  }
}
