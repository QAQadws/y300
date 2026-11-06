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

  NovelReaderPreferences previewDefaults(NovelReaderPreferences draft);
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
}

/// The running version cannot safely edit this stored preference format.
/// No serialized payload is carried through the failure/UI boundary.
final class NovelReaderPreferencesUnsupportedSnapshot implements Exception {
  const NovelReaderPreferencesUnsupportedSnapshot();

  @override
  String toString() => 'NovelReaderPreferencesUnsupportedSnapshot';
}
