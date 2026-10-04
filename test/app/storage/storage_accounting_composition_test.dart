import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/app/storage/storage_accounting_composition.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/services/storage_accounting_service.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/services/comic_metadata_storage_accounting_adapter.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';

import '../../features/profile/test_support/blog_draft_fixture.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late Database db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp(
      'y300-accounting-composition-',
    );
    db = await AppDatabase.open(databaseName: p.join(temp.path, 'library.db'));
  });

  tearDown(() async {
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'owner counts preserve order and share one main-file contribution',
    () async {
      await _seedOwnerRows(db);
      final countedPath = p.join(temp.path, 'counted-library.db');
      await File(countedPath).writeAsBytes(List<int>.filled(11, 7));
      await File('$countedPath-wal').writeAsBytes(List<int>.filled(5, 7));
      await File('$countedPath-shm').writeAsBytes(List<int>.filled(3, 7));
      final adapter = composeLibraryMetadataStorageAccountingAdapter(
        databaseProvider: () async => db,
        databasePathFuture: Future<String>.value(countedPath),
      );

      final report = await DefaultStorageAccountingService(
        adapters: <StorageAccountingAdapter>[adapter],
      ).loadUsageReport();

      expect(report.totalBytes, 11);
      final section = report.sections.single;
      expect(section.bucket, StorageBucket.libraryMetadata);
      expect(section.labelRef?.kind, StorageUsageLabelKind.bucket);
      expect(section.labelRef?.code, 'library_metadata');
      expect(section.clearable, isFalse);
      expect(section.slices.map((slice) => slice.id), <String>[
        'library_metadata:sqlite',
        'library_metadata:comics',
        'library_metadata:comic_episodes',
        'library_metadata:novels',
        'library_metadata:novel_episodes',
        'library_metadata:favorites',
        'library_metadata:library_work_state',
        'library_metadata:library_episode_state',
      ]);
      expect(section.slices.map((slice) => slice.bytes), <int>[
        11,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(
        section.slices.first.labelRef?.kind,
        StorageUsageLabelKind.database,
      );
      expect(section.slices.first.labelRef?.code, 'library_metadata');
      expect(
        section.slices.skip(1).map((slice) => slice.labelRef?.kind),
        everyElement(StorageUsageLabelKind.libraryKind),
      );
      expect(
        section.slices.skip(1).map((slice) => slice.labelRef?.count),
        <int>[1, 2, 1, 2, 1, 1, 2],
      );
      expect(section.slices.every((slice) => slice.protected), isTrue);
    },
  );

  test(
    'missing physical file leaves owner counts without estimated bytes',
    () async {
      await _seedOwnerRows(db);
      final section = await composeLibraryMetadataStorageAccountingAdapter(
        databaseProvider: () async => db,
        databasePathFuture: Future<String>.value(
          p.join(temp.path, 'missing.db'),
        ),
      ).calculateUsage();

      expect(section.bytes, 0);
      expect(section.slices, hasLength(7));
      expect(section.slices.every((slice) => slice.bytes == 0), isTrue);
      expect(section.slices.first.id, 'library_metadata:comics');
    },
  );

  test('a missing owner table does not hide available owner counts', () async {
    await _seedOwnerRows(db);
    await db.execute('DROP TABLE ${AppDatabase.episodesTable}');

    final section = await ComicMetadataStorageAccountingAdapter(
      databaseProvider: () async => db,
    ).calculateUsage();

    expect(section.bytes, 0);
    expect(section.slices.single.id, 'library_metadata:comics');
    expect(section.slices.single.labelRef?.count, 1);
  });

  test(
    'a blog-only draft bucket stays protected and cannot be cleared',
    () async {
      final drafts = await ComposerDraftLocalDb.open(
        databaseName: p.join(temp.path, 'composer.db'),
      );
      addTearDown(drafts.close);
      final blogs = MemoryBlogDraftRepository();
      blogs.values['101'] = BlogDraftSnapshot(
        accountId: '101',
        updatedAt: DateTime.utc(2026, 7, 18),
      );

      final section = await composeComposerDraftStorageAccountingAdapter(
        databaseProvider: () async => drafts,
        blogDraftRepository: blogs,
      ).calculateUsage();

      expect(section.bucket, StorageBucket.composerDraft);
      expect(section.bytes, 100);
      expect(section.clearable, isFalse);
      expect(section.slices.single.id, 'composer_draft:blog');
      expect(section.slices.single.labelRef?.code, 'blog_draft');
      expect(section.slices.single.labelRef?.count, 1);
      expect(section.slices.single.protected, isTrue);
    },
  );
}

Future<void> _seedOwnerRows(Database db) async {
  await db.insert(AppDatabase.comicsTable, <String, Object?>{
    'comic_id': 'comic-1',
    'source_tid': '100',
    'source_fid': '33',
    'title': 'comic',
    'created_at': 1,
    'updated_at': 1,
  });
  await db.insert(AppDatabase.worksTable, <String, Object?>{
    'work_id': 'novel:49:200',
    'content_type': 'novel',
    'source_tid': '200',
    'source_fid': '49',
    'title': 'novel',
    'updated_at': 1,
  });
  for (var index = 0; index < 2; index++) {
    await db.insert(AppDatabase.episodesTable, <String, Object?>{
      'episode_id': 'comic-1:$index',
      'comic_id': 'comic-1',
      'source_tid': '100',
      'source_url': 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
      'order_index': index,
    });
    await db.insert(AppDatabase.workEpisodesTable, <String, Object?>{
      'episode_id': 'novel:49:200:$index',
      'work_id': 'novel:49:200',
      'content_type': 'novel',
      'source_tid': '200',
      'source_pid': '${index + 1}',
      'order_index': index,
    });
    await db.insert(AppDatabase.libraryEpisodeStateTable, <String, Object?>{
      'content_type': 'novel',
      'episode_id': 'novel:49:200:$index',
      'work_id': 'novel:49:200',
    });
  }
  await db.insert(AppDatabase.favoriteThreadsTable, <String, Object?>{
    'tid': '100',
    'title': 'favorite',
    'first_seen_at': 1,
    'last_seen_at': 1,
  });
  await db.insert(AppDatabase.libraryWorkStateTable, <String, Object?>{
    'content_type': 'novel',
    'work_id': 'novel:49:200',
    'created_at': 1,
    'updated_at': 1,
  });
}
