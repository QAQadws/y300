import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';

final class SharedPreferencesNovelReaderPreferencesRepository
    implements NovelReaderPreferencesRepository {
  SharedPreferencesNovelReaderPreferencesRepository({
    required PreferencesStore preferencesStore,
    required NovelReaderPreferencesLegacySource legacySource,
    NovelReaderPreferencesSnapshotCodec codec =
        const NovelReaderPreferencesSnapshotCodec(),
  }) : _preferencesStore = preferencesStore,
       _legacySource = legacySource,
       _codec = codec;

  static const int migrationVersion = 1;

  final PreferencesStore _preferencesStore;
  final NovelReaderPreferencesLegacySource _legacySource;
  final NovelReaderPreferencesSnapshotCodec _codec;

  @override
  Future<NovelReaderPreferences> load() async {
    if (await _preferencesStore.contains(
      PreferenceKeys.novelReaderSnapshotV1,
    )) {
      return _codec.decode(
        await _preferencesStore.read(PreferenceKeys.novelReaderSnapshotV1),
      );
    }

    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.novelReaderMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return NovelReaderPreferences.defaults();
    }

    NovelReaderPreferences? legacy;
    try {
      legacy = await _legacySource.load();
    } catch (_) {
      legacy = null;
    }
    final migrated = _codec.normalize(
      legacy ?? NovelReaderPreferences.defaults(),
    );
    await _write(migrated);
    return migrated;
  }

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    await _write(_codec.normalize(preferences));
  }

  Future<void> _write(NovelReaderPreferences preferences) async {
    await _preferencesStore.write(
      PreferenceKeys.novelReaderSnapshotV1,
      _codec.encode(preferences),
    );
    await _preferencesStore.write(
      PreferenceKeys.novelReaderMigrationVersion,
      migrationVersion,
    );
  }
}
