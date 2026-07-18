import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';

abstract interface class LibraryViewPreferencesRepository {
  Future<LibraryShelfViewPreferences> load({
    required LibraryShelfViewPreferences defaults,
  });

  Future<void> save(LibraryShelfViewPreferences preferences);
}

/// Process-local fallback for isolated controller/widget hosts.
///
/// Application module pages inject the persistent implementation. Keeping a
/// small volatile implementation makes the shared presentation layer usable
/// in previews and focused tests without coupling it to Riverpod or storage.
final class VolatileLibraryViewPreferencesRepository
    implements LibraryViewPreferencesRepository {
  final Map<Object, LibraryShelfViewPreferences> _values =
      <Object, LibraryShelfViewPreferences>{};

  @override
  Future<LibraryShelfViewPreferences> load({
    required LibraryShelfViewPreferences defaults,
  }) async {
    return _values[defaults.moduleKey] ?? defaults;
  }

  @override
  Future<void> save(LibraryShelfViewPreferences preferences) async {
    _values[preferences.moduleKey] = preferences;
  }
}
