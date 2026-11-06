import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

abstract interface class NovelReaderPreferencesRepository {
  Future<NovelReaderPreferences> load();

  Future<void> save(NovelReaderPreferences preferences);
}

enum NovelReaderPreferenceScope { defaults, work }

/// Immutable loaded values for one work. A defaults preview must keep that
/// work's explicit overrides without performing another storage read.
abstract interface class NovelReaderPreferenceScopes {
  NovelReaderPreferences get defaults;
  NovelReaderPreferences get effective;
  bool get hasWorkOverrides;
  bool get canEditWork;
  NovelReaderPreferenceScope get fontFamilyScope;
  NovelReaderPreferenceScope get flowModeScope;

  NovelReaderPreferences previewDefaults(NovelReaderPreferences draft);

  NovelReaderPreferences previewEdit(
    NovelReaderPreferenceScope scope,
    NovelReaderPreferences previous,
    NovelReaderPreferences draft,
  );
}

abstract interface class NovelReaderScopedPreferencesRepository
    implements NovelReaderPreferencesRepository {
  Future<NovelReaderPreferenceScopes> loadScopes(String novelId);

  /// Only fields changed from the editor's baseline are applied to the
  /// current stored scope. The write uses the work identity supplied here.
  Future<NovelReaderPreferenceScopes> saveScope(
    String novelId, {
    required NovelReaderPreferenceScope scope,
    required NovelReaderPreferences previous,
    required NovelReaderPreferences next,
  });

  Future<NovelReaderPreferenceScopes> resetWork(String novelId);

  Future<NovelReaderPreferenceScopes> applyPreset(
    String novelId, {
    required NovelReaderPreferenceScope scope,
    required NovelReaderPreferences preferences,
    required bool keepCurrentFont,
  });

  /// Compare against storage inside the write queue so a repair cannot replace
  /// a font chosen by another reader since this owner loaded.
  Future<NovelReaderPreferenceScopes?> repairFontReference(
    String novelId, {
    required NovelReaderPreferenceScope scope,
    required String unavailableId,
  });
}

/// The running version cannot safely edit this stored preference format.
/// No serialized payload is carried through the failure/UI boundary.
final class NovelReaderPreferencesUnsupportedSnapshot implements Exception {
  const NovelReaderPreferencesUnsupportedSnapshot();

  @override
  String toString() => 'NovelReaderPreferencesUnsupportedSnapshot';
}
