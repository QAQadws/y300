import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

/// Persisted typography preferences for thread post body rendering.
@immutable
class ThreadTextPreferences {
  const ThreadTextPreferences({
    required this.typography,
  });

  factory ThreadTextPreferences.defaults() => const ThreadTextPreferences(
    typography: RichTextTypography.standard,
  );

  final RichTextTypography typography;

  ThreadTextPreferences copyWith({RichTextTypography? typography}) =>
      ThreadTextPreferences(typography: typography ?? this.typography);
}

// ── Repository ────────────────────────────────────────────────────────────────

abstract class ThreadTextPreferencesRepository {
  Future<ThreadTextPreferences> load();
  Future<void> save(ThreadTextPreferences prefs);
}

class SharedPrefsThreadTextPreferencesRepository
    implements ThreadTextPreferencesRepository {
  static const _fontScaleKey = 'thread_text_font_scale';
  static const _lineHeightScaleKey = 'thread_text_line_height_scale';
  static const _paragraphSpacingKey = 'thread_text_paragraph_spacing';

  @override
  Future<ThreadTextPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    const std = RichTextTypography.standard;
    return ThreadTextPreferences(
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
    );
  }

  @override
  Future<void> save(ThreadTextPreferences prefs) async {
    final p = await SharedPreferences.getInstance();
    final t = prefs.typography;
    await p.setDouble(_fontScaleKey, _clampFontScale(t.fontScale));
    await p.setDouble(_lineHeightScaleKey, _clampLineHeight(t.lineHeightScale));
    await p.setDouble(_paragraphSpacingKey, _clampSpacing(t.paragraphSpacing));
  }

  static double _clampFontScale(double v) => v.clamp(0.7, 2.0);
  static double _clampLineHeight(double v) => v.clamp(1.0, 2.5);
  static double _clampSpacing(double v) => v.clamp(0.0, 40.0);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final threadTextPreferencesRepositoryProvider =
    Provider<ThreadTextPreferencesRepository>(
      (_) => SharedPrefsThreadTextPreferencesRepository(),
    );

final threadTextPreferencesControllerProvider = AsyncNotifierProvider<
  ThreadTextPreferencesController,
  ThreadTextPreferences
>(ThreadTextPreferencesController.new);

class ThreadTextPreferencesController
    extends AsyncNotifier<ThreadTextPreferences> {
  ThreadTextPreferencesRepository get _repo =>
      ref.read(threadTextPreferencesRepositoryProvider);

  @override
  Future<ThreadTextPreferences> build() => _repo.load();

  Future<void> setTypography(RichTextTypography typography) =>
      _persist(state.value!.copyWith(typography: typography));

  Future<void> setFontScale(double value) => setTypography(
    (state.value ?? ThreadTextPreferences.defaults()).typography.copyWith(
      fontScale: value,
    ),
  );

  Future<void> setLineHeightScale(double value) => setTypography(
    (state.value ?? ThreadTextPreferences.defaults()).typography.copyWith(
      lineHeightScale: value,
    ),
  );

  Future<void> setParagraphSpacing(double value) => setTypography(
    (state.value ?? ThreadTextPreferences.defaults()).typography.copyWith(
      paragraphSpacing: value,
    ),
  );

  Future<void> _persist(ThreadTextPreferences next) async {
    state = AsyncData(next);
    await _repo.save(next);
  }
}
