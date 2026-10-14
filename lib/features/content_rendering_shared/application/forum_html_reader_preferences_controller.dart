import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preferences_repository_provider.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/domain/services/forum_html_reader_preference_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'forum_html_reader_preference_writer.dart';
import 'forum_html_typography_preview.dart';

final _writerProvider = Provider<ForumHtmlReaderPreferenceWriter>((ref) {
  return ForumHtmlReaderPreferenceWriter(
    ref.watch(forumHtmlReaderPreferencesRepositoryProvider),
  );
});

final forumHtmlReaderPreferencesControllerProvider =
    AsyncNotifierProvider<
      ForumHtmlReaderPreferencesController,
      ForumHtmlReaderPreferences
    >(ForumHtmlReaderPreferencesController.new);

class ForumHtmlReaderPreferencesController
    extends AsyncNotifier<ForumHtmlReaderPreferences> {
  ForumHtmlTypographyPreview? _preview;
  int _revision = 0;
  int _generation = 0;
  bool _bound = false;
  bool _closed = false;

  ForumHtmlReaderPreferenceWriter get _writer => ref.read(_writerProvider);

  @override
  Future<ForumHtmlReaderPreferences> build() {
    _bound = false;
    _bind();
    return ref.watch(_writerProvider).load();
  }

  void _bind() {
    if (_bound) return;
    _bound = true;
    _closed = false;
    final generation = ++_generation;
    ref.onDispose(() {
      if (generation != _generation) return;
      _closed = true;
      _revision++;
      _preview?.cancel();
      _preview = null;
    });
  }

  ForumHtmlTypographyPreview beginTypographyPreview({
    required void Function(Object, StackTrace) onError,
  }) {
    _bind();
    _finishPreview();
    _writer.retainRollbackBaseline(
      state.value ?? ForumHtmlReaderPreferences.defaults(),
    );
    final generation = _generation;
    late final ForumHtmlTypographyPreview session;
    bool current() =>
        !_closed && generation == _generation && identical(_preview, session);
    session = ForumHtmlTypographyPreview(
      initialValue:
          (state.value ?? ForumHtmlReaderPreferences.defaults()).typography,
      preview: (typography) {
        if (!current()) return;
        _revision++;
        final value = state.value ?? ForumHtmlReaderPreferences.defaults();
        final next = value.copyWith(typography: _normalize(typography));
        if (value != next) state = AsyncData(next);
      },
      commit: (typography) {
        if (!current()) return Future<void>.value();
        final value = state.value ?? ForumHtmlReaderPreferences.defaults();
        return _persist(value.copyWith(typography: _normalize(typography)));
      },
      onError: onError,
    );
    _preview = session;
    return session;
  }

  void _finishPreview({bool apply = true}) {
    final preview = _preview;
    if (apply) preview?.apply();
    preview?.cancel();
    _preview = null;
  }

  Future<void> setConversionMode(TextConversionMode mode) {
    _finishPreview();
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(conversionMode: mode));
  }

  Future<void> setTypography(RichTextTypography typography) {
    _finishPreview(apply: false);
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(typography: _normalize(typography)));
  }

  Future<void> setFontScale(double value) {
    _finishPreview();
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        fontScale: ForumHtmlReaderPreferencePolicy.clampFontScale(value),
      ),
    );
  }

  Future<void> setLineHeightScale(double value) {
    _finishPreview();
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return setTypography(
      current.typography.copyWith(
        lineHeightScale: ForumHtmlReaderPreferencePolicy.clampLineHeight(value),
      ),
    );
  }

  Future<void> setPreserveAuthorFontSize(bool value) {
    _finishPreview();
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(preserveAuthorFontSize: value));
  }

  Future<void> reset() {
    _finishPreview(apply: false);
    return _persist(ForumHtmlReaderPreferences.defaults());
  }

  Future<void> _persist(ForumHtmlReaderPreferences next) async {
    _bind();
    final generation = _generation;
    final revision = ++_revision;
    final normalized = next.copyWith(typography: _normalize(next.typography));
    final writer = _writer;
    writer.retainRollbackBaseline(
      state.value ?? ForumHtmlReaderPreferences.defaults(),
    );
    final previous =
        writer.lastSuccessful ?? ForumHtmlReaderPreferences.defaults();
    if (state.value != normalized) state = AsyncData(normalized);
    try {
      await writer.save(normalized);
    } catch (error, stackTrace) {
      if (!_closed && generation == _generation && revision == _revision) {
        _preview?.cancel();
        _preview = null;
        state = AsyncData(writer.lastSuccessful ?? previous);
      }
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
