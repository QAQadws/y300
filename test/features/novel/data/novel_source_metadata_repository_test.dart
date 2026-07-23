import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;
  late SqfliteNovelSourceMetadataRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('y300-novel-metadata-');
    dbPath = p.join(temp.path, 'metadata.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
    repository = SqfliteNovelSourceMetadataRepository(Future.value(db));
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'atomically creates metadata-only shelf work with zero chapters',
    () async {
      await repository.saveFromFavoriteDetail(
        seed: const NovelSourceSeed(
          fid: '55',
          tid: '521519',
          typeid: '295',
          tagName: '長篇連載',
        ),
        metadata: _metadata(),
        favoriteAddedAt: DateTime(2026, 7, 1),
      );

      final works = await db.query(
        ComicLocalDb.worksTable,
        where: 'work_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
      );
      expect(works, hasLength(1));
      expect(works.single['title'], '一周一次买下同班同学的那些事');
      expect(works.single['author'], 'INCSKY16');
      expect(works.single['source_typeid'], '295');
      expect(works.single['source_tag_name'], '長篇連載');
      expect(
        works.single['cover_image_url'],
        'https://cdn.example.test/cover.jpg',
      );

      final shelfRows = await db.query(
        ComicLocalDb.novelShelfItemsTable,
        where: 'novel_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
      );
      expect(shelfRows, hasLength(1));
      expect(shelfRows.single['category_id'], 'default');
      expect(
        shelfRows.single['added_at'],
        DateTime(2026, 7, 1).millisecondsSinceEpoch,
      );

      final episodes = await db.query(
        ComicLocalDb.workEpisodesTable,
        where: 'work_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
      );
      expect(episodes, isEmpty);

      final sourceState = await SqfliteNovelSourceStateRepository(
        Future.value(db),
      ).getSourceState(novelId: 'novel:55:521519');
      expect(sourceState?.publisherId, '406769');
      expect(sourceState?.publisherName, 'INCSKY16');
      expect(sourceState?.sourceIntro, '来源简介');
      expect(sourceState?.catalogEntries.single.pid, '40213902');
      expect(sourceState?.metadataSourceVersion, 4);
      expect(
        sourceState?.hydrationState,
        NovelChapterHydrationState.metadataOnly,
      );
    },
  );

  test('metadata misses preserve prior source values and user data', () async {
    await repository.saveFromFavoriteDetail(
      seed: const NovelSourceSeed(
        fid: '55',
        tid: '521519',
        typeid: '295',
        tagName: '長篇連載',
      ),
      metadata: _metadata(),
      favoriteAddedAt: DateTime(2026, 7, 1),
    );
    await db.update(
      ComicLocalDb.worksTable,
      <String, Object?>{
        'cover_local_path': 'cached/cover.jpg',
        'custom_cover_local_path': 'custom/cover.jpg',
      },
      where: 'work_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
    );
    await db.insert(ComicLocalDb.workEpisodesTable, <String, Object?>{
      'episode_id': 'novel:55:521519:40213902',
      'work_id': 'novel:55:521519',
      'content_type': 'novel',
      'source_tid': '521519',
      'source_pid': '40213902',
      'source_page': 1,
      'episode_title': '旧章节',
      'order_index': 0,
      'dateline_text': '2026-07-13',
    });

    await repository.saveFromFavoriteDetail(
      seed: const NovelSourceSeed(fid: '55', tid: '521519'),
      metadata: _metadata(
        publisherName: '',
        sourceIntro: null,
        catalogEntries: const <NovelSourceCatalogEntry>[],
        coverImageUrl: null,
        ingestedAt: DateTime(2026, 7, 14),
      ),
      favoriteAddedAt: DateTime(2026, 7, 14),
    );

    final work = (await db.query(
      ComicLocalDb.worksTable,
      where: 'work_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
    )).single;
    expect(work['author'], 'INCSKY16');
    expect(work['source_typeid'], '295');
    expect(work['source_tag_name'], '長篇連載');
    expect(work['cover_image_url'], 'https://cdn.example.test/cover.jpg');
    expect(work['cover_local_path'], 'cached/cover.jpg');
    expect(work['custom_cover_local_path'], 'custom/cover.jpg');
    expect(
      await db.query(
        ComicLocalDb.workEpisodesTable,
        where: 'work_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
      ),
      hasLength(1),
    );

    final sourceState = await SqfliteNovelSourceStateRepository(
      Future.value(db),
    ).getSourceState(novelId: 'novel:55:521519');
    expect(sourceState?.publisherName, 'INCSKY16');
    expect(sourceState?.sourceIntro, '来源简介');
    expect(sourceState?.catalogEntries.single.pid, '40213902');
    final shelfAddedAt = (await db.query(
      ComicLocalDb.novelShelfItemsTable,
      columns: const <String>['added_at'],
      where: 'novel_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
    )).single['added_at'];
    expect(shelfAddedAt, DateTime(2026, 7, 1).millisecondsSinceEpoch);

    await repository.saveFromFavoriteDetail(
      seed: const NovelSourceSeed(fid: '55', tid: '521519'),
      metadata: _metadata(
        subject: '',
        publisherName: '',
        sourceIntro: null,
        catalogEntries: const <NovelSourceCatalogEntry>[],
        coverImageUrl: null,
      ),
      favoriteAddedAt: DateTime(2026, 7, 15),
    );
    final titleAfterMissingSource = (await db.query(
      ComicLocalDb.worksTable,
      columns: const <String>['title'],
      where: 'work_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
    )).single['title'];
    expect(titleAfterMissingSource, '一周一次买下同班同学的那些事');
  });

  test(
    'rolls back work and shelf rows when source-state write fails',
    () async {
      await db.execute('''
      CREATE TRIGGER fail_novel_source_metadata
      BEFORE INSERT ON ${ComicLocalDb.novelSourceStateTable}
      WHEN NEW.publisher_id = '406769'
      BEGIN
        SELECT RAISE(ABORT, 'forced metadata failure');
      END
    ''');

      await expectLater(
        repository.saveFromFavoriteDetail(
          seed: const NovelSourceSeed(fid: '55', tid: '521519'),
          metadata: _metadata(),
          favoriteAddedAt: DateTime(2026, 7, 1),
        ),
        throwsA(anything),
      );

      expect(
        await db.query(
          ComicLocalDb.worksTable,
          where: 'work_id = ?',
          whereArgs: const <Object?>['novel:55:521519'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.novelShelfItemsTable,
          where: 'novel_id = ?',
          whereArgs: const <Object?>['novel:55:521519'],
        ),
        isEmpty,
      );
    },
  );
}

NovelSourceMetadata _metadata({
  String subject = '[个人翻译][长篇]一周一次买下同班同学的那些事',
  String publisherName = 'INCSKY16',
  String? sourceIntro = '来源简介',
  List<NovelSourceCatalogEntry>
  catalogEntries = const <NovelSourceCatalogEntry>[
    NovelSourceCatalogEntry(
      position: 0,
      pid: '40213902',
      title: '第一章',
      url:
          'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=521519&pid=40213902',
    ),
  ],
  String? coverImageUrl = 'https://cdn.example.test/cover.jpg',
  DateTime? ingestedAt,
}) {
  return NovelSourceMetadata(
    novelId: 'novel:55:521519',
    tid: '521519',
    fid: '55',
    subject: subject,
    publisherName: publisherName,
    publisherId: '406769',
    firstPostPid: '40213901',
    catalogEntries: catalogEntries,
    sourceIntro: sourceIntro,
    coverImageUrl: coverImageUrl,
    sourceApiVersion: 4,
    ingestedAt: ingestedAt ?? DateTime(2026, 7, 13),
  );
}
