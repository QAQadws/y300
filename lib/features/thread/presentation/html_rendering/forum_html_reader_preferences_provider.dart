import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        typography: RichTextTypography.standard,
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
  static const _fontScaleKey = 'forum_html_reader_font_scale';
  static const _lineHeightScaleKey = 'forum_html_reader_line_height_scale';
  static const _paragraphSpacingKey = 'forum_html_reader_paragraph_spacing';
  static const _conversionModeKey = 'forum_html_reader_conversion_mode';
  static const _preserveFontSizeKey =
      'forum_html_reader_preserve_author_font_size';

  @override
  Future<ForumHtmlReaderPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    const std = RichTextTypography.standard;
    return ForumHtmlReaderPreferences(
      typography: RichTextTypography(
        fontScale: _clampFontScale(
          prefs.getDouble(_fontScaleKey) ?? std.fontScale,
        ),
        lineHeightScale: _clampLineHeight(
          prefs.getDouble(_lineHeightScaleKey) ?? std.lineHeightScale,
        ),
        paragraphSpacing: _clampSpacing(
          prefs.getDouble(_paragraphSpacingKey) ?? std.paragraphSpacing,
        ),
      ),
      conversionMode: _parseConversionMode(prefs.getString(_conversionModeKey)),
      preserveAuthorFontSize: prefs.getBool(_preserveFontSizeKey) ?? true,
    );
  }

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    final typography = preferences.typography;
    await prefs.setDouble(_fontScaleKey, _clampFontScale(typography.fontScale));
    await prefs.setDouble(
      _lineHeightScaleKey,
      _clampLineHeight(typography.lineHeightScale),
    );
    await prefs.setDouble(
      _paragraphSpacingKey,
      _clampSpacing(typography.paragraphSpacing),
    );
    await prefs.setString(_conversionModeKey, preferences.conversionMode.name);
    await prefs.setBool(
      _preserveFontSizeKey,
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
      (ref) => SharedPrefsForumHtmlReaderPreferencesRepository(),
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
