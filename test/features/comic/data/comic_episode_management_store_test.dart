import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String databaseName;
  late Database database;
  late LocalComicRepository repository;

  setUp(() async {
    databaseName =
        'comic_episode_management_${DateTime.now().microsecondsSinceEpoch}.db';
    database = await ComicLocalDb.open(databaseName: databaseName);
    repository = LocalComicRepository(Future<Database>.value(database));
    await database.insert(ComicLocalDb.comicsTable, <String, Object?>{
      'comic_id': 'comic-management',
      'source_tid': '100',
      'source_fid': '5',
      'title': '章节管理测试',
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDown(() async {
    await database.close();
    await deleteDatabase(databaseName);
  });

  test(
    'manual episodes are deduplicated and hidden from normal reads',
    () async {
      final added = await repository.addManualEpisode(
        comicId: 'comic-management',
        sourceTid: '573440',
        sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440',
      );
      final duplicate = await repository.addManualEpisode(
        comicId: 'comic-management',
        sourceTid: '573440',
        sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440',
      );

      expect(added, isTrue);
      expect(duplicate, isFalse);

      await repository.setEpisodeHidden(
        comicId: 'comic-management',
        episodeId: 'comic-management:573440',
        isHidden: true,
      );

      expect(
        await repository.getComicEpisodes(comicId: 'comic-management'),
        isEmpty,
      );
      final managed = await repository.getManagedComicEpisodes(
        comicId: 'comic-management',
      );
      expect(managed.single.isManual, isTrue);
      expect(managed.single.isHidden, isTrue);
    },
  );

  test('parsed episodes cannot be removed', () async {
    await database.insert(ComicLocalDb.episodesTable, <String, Object?>{
      'episode_id': 'comic-management:200',
      'comic_id': 'comic-management',
      'episode_title': '解析章节',
      'source_tid': '200',
      'source_url': 'https://bbs.yamibo.com/thread-200-1-1.html',
      'order_index': 0,
      'publish_time_text': null,
      'is_manual': 0,
      'is_hidden': 0,
    });

    final removed = await repository.removeManualEpisode(
      comicId: 'comic-management',
      episodeId: 'comic-management:200',
    );

    expect(removed, isFalse);
    expect(
      await repository.getManagedComicEpisodes(comicId: 'comic-management'),
      hasLength(1),
    );
  });

  test('removing a manual episode clears reading and library state', () async {
    const episodeId = 'comic-management:300';
    await database.insert(ComicLocalDb.episodesTable, <String, Object?>{
      'episode_id': episodeId,
      'comic_id': 'comic-management',
      'episode_title': '手动章节',
      'source_tid': '300',
      'source_url': 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=300',
      'order_index': 0,
      'publish_time_text': null,
      'is_manual': 1,
      'is_hidden': 0,
    });
    await database.insert(ComicLocalDb.episodeImagesTable, <String, Object?>{
      'episode_id': episodeId,
      'image_url': 'https://img.example/300.jpg',
      'image_index': 0,
      'bytes': 0,
      'protected': 0,
    });
    await database.insert(ComicLocalDb.readingProgressTable, <String, Object?>{
      'comic_id': 'comic-management',
      'episode_id': episodeId,
      'image_index': 2,
      'scroll_offset': 10.0,
      'updated_at': 1,
    });
    await database
        .insert(ComicLocalDb.libraryEpisodeStateTable, <String, Object?>{
          'content_type': 'comic',
          'episode_id': episodeId,
          'work_id': 'comic-management',
          'is_read': 1,
          'is_downloaded': 1,
          'is_bookmarked': 1,
        });
    await database.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{'last_read_episode_id': episodeId},
      where: 'comic_id = ?',
      whereArgs: const <Object>['comic-management'],
    );

    final removed = await repository.removeManualEpisode(
      comicId: 'comic-management',
      episodeId: episodeId,
    );

    expect(removed, isTrue);
    expect(
      await database.query(
        ComicLocalDb.episodesTable,
        where: 'episode_id = ?',
        whereArgs: const <Object>[episodeId],
      ),
      isEmpty,
    );
    expect(
      await database.query(
        ComicLocalDb.episodeImagesTable,
        where: 'episode_id = ?',
        whereArgs: const <Object>[episodeId],
      ),
      isEmpty,
    );
    expect(
      await database.query(
        ComicLocalDb.readingProgressTable,
        where: 'episode_id = ?',
        whereArgs: const <Object>[episodeId],
      ),
      isEmpty,
    );
    expect(
      await database.query(
        ComicLocalDb.libraryEpisodeStateTable,
        where: 'episode_id = ?',
        whereArgs: const <Object>[episodeId],
      ),
      isEmpty,
    );
    final comic = await database.query(
      ComicLocalDb.comicsTable,
      columns: const <String>['last_read_episode_id'],
      where: 'comic_id = ?',
      whereArgs: const <Object>['comic-management'],
    );
    expect(comic.single['last_read_episode_id'], isNull);
  });
}
