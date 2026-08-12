import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import '../../../test_support/unavailable_library_cover_store.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

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
    repository = LocalComicRepository(
      Future<Database>.value(database),
      libraryCoverStore: const UnavailableLibraryCoverStore(),
    );
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

      await repository.addManualEpisode(
        comicId: 'comic-management',
        sourceTid: '573441',
        sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573441',
      );

      final visibility = await repository.setEpisodeHidden(
        comicId: 'comic-management',
        episodeId: 'comic-management:573440',
        isHidden: true,
      );
      expect(visibility.code, ComicEpisodeVisibilityUpdateCode.updated);

      expect(
        await repository.getComicEpisodes(comicId: 'comic-management'),
        hasLength(1),
      );
      final managed = await repository.getManagedComicEpisodes(
        comicId: 'comic-management',
      );
      expect(managed, hasLength(2));
      expect(
        managed.firstWhere((episode) => episode.sourceTid == '573440').isHidden,
        isTrue,
      );
    },
  );

  test('the last visible episode cannot be hidden', () async {
    await repository.addManualEpisode(
      comicId: 'comic-management',
      sourceTid: '573440',
      sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440',
    );

    final result = await repository.setEpisodeHidden(
      comicId: 'comic-management',
      episodeId: 'comic-management:573440',
      isHidden: true,
    );

    expect(result.code, ComicEpisodeVisibilityUpdateCode.rejectedLastVisible);
    expect(
      (await repository.getComicEpisodes(
        comicId: 'comic-management',
      )).single.isHidden,
      isFalse,
    );
  });

  test('the last visible manual episode cannot be removed', () async {
    await repository.addManualEpisode(
      comicId: 'comic-management',
      sourceTid: '573440',
      sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440',
    );

    final result = await repository.removeManualEpisode(
      comicId: 'comic-management',
      episodeId: 'comic-management:573440',
    );

    expect(result.code, ComicEpisodeRemovalCode.lastVisible);
    expect(
      await repository.getManagedComicEpisodes(comicId: 'comic-management'),
      hasLength(1),
    );
  });

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

    expect(removed.code, ComicEpisodeRemovalCode.notManual);
    expect(
      await repository.getManagedComicEpisodes(comicId: 'comic-management'),
      hasLength(1),
    );
  });

  test('hiding survives a parsed refresh that rewrites the row', () async {
    const episodeId = 'comic-management:400';
    await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-400-1-1.html', rawText: '第一话'),
        ComicEpisodeLink(url: 'thread-401-1-1.html', rawText: '第二话'),
      ],
    );
    await repository.setEpisodeHidden(
      comicId: 'comic-management',
      episodeId: episodeId,
      isHidden: true,
    );

    final refreshed = await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-400-1-1.html', rawText: '第一话'),
        ComicEpisodeLink(url: 'thread-401-1-1.html', rawText: '第二话'),
      ],
    );

    // 刷新用整行 replace 覆盖章节，隐藏是用户意图，不能被解析结果冲掉。
    expect(refreshed.totalCount, 1);
    final managed = await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    );
    expect(managed, hasLength(2));
    expect(
      managed.firstWhere((episode) => episode.episodeId == episodeId).isHidden,
      isTrue,
    );
    expect(
      managed.firstWhere((episode) => episode.episodeId != episodeId).isHidden,
      isFalse,
    );
  });

  test('a manual episode rediscovered by parsing becomes parsed', () async {
    await repository.addManualEpisode(
      comicId: 'comic-management',
      sourceTid: '500',
      sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=500',
    );

    await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-500-1-1.html', rawText: '第一话'),
      ],
    );

    // 来源每次刷新都会带回这条链接，继续标成手动只会给出移除不掉的假承诺。
    final managed = await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    );
    expect(managed.single.isManual, isFalse);
    expect(
      (await repository.removeManualEpisode(
        comicId: 'comic-management',
        episodeId: 'comic-management:500',
      )).code,
      ComicEpisodeRemovalCode.notManual,
    );
  });

  test('clearing a rename falls back to the parsed episode name', () async {
    const episodeId = 'comic-management:600';
    await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-600-1-1.html', rawText: '第一话 来源名'),
      ],
    );

    expect(
      await repository.setEpisodeCustomTitle(
        comicId: 'comic-management',
        episodeId: episodeId,
        customTitle: '我改的名字',
      ),
      isTrue,
    );
    var episode = (await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    )).single;
    expect(episode.episodeTitle, '我改的名字');
    expect(episode.customEpisodeTitle, '我改的名字');
    // 来源名必须原样留着，否则清空后无处可退。
    expect(episode.sourceEpisodeTitle, '第一话 来源名');

    await repository.setEpisodeCustomTitle(
      comicId: 'comic-management',
      episodeId: episodeId,
      customTitle: '   ',
    );
    episode = (await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    )).single;
    // 空白等同清空：章节名退回解析出的原名，而不是变成空标题。
    expect(episode.customEpisodeTitle, isNull);
    expect(episode.episodeTitle, '第一话 来源名');
  });

  test('a rename survives a parsed refresh that rewrites the row', () async {
    const episodeId = 'comic-management:601';
    const links = <ComicEpisodeLink>[
      ComicEpisodeLink(url: 'thread-601-1-1.html', rawText: '第一话 来源名'),
    ];
    await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: links,
    );
    await repository.setEpisodeCustomTitle(
      comicId: 'comic-management',
      episodeId: episodeId,
      customTitle: '我改的名字',
    );

    await repository.mergeEpisodesFromLinks(
      comicId: 'comic-management',
      fallbackSourceTid: '100',
      episodeLinks: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-601-1-1.html', rawText: '来源改名了'),
      ],
    );

    final episode = (await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    )).single;
    // 刷新整行 replace 覆盖章节：重命名是用户意图不能被冲掉，
    // 同时来源名要跟上最新解析结果，清空后才会退到新的来源名。
    expect(episode.episodeTitle, '我改的名字');
    expect(episode.sourceEpisodeTitle, '来源改名了');
  });

  test('manual episodes can be renamed and restored to the default', () async {
    await repository.addManualEpisode(
      comicId: 'comic-management',
      sourceTid: '602',
      sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=602',
    );
    const episodeId = 'comic-management:602';

    await repository.setEpisodeCustomTitle(
      comicId: 'comic-management',
      episodeId: episodeId,
      customTitle: '手动章节改名',
    );
    var episode = (await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    )).single;
    expect(episode.episodeTitle, '手动章节改名');

    await repository.setEpisodeCustomTitle(
      comicId: 'comic-management',
      episodeId: episodeId,
      customTitle: null,
    );
    episode = (await repository.getManagedComicEpisodes(
      comicId: 'comic-management',
    )).single;
    // 存储层只保留稳定来源 TID，展示层按当前 locale 生成章节 fallback。
    expect(episode.episodeTitle, '602');
  });

  test('renaming a missing episode reports failure', () async {
    expect(
      await repository.setEpisodeCustomTitle(
        comicId: 'comic-management',
        episodeId: 'comic-management:404',
        customTitle: '不存在',
      ),
      isFalse,
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
    await database.insert(ComicLocalDb.episodesTable, <String, Object?>{
      'episode_id': 'comic-management:301',
      'comic_id': 'comic-management',
      'episode_title': '另一章',
      'source_tid': '301',
      'source_url': 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
      'order_index': 1,
      'publish_time_text': null,
      'is_manual': 0,
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

    expect(removed.code, ComicEpisodeRemovalCode.removed);
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
