import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/composer_shared/data/preferences/composer_preferences_snapshot_codec.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';

class SharedPreferencesComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  SharedPreferencesComposerPreferencesRepository({
    required PreferencesStore preferencesStore,
    ComposerPreferencesSnapshotCodec codec =
        const ComposerPreferencesSnapshotCodec(),
  }) : _preferencesStore = preferencesStore,
       _codec = codec;

  final PreferencesStore _preferencesStore;
  final ComposerPreferencesSnapshotCodec _codec;

  @override
  Future<ComposerPreferences> load() async {
    return _codec.decode(
      await _preferencesStore.read(PreferenceKeys.composerDefaultsSnapshotV1),
    );
  }

  @override
  Future<void> save(ComposerPreferences preferences) {
    return _preferencesStore.write(
      PreferenceKeys.composerDefaultsSnapshotV1,
      _codec.encode(preferences),
    );
  }
}
