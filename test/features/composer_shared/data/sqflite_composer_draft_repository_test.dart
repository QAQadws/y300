import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Database;
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';
import 'package:y300/features/composer_shared/data/preferences/composer_draft_legacy_store.dart';
import 'package:y300/features/composer_shared/data/repositories/migrating_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/repositories/sqflite_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late _RecordingCacheStorage cacheStorage;
  late SqfliteComposerDraftRepository repository;
  var now = DateTime.utc(2026, 6, 8, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await ComposerDraftLocalDb.open(databaseName: inMemoryDatabasePath);
    cacheStorage = _RecordingCacheStorage();
    repository = SqfliteComposerDraftRepository(
      databaseProvider: () async => db,
      cacheStorage: cacheStorage,
      now: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('schema exposes identity and retention indexes', () async {
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );

    expect(
      indexes.map((row) => row['name']),
      containsAll(<String>[
        ComposerDraftLocalDb.threadIndex,
        ComposerDraftLocalDb.recentIndex,
      ]),
    );
  });

  test('saves and restores an explicit draft signature setting', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    await repository.saveDraft(
      ComposerDraftSnapshot(
        identity: identity,
        message: '未写完的回复',
        useSignature: false,
        updatedAt: DateTime.utc(2026, 6, 6),
      ),
    );

    final loaded = await repository.loadDraft(identity);

    expect(loaded?.message, '未写完的回复');
    expect(loaded?.useSignature, isFalse);
    expect(loaded?.updatedAt, DateTime.utc(2026, 6, 6));
  });

  test('keeps identities isolated and lists one thread newest first', () async {
    final thread = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    final post = ComposerDraftIdentity.post(
      fid: '33',
      tid: '572063',
      repquote: '41554317',
    );
    await repository.saveDraft(_draft(thread, 'thread', minute: 1));
    await repository.saveDraft(_draft(post, 'post', minute: 2));
    await repository.saveDraft(
      _draft(
        ComposerDraftIdentity.thread(fid: '33', tid: 'other'),
        'other',
        minute: 3,
      ),
    );

    final drafts = await repository.listDraftsForThread(
      fid: '33',
      tid: '572063',
    );

    expect(drafts.map((draft) => draft.message), <String>['post', 'thread']);
  });

  test('empty content removes the existing snapshot', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    await repository.saveDraft(_draft(identity, 'draft'));

    await repository.saveDraft(_draft(identity, '   '));

    expect(await repository.loadDraft(identity), isNull);
  });

  test('load sanitizes expired attachments and owned cache files', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    await repository.saveDraft(
      ComposerDraftSnapshot(
        identity: identity,
        message: '正文\n[attach]111[/attach]\n[attach]222[/attach]',
        useSignature: true,
        updatedAt: now,
        imageAttachments: <ComposerImageAttachment>[
          _attachment('expired', '111', now.subtract(const Duration(days: 2))),
          _attachment('fresh', '222', now.subtract(const Duration(hours: 1))),
        ],
      ),
    );

    final loaded = await repository.loadDraft(identity);

    expect(loaded?.message, '正文\n[attach]222[/attach]');
    expect(loaded?.imageAttachments.single.localId, 'fresh');
    expect(cacheStorage.deletedPaths, contains('/cache/expired.jpg'));
  });

  test('prunes expired and overflow snapshots while keeping newest', () async {
    await repository.saveDraft(
      ComposerDraftSnapshot(
        identity: ComposerDraftIdentity.thread(fid: '33', tid: 'expired'),
        message: 'expired',
        useSignature: true,
        updatedAt: now.subtract(const Duration(days: 31)),
      ),
    );
    for (var index = 0; index < 3; index += 1) {
      await repository.saveDraft(
        _draft(
          ComposerDraftIdentity.thread(fid: '33', tid: '$index'),
          'draft-$index',
          minute: index,
        ),
      );
    }

    final result = await repository.pruneDrafts(maxCount: 2);

    expect(result.removedCount, 2);
    expect(result.keptCount, 2);
    expect(
      await repository.loadDraft(
        ComposerDraftIdentity.thread(fid: '33', tid: 'expired'),
      ),
      isNull,
    );
    expect(
      await repository.loadDraft(
        ComposerDraftIdentity.thread(fid: '33', tid: '0'),
      ),
      isNull,
    );
  });

  test('migrates legacy SharedPreferences drafts once', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    const codec = ComposerDraftSnapshotJsonCodec();
    final legacyKey =
        '${SharedPreferencesComposerDraftLegacyStore.draftKeyPrefix}'
        '${identity.storageKey}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: jsonEncode(
        codec.encode(_draft(identity, 'legacy', signature: false)),
      ),
    });
    final preferences = await SharedPreferences.getInstance();
    final migrating = MigratingComposerDraftRepository(
      target: repository,
      legacyStore: SharedPreferencesComposerDraftLegacyStore(
        sharedPreferences: preferences,
      ),
      preferencesStore: SharedPreferencesStore(loader: () async => preferences),
    );

    final loaded = await migrating.loadDraft(identity);

    expect(loaded?.message, 'legacy');
    expect(loaded?.useSignature, isFalse);
    expect(preferences.containsKey(legacyKey), isFalse);
    expect(
      preferences.getInt(PreferenceKeys.composerDraftMigrationVersion.name),
      1,
    );
  });

  test('SQLite snapshot wins over stale legacy data', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    await repository.saveDraft(_draft(identity, 'sqlite'));
    const codec = ComposerDraftSnapshotJsonCodec();
    final legacyKey =
        '${SharedPreferencesComposerDraftLegacyStore.draftKeyPrefix}'
        '${identity.storageKey}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: jsonEncode(codec.encode(_draft(identity, 'legacy'))),
    });
    final preferences = await SharedPreferences.getInstance();
    final migrating = MigratingComposerDraftRepository(
      target: repository,
      legacyStore: SharedPreferencesComposerDraftLegacyStore(
        sharedPreferences: preferences,
      ),
      preferencesStore: SharedPreferencesStore(loader: () async => preferences),
    );

    expect((await migrating.loadDraft(identity))?.message, 'sqlite');
  });

  test('completed migration marker prevents legacy draft resurrection', () async {
    final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
    const codec = ComposerDraftSnapshotJsonCodec();
    final legacyKey =
        '${SharedPreferencesComposerDraftLegacyStore.draftKeyPrefix}'
        '${identity.storageKey}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.composerDraftMigrationVersion.name:
          MigratingComposerDraftRepository.migrationVersion,
      legacyKey: jsonEncode(codec.encode(_draft(identity, 'stale legacy'))),
    });
    final preferences = await SharedPreferences.getInstance();
    final migrating = MigratingComposerDraftRepository(
      target: repository,
      legacyStore: SharedPreferencesComposerDraftLegacyStore(
        sharedPreferences: preferences,
      ),
      preferencesStore: SharedPreferencesStore(loader: () async => preferences),
    );

    expect(await migrating.loadDraft(identity), isNull);
  });
}

ComposerDraftSnapshot _draft(
  ComposerDraftIdentity identity,
  String message, {
  int minute = 0,
  bool signature = true,
}) {
  return ComposerDraftSnapshot(
    identity: identity,
    message: message,
    useSignature: signature,
    updatedAt: DateTime.utc(2026, 6, 8, 10, minute),
  );
}

ComposerImageAttachment _attachment(
  String localId,
  String aid,
  DateTime uploadedAt,
) {
  return ComposerImageAttachment(
    localId: localId,
    localPath: '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: uploadedAt,
    cachePath: '/cache/$localId.jpg',
  );
}

class _RecordingCacheStorage implements ComposerUploadCacheStorage {
  final List<String> deletedPaths = <String>[];

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    if (cachePath == null) {
      return false;
    }
    deletedPaths.add(cachePath);
    return true;
  }
}
