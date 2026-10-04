import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/data/services/default_novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:y300/features/novel/domain/services/novel_sync_request_governor.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../test_support/novel_repository_seed.dart';
import '../test_support/novel_title_fixtures.dart';

const _seed = NovelSourceSeed(fid: '49', tid: '200');
const _novelId = 'novel:49:200';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;
  late LocalNovelRepository novels;
  late LocalLibraryStateRepository libraryState;
  late SqfliteNovelSourceStateRepository sourceState;
  late DefaultNovelChapterSyncService sync;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('y300-novel-preservation-');
    dbPath = p.join(temp.path, 'novel.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
    await seedNovelRepository(db, seed: _seed);
    final dbFuture = Future<Database>.value(db);
    novels = LocalNovelRepository(dbFuture);
    libraryState = LocalLibraryStateRepository(dbFuture);
    sourceState = SqfliteNovelSourceStateRepository(dbFuture);
    sync = DefaultNovelChapterSyncService(
      threadGateway: _Gateway(),
      governor: _Governor(),
      episodeBuilder: const DefaultNovelAuthorPostEpisodeBuilder(),
      titleSanitizer: const DefaultNovelTitleSanitizer(),
      repository: SqfliteNovelChapterSyncRepository(dbFuture),
      sourceStateRepository: sourceState,
    );
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  for (final mode in <NovelChapterSyncMode>[
    NovelChapterSyncMode.fullRefresh,
    NovelChapterSyncMode.incremental,
  ]) {
    test(
      '${mode.name} preserves user metadata through source refresh',
      () async {
        await novels.updateCustomMetadata(
          novelId: _novelId,
          customTitle: '自定义标题',
        );
        await novels.updateCustomCover(
          novelId: _novelId,
          customCoverLocalPath: 'custom/cover.jpg',
          focusX: 0.25,
          focusY: -0.5,
        );
        await libraryState.upsertWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: _novelId,
          introText: '我手动写的简介',
        );

        await _refreshMetadata(db);
        await _synchronize(sync, sourceState, mode);

        final detail = await novels.getDetail(novelId: _novelId);
        expect(detail?.displayTitle, '自定义标题');
        expect(detail?.publisherName, '楼主A');
        expect(detail?.customCoverLocalPath, 'custom/cover.jpg');
        expect(detail?.customCoverFocusX, 0.25);
        expect(detail?.customCoverFocusY, -0.5);
        expect(detail?.coverHidden, isFalse);
        expect(
          (await libraryState.getWorkState(
            moduleKey: LibraryModuleKey.novel,
            workId: _novelId,
          ))?.introText,
          '我手动写的简介',
        );
        expect(
          (await sourceState.getSourceState(novelId: _novelId))?.sourceIntro,
          '更新后的来源简介',
        );

        await novels.removeCustomCover(novelId: _novelId);
        await _refreshMetadata(db);
        await _synchronize(sync, sourceState, mode);

        final hidden = await novels.getDetail(novelId: _novelId);
        expect(hidden?.coverHidden, isTrue);
        expect(hidden?.customCoverLocalPath, isNull);
        expect(hidden?.customCoverFocusX, isNull);
        expect(hidden?.customCoverFocusY, isNull);
        expect(hidden?.displayTitle, '自定义标题');
      },
    );
  }

  test('source intro never becomes an implicit user intro', () async {
    await _refreshMetadata(db);
    await _synchronize(sync, sourceState, NovelChapterSyncMode.incremental);

    expect(
      (await sourceState.getSourceState(novelId: _novelId))?.sourceIntro,
      '更新后的来源简介',
    );
    expect(
      (await libraryState.getWorkState(
        moduleKey: LibraryModuleKey.novel,
        workId: _novelId,
      ))?.introText,
      isNull,
    );
    final detail = await novels.getDetail(novelId: _novelId);
    expect(detail?.title, novelTitleFixtures.first.expectedSanitized);
  });
}

Future<void> _refreshMetadata(Database db) =>
    SqfliteNovelSourceMetadataRepository(
      Future<Database>.value(db),
    ).saveFromFavoriteDetail(
      seed: _seed,
      metadata: NovelSourceMetadata(
        novelId: _novelId,
        tid: _seed.tid,
        fid: _seed.fid,
        subject: novelTitleFixtures.first.raw,
        publisherName: '楼主A',
        publisherId: '1',
        firstPostPid: '5001',
        catalogEntries: const <NovelSourceCatalogEntry>[],
        sourceIntro: '更新后的来源简介',
        coverImageUrl: 'https://img.test/updated-cover.jpg',
        sourceApiVersion: 4,
        ingestedAt: DateTime.utc(2026, 6, 2),
      ),
      favoriteAddedAt: DateTime.utc(2026, 6, 2),
    );

Future<NovelChapterSyncResult> _synchronize(
  DefaultNovelChapterSyncService sync,
  SqfliteNovelSourceStateRepository sourceState,
  NovelChapterSyncMode mode,
) async {
  final previous = await sourceState.getSourceState(novelId: _novelId);
  return sync.synchronize(
    NovelChapterSyncRequest(
      novelId: _novelId,
      tid: _seed.tid,
      publisherId: '1',
      mode: mode,
      checkpoint: mode == NovelChapterSyncMode.incremental
          ? previous?.checkpoint
          : null,
    ),
  );
}

class _Gateway implements NovelThreadGateway {
  @override
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  }) async => ThreadDetailData(
    tid: tid,
    fid: _seed.fid,
    subject: novelTitleFixtures.first.raw,
    author: '楼主A',
    replies: 1,
    views: 0,
    currentPage: page,
    perPage: postsPerPage,
    posts: <ThreadPost>[
      for (final entry in novelRepositorySeedEpisodes(_seed).indexed)
        ThreadPost(
          pid: entry.$2.sourcePid,
          author: '楼主A',
          authorId: authorId,
          message: entry.$2.rawHtml,
          number: entry.$1 + 1,
          isFirst: entry.$1 == 0,
          dateline: entry.$2.datelineText,
        ),
    ],
  );
}

class _Governor implements NovelSyncRequestGovernor {
  @override
  Future<T> schedule<T>(Future<T> Function() request) => request();
}
