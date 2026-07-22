import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/app_update/data/local/shared_prefs_app_release_notes_repository.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';

void main() {
  test(
    'persists notes and attempts across repository reconstruction',
    () async {
      final store = _MemoryPreferencesStore();
      final version = Version.parse('0.0.6');
      final first = SharedPrefsAppReleaseNotesRepository(
        preferencesStore: store,
      );
      await first.recordAttempt(version, DateTime.utc(2026, 7, 22, 1));
      await first.save(
        AppReleaseNotes(
          version: version,
          tag: 'v0.0.6',
          body: 'Persisted notes',
          fetchedAt: DateTime.utc(2026, 7, 22, 2),
        ),
      );

      final reconstructed = SharedPrefsAppReleaseNotesRepository(
        preferencesStore: store,
      );

      expect((await reconstructed.read(version))?.body, 'Persisted notes');
      expect(
        await reconstructed.readLastAttempt(version),
        DateTime.utc(2026, 7, 22, 1),
      );
    },
  );
}

final class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> values = <String, Object>{};

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async {
    return values.containsKey(key.name);
  }

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    return values[key.name] as T?;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    values.remove(key.name);
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    values[key.name] = value;
  }
}
