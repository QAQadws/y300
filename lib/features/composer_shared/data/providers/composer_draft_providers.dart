import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_database_manager.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';
import 'package:y300/features/composer_shared/data/preferences/composer_draft_legacy_store.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/repositories/migrating_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/repositories/sqflite_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_attachment_maintenance_service.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';

final composerUploadCacheStorageProvider = Provider<ComposerUploadCacheStorage>(
  (_) => LocalComposerUploadCacheStorage(),
);

final composerDraftDatabaseNameProvider = Provider<String>((ref) {
  return ComposerDraftLocalDb.dbName;
});

final composerDraftDatabaseManagerProvider =
    Provider<ComposerDraftDatabaseManager>((ref) {
      final manager = ComposerDraftDatabaseManager(
        databaseName: ref.watch(composerDraftDatabaseNameProvider),
      );
      ref.onDispose(() {
        unawaited(manager.dispose());
      });
      return manager;
    });

final composerDraftLegacyStoreProvider = Provider<ComposerDraftLegacyStore>((
  ref,
) {
  return SharedPreferencesComposerDraftLegacyStore();
});

final composerDraftRepositoryProvider = Provider<ComposerDraftRepository>((
  ref,
) {
  final target = SqfliteComposerDraftRepository(
    databaseProvider: ref.watch(composerDraftDatabaseManagerProvider).open,
    cacheStorage: ref.watch(composerUploadCacheStorageProvider),
  );
  return MigratingComposerDraftRepository(
    target: target,
    legacyStore: ref.watch(composerDraftLegacyStoreProvider),
    preferencesStore: ref.watch(preferencesStoreProvider),
  );
});

final composerDraftAttachmentMaintenanceServiceProvider =
    Provider<ComposerDraftAttachmentMaintenanceService>((ref) {
      return RepositoryComposerDraftAttachmentMaintenanceService(
        repository: ref.watch(composerDraftRepositoryProvider),
      );
    });
