import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_interaction_preferences_legacy_source.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_interaction_preferences_repository.dart';

final class SharedPreferencesNovelInteractionPreferencesRepository
    implements NovelInteractionPreferencesRepository {
  SharedPreferencesNovelInteractionPreferencesRepository({
    required PreferencesStore preferencesStore,
    required NovelInteractionPreferencesLegacySource legacySource,
  }) : _preferencesStore = preferencesStore,
       _legacySource = legacySource;

  static const int migrationVersion = 1;

  final PreferencesStore _preferencesStore;
  final NovelInteractionPreferencesLegacySource _legacySource;

  @override
  Future<NovelChapterOpenMode> loadChapterOpenMode() async {
    if (await _preferencesStore.contains(
      PreferenceKeys.novelChapterOpenModeV1,
    )) {
      return NovelChapterOpenModeCodec.fromStorage(
        await _preferencesStore.read(PreferenceKeys.novelChapterOpenModeV1),
      );
    }

    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.novelChapterOpenModeMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return NovelChapterOpenMode.reader;
    }

    NovelChapterOpenMode? legacy;
    try {
      legacy = await _legacySource.loadChapterOpenMode();
    } on Exception {
      legacy = null;
    }
    final migrated = legacy ?? NovelChapterOpenMode.reader;
    await _write(migrated);
    return migrated;
  }

  @override
  Future<void> saveChapterOpenMode(NovelChapterOpenMode mode) async {
    await _write(mode);
  }

  Future<void> _write(NovelChapterOpenMode mode) async {
    await _preferencesStore.write(
      PreferenceKeys.novelChapterOpenModeV1,
      mode.storageValue,
    );
    await _preferencesStore.write(
      PreferenceKeys.novelChapterOpenModeMigrationVersion,
      migrationVersion,
    );
  }
}
