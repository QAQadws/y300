import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/local_novel_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const testDbName = 'comic_shelf_test_novel_repo.db';

  group('LocalNovelRepository', () {
    late LocalNovelRepository repository;

    setUp(() async {
      await deleteDatabase(testDbName);
      repository = LocalNovelRepository(
        ComicLocalDb.open(databaseName: testDbName),
        threadGateway: _FakeGateway(),
        discoveryService: const NovelEpisodeDiscoveryService(),
      );
    });

    tearDown(() async {
      await deleteDatabase(testDbName);
    });

    test('upsertNovelBySeed + refreshEpisodes builds readable shelf and episodes', () async {
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(
          fid: '49',
          tid: '200',
          typeid: '293',
          tagName: '原创',
        ),
      );
      final result = await repository.refreshEpisodes(novelId: 'novel:49:200');

      final shelf = await repository.getShelfItems();
      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final content = await repository.getChapterContent(episodeId: episodes.first.episodeId);

      expect(result.totalCount, greaterThan(0));
      expect(shelf.length, 1);
      expect(shelf.first.sourceFid, '49');
      expect(shelf.first.sourceTypeId, '293');
      expect(shelf.first.sourceTagName, '原创');
      expect(shelf.first.categoryId, 'default');
      expect(episodes.length, greaterThan(0));
      expect(content, isNotNull);
      expect(content!.paragraphs, isNotEmpty);
    });

    test('reader preferences and reading progress can persist', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '55', tid: '300'));
      await repository.refreshEpisodes(novelId: 'novel:55:300');
      final episodes = await repository.getEpisodes(novelId: 'novel:55:300');

      await repository.upsertReaderPreferences(
        const NovelReaderPreferences(
          fontSize: 20,
          lineHeight: 2.0,
          paragraphSpacing: 12,
          pagePadding: 18,
          themeMode: 'sepia',
          fontFamily: 'system',
        ),
      );
      await repository.saveReadingProgress(
        novelId: 'novel:55:300',
        episodeId: episodes.first.episodeId,
        scrollOffset: 222.5,
      );

      final preferences = await repository.getReaderPreferences();
      final progress = await repository.getReadingProgress(novelId: 'novel:55:300');

      expect(preferences.themeMode, 'sepia');
      expect(preferences.fontSize, 20);
      expect(progress, isNotNull);
      expect(progress!.episodeId, episodes.first.episodeId);
      expect(progress.scrollOffset, 222.5);
    });
  });
}

class _FakeGateway implements NovelThreadGateway {
  @override
  Future<ThreadDetailData> getThreadDetail({required String tid, required int page}) async {
    if (page > 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '测试小说标题',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      );
    }

    return ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '测试小说标题',
      author: '楼主A',
      replies: 2,
      views: 10,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '5001',
          author: '楼主A',
          authorId: '1',
          message: '<p>第1章 开始</p><p>这是第一段。</p>',
          number: 1,
          isFirst: true,
          dateline: '2026-05-03',
        ),
        ThreadPost(
          pid: '5002',
          author: '路人',
          authorId: '2',
          message: '<p>围观</p>',
          number: 2,
          isFirst: false,
          dateline: '2026-05-03',
        ),
        ThreadPost(
          pid: '5003',
          author: '楼主A',
          authorId: '1',
          message: '<p>第2章 继续</p><p>这是第二章。</p>',
          number: 3,
          isFirst: false,
          dateline: '2026-05-04',
        ),
      ],
    );
  }
}

