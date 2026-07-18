import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

@immutable
class ForumHtmlReaderPreferences {
  const ForumHtmlReaderPreferences({
    required this.typography,
    required this.conversionMode,
    this.preserveAuthorFontSize = true,
  });

  factory ForumHtmlReaderPreferences.defaults() =>
      const ForumHtmlReaderPreferences(
        typography: RichTextTypography(
          fontScale: 1.15,
          lineHeightScale: 1.5,
          paragraphSpacing: 12,
        ),
        conversionMode: TextConversionMode.none,
      );

  final RichTextTypography typography;
  final TextConversionMode conversionMode;
  final bool preserveAuthorFontSize;

  ForumHtmlReaderPreferences copyWith({
    RichTextTypography? typography,
    TextConversionMode? conversionMode,
    bool? preserveAuthorFontSize,
  }) {
    return ForumHtmlReaderPreferences(
      typography: typography ?? this.typography,
      conversionMode: conversionMode ?? this.conversionMode,
      preserveAuthorFontSize:
          preserveAuthorFontSize ?? this.preserveAuthorFontSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumHtmlReaderPreferences &&
        typography == other.typography &&
        conversionMode == other.conversionMode &&
        preserveAuthorFontSize == other.preserveAuthorFontSize;
  }

  @override
  int get hashCode =>
      Object.hash(typography, conversionMode, preserveAuthorFontSize);
}

abstract class ForumHtmlReaderPreferencesRepository {
  Future<ForumHtmlReaderPreferences> load();

  Future<void> save(ForumHtmlReaderPreferences preferences);
}

class SharedPrefsForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  SharedPrefsForumHtmlReaderPreferencesRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<ForumHtmlReaderPreferences> load() async {
    final defaults = ForumHtmlReaderPreferences.defaults();
    final defaultTypography = defaults.typography;
    return ForumHtmlReaderPreferences(
      typography: RichTextTypography(
        fontScale: _clampFontScale(
          await _preferencesStore.read(
                PreferenceKeys.forumHtmlReaderFontScale,
              ) ??
              defaultTypography.fontScale,
        ),
        lineHeightScale: _clampLineHeight(
          await _preferencesStore.read(
                PreferenceKeys.forumHtmlReaderLineHeightScale,
              ) ??
              defaultTypography.lineHeightScale,
        ),
        paragraphSpacing: _clampSpacing(
          await _preferencesStore.read(
                PreferenceKeys.forumHtmlReaderParagraphSpacing,
              ) ??
              defaultTypography.paragraphSpacing,
        ),
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
      _clampFontScale(typography.fontScale),
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderLineHeightScale,
      _clampLineHeight(typography.lineHeightScale),
    );
    await _preferencesStore.write(
      PreferenceKeys.forumHtmlReaderParagraphSpacing,
      _clampSpacing(typography.paragraphSpacing),
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

  static double _clampFontScale(double value) =>
      value.clamp(0.7, 2.0).toDouble();

  static double _clampLineHeight(double value) =>
      value.clamp(1.0, 2.5).toDouble();

  static double _clampSpacing(double value) =>
      value.clamp(0.0, 40.0).toDouble();

  static TextConversionMode _parseConversionMode(String? raw) {
    for (final mode in TextConversionMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return TextConversionMode.none;
  }
}

final forumHtmlReaderPreferencesRepositoryProvider =
    Provider<ForumHtmlReaderPreferencesRepository>(
      (ref) => SharedPrefsForumHtmlReaderPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      ),
    );

final forumHtmlReaderPreferencesControllerProvider =
    AsyncNotifierProvider<
      ForumHtmlReaderPreferencesController,
      ForumHtmlReaderPreferences
    >(ForumHtmlReaderPreferencesController.new);

class ForumHtmlReaderPreferencesController
    extends AsyncNotifier<ForumHtmlReaderPreferences> {
  ForumHtmlReaderPreferencesRepository get _repository =>
      ref.read(forumHtmlReaderPreferencesRepositoryProvider);

  @override
  Future<ForumHtmlReaderPreferences> build() {
    return _repository.load();
  }

  Future<void> setConversionMode(TextConversionMode mode) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(conversionMode: mode));
  }

  Future<void> setTypography(RichTextTypography typography) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(typography: _normalize(typography)));
  }

  Future<void> setFontScale(double value) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        fontScale:
            SharedPrefsForumHtmlReaderPreferencesRepository._clampFontScale(
              value,
            ),
      ),
    );
  }

  Future<void> setLineHeightScale(double value) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        lineHeightScale:
            SharedPrefsForumHtmlReaderPreferencesRepository._clampLineHeight(
              value,
            ),
      ),
    );
  }

  Future<void> setParagraphSpacing(double value) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        paragraphSpacing:
            SharedPrefsForumHtmlReaderPreferencesRepository._clampSpacing(
              value,
            ),
      ),
    );
  }

  Future<void> setPreserveAuthorFontSize(bool value) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(preserveAuthorFontSize: value));
  }

  Future<void> reset() {
    return _persist(ForumHtmlReaderPreferences.defaults());
  }

  Future<void> _persist(ForumHtmlReaderPreferences next) async {
    final normalized = next.copyWith(typography: _normalize(next.typography));
    state = AsyncData(normalized);
    await _repository.save(normalized);
  }

  RichTextTypography _normalize(RichTextTypography typography) {
    return RichTextTypography(
      fontScale:
          SharedPrefsForumHtmlReaderPreferencesRepository._clampFontScale(
            typography.fontScale,
          ),
      lineHeightScale:
          SharedPrefsForumHtmlReaderPreferencesRepository._clampLineHeight(
            typography.lineHeightScale,
          ),
      paragraphSpacing:
          SharedPrefsForumHtmlReaderPreferencesRepository._clampSpacing(
            typography.paragraphSpacing,
          ),
    );
  }
}
