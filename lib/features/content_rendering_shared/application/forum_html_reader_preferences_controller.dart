import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/fonts/fonts.dart';
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
  int _fontRequest = 0;
  String? _repairAttempt;
  FontResolution _fontResolution = const FontResolution(
    requestedId: FontIdentity.system,
    font: ResolvedFont.system,
  );

  FontResolution get fontResolution => _fontResolution;

  ForumHtmlReaderPreferenceWriter get _writer => ref.read(_writerProvider);

  @override
  Future<ForumHtmlReaderPreferences> build() async {
    _bound = false;
    _bind();
    final generation = _generation;
    final writer = ref.watch(_writerProvider);
    final preferences = await writer.load();
    final resolution = await _resolveFont(preferences.fontFamily);
    final effective = preferences.copyWith(fontFamily: resolution.font.id);
    if (!_closed && generation == _generation) {
      _fontResolution = resolution;
      _scheduleRepair(resolution);
    }
    return effective;
  }

  void _bind() {
    if (_bound) return;
    _bound = true;
    _closed = false;
    _repairAttempt = null;
    final generation = ++_generation;
    final changes = ref.read(fontLibraryServiceProvider).changes.listen((_) {
      unawaited(_refreshFont());
    });
    ref.onDispose(() {
      if (generation != _generation) return;
      _closed = true;
      _revision++;
      _fontRequest++;
      unawaited(changes.cancel());
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

  Future<void> setFontFamily(String fontId) {
    _finishPreview();
    final current = state.value ?? ForumHtmlReaderPreferences.defaults();
    return _persist(current.copyWith(fontFamily: fontId), replaceFont: true);
  }

  Future<void> reset() {
    _finishPreview(apply: false);
    return _persist(ForumHtmlReaderPreferences.defaults(), replaceFont: true);
  }

  Future<void> _persist(
    ForumHtmlReaderPreferences next, {
    bool replaceFont = false,
  }) async {
    _bind();
    final generation = _generation;
    final revision = ++_revision;
    final fontRequest = ++_fontRequest;
    // Other settings must not turn a temporary runtime fallback into a durable
    // font choice. Only explicit font selection/reset replaces that reference.
    final retainFailedFont =
        !replaceFont &&
        _fontResolution.failure != null &&
        !_isUnavailableFont(_fontResolution.failure) &&
        next.fontFamily == _fontResolution.font.id &&
        _writer.lastSuccessful?.fontFamily == _fontResolution.requestedId;
    final resolution = retainFailedFont
        ? _fontResolution
        : next.fontFamily == _fontResolution.font.id
        ? FontResolution(
            requestedId: next.fontFamily,
            font: _fontResolution.font,
          )
        : await _resolveFont(next.fontFamily);
    if (_closed ||
        generation != _generation ||
        fontRequest != _fontRequest ||
        revision != _revision) {
      return;
    }
    final normalized = next.copyWith(
      typography: _normalize(next.typography),
      fontFamily: resolution.font.id,
    );
    final writer = _writer;
    writer.retainRollbackBaseline(
      state.value ?? ForumHtmlReaderPreferences.defaults(),
    );
    final previous =
        writer.lastSuccessful ?? ForumHtmlReaderPreferences.defaults();
    final resolutionChanged =
        _fontResolution.font != resolution.font ||
        _fontResolution.requestedId != resolution.requestedId ||
        _fontResolution.failure != resolution.failure;
    _fontResolution = resolution;
    if (resolution.failure == null) _repairAttempt = null;
    if (state.value != normalized) {
      state = AsyncData(normalized);
    } else if (resolutionChanged) {
      ref.notifyListeners();
    }
    try {
      await writer.save(
        retainFailedFont
            ? normalized.copyWith(fontFamily: resolution.requestedId)
            : normalized,
      );
    } catch (error, stackTrace) {
      if (!_closed && generation == _generation && revision == _revision) {
        _preview?.cancel();
        _preview = null;
        final rollback = writer.lastSuccessful ?? previous;
        final rollbackResolution = await _resolveFont(rollback.fontFamily);
        if (!_closed && generation == _generation && revision == _revision) {
          _fontResolution = rollbackResolution;
          state = AsyncData(
            rollback.copyWith(fontFamily: rollbackResolution.font.id),
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<FontResolution> _resolveFont(String id) {
    if (id == FontIdentity.system || !ref.mounted) {
      return Future.value(
        const FontResolution(
          requestedId: FontIdentity.system,
          font: ResolvedFont.system,
        ),
      );
    }
    return ref.read(fontLibraryServiceProvider).resolveFont(id);
  }

  Future<void> _refreshFont() async {
    final current = state.value;
    if (_closed || current == null || state.isLoading) return;
    final retained = _writer.lastSuccessful?.fontFamily;
    final id =
        current.fontFamily == FontIdentity.system &&
            _fontResolution.failure != null &&
            retained == _fontResolution.requestedId
        ? _fontResolution.requestedId
        : current.fontFamily;
    if (id == FontIdentity.system) return;
    final generation = _generation;
    final request = _fontRequest;
    final revision = _revision;
    final resolution = await _resolveFont(id);
    if (_closed || generation != _generation) {
      return;
    }
    if (request != _fontRequest || revision != _revision) {
      // Another page may have changed typography during deletion. Recheck its
      // latest snapshot without retiring a newer in-flight font choice.
      unawaited(_refreshFont());
      return;
    }
    final latest = state.value;
    if (latest == null || latest.fontFamily != current.fontFamily) return;
    final next = latest.copyWith(fontFamily: resolution.font.id);
    _fontResolution = resolution;
    if (next != latest || resolution.failure != null) state = AsyncData(next);
    _scheduleRepair(resolution);
  }

  void _scheduleRepair(FontResolution resolution) {
    if (!_isUnavailableFont(resolution.failure)) {
      if (resolution.failure == null) _repairAttempt = null;
      return;
    }
    if (_repairAttempt == resolution.requestedId) return;
    _repairAttempt = resolution.requestedId;
    final generation = _generation;
    // Let AsyncNotifier publish its initial value before attempting repair.
    unawaited(
      Future<void>(() async {
        if (_closed || generation != _generation) {
          return;
        }
        final writer = _writer;
        try {
          await writer.repairFontReference(
            resolution.requestedId,
            isCurrent: () => !_closed && generation == _generation,
          );
        } catch (_) {
          // Keep the readable fallback; a failed write must not start a retry loop.
        }
      }),
    );
  }

  bool _isUnavailableFont(FontLibraryFailure? failure) =>
      failure == FontLibraryFailure.notFound ||
      failure == FontLibraryFailure.invalidFont ||
      failure == FontLibraryFailure.unsupportedFormat;

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
