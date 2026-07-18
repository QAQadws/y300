import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/composer_shared/data/preferences/composer_draft_legacy_store.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

class MigratingComposerDraftRepository implements ComposerDraftRepository {
  MigratingComposerDraftRepository({
    required ComposerDraftRepository target,
    required ComposerDraftLegacyStore legacyStore,
    required PreferencesStore preferencesStore,
    ComposerDraftSnapshotJsonCodec codec =
        const ComposerDraftSnapshotJsonCodec(),
  }) : _target = target,
       _legacyStore = legacyStore,
       _preferencesStore = preferencesStore,
       _codec = codec;

  static const int migrationVersion = 1;

  final ComposerDraftRepository _target;
  final ComposerDraftLegacyStore _legacyStore;
  final PreferencesStore _preferencesStore;
  final ComposerDraftSnapshotJsonCodec _codec;
  Future<void>? _migration;

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    await _ensureMigrated();
    return _target.loadDraft(identity);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    await _ensureMigrated();
    await _target.saveDraft(draft);
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    await _ensureMigrated();
    await _target.deleteDraft(identity);
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    await _ensureMigrated();
    return _target.pruneDrafts(maxAge: maxAge, maxCount: maxCount);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    await _ensureMigrated();
    return _target.listDraftsForThread(fid: fid, tid: tid);
  }

  Future<void> _ensureMigrated() async {
    final existing = _migration;
    if (existing != null) {
      return existing;
    }
    final operation = _migrate();
    _migration = operation;
    try {
      await operation;
    } catch (_) {
      if (identical(_migration, operation)) {
        _migration = null;
      }
      rethrow;
    }
  }

  Future<void> _migrate() async {
    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.composerDraftMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return;
    }

    final entries = await _legacyStore.loadEntries();
    for (final entry in entries.entries) {
      final legacyDraft = _codec.decode(entry.value);
      if (legacyDraft != null) {
        final current = await _target.loadDraft(legacyDraft.identity);
        if (current == null) {
          await _target.saveDraft(legacyDraft);
        }
      }
      await _legacyStore.remove(entry.key);
    }
    await _preferencesStore.write(
      PreferenceKeys.composerDraftMigrationVersion,
      migrationVersion,
    );
  }
}
