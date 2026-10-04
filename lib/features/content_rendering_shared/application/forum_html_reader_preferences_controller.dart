import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preferences_repository_provider.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/domain/repositories/forum_html_reader_preferences_repository.dart';
import 'package:y300/features/content_rendering_shared/domain/services/forum_html_reader_preference_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

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
        fontScale: ForumHtmlReaderPreferencePolicy.clampFontScale(value),
      ),
    );
  }

  Future<void> setLineHeightScale(double value) {
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        lineHeightScale: ForumHtmlReaderPreferencePolicy.clampLineHeight(value),
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
    final previous = state.value ?? ForumHtmlReaderPreferences.defaults();
    state = AsyncData(normalized);
    try {
      await _repository.save(normalized);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RichTextTypography _normalize(RichTextTypography typography) {
    return RichTextTypography(
      fontScale: ForumHtmlReaderPreferencePolicy.clampFontScale(
        typography.fontScale,
      ),
      lineHeightScale: ForumHtmlReaderPreferencePolicy.clampLineHeight(
        typography.lineHeightScale,
      ),
      paragraphSpacing: ForumHtmlReaderPreferences.defaultParagraphSpacing,
    );
  }
}
