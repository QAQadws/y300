import 'package:sqflite/sqflite.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';

/// Seeds explicit persisted data through the current storage contracts.
/// It never discovers chapters, parses forum HTML, or requests a gateway.
Future<NovelSourceMetadata> seedNovelRepository(
  Database db, {
  required NovelSourceSeed seed,
  String title = '测试小说标题',
  String publisherName = '楼主A',
  String publisherId = '1',
  String? coverImageUrl = 'https://img.test/novel-cover.jpg',
  String? sourceIntro,
  List<NovelEpisodeDraft>? episodes,
}) async {
  final novelId = 'novel:${seed.fid}:${seed.tid}';
  final seededEpisodes = episodes ?? novelRepositorySeedEpisodes(seed);
  final seededAt = DateTime.utc(2026, 6, 1);
  final metadata = NovelSourceMetadata(
    novelId: novelId,
    tid: seed.tid,
    fid: seed.fid,
    subject: title,
    publisherName: publisherName,
    publisherId: publisherId,
    firstPostPid: seededEpisodes.isEmpty
        ? '5001'
        : seededEpisodes.first.sourcePid,
    catalogEntries: const <NovelSourceCatalogEntry>[],
    sourceIntro: sourceIntro,
    coverImageUrl: coverImageUrl,
    sourceApiVersion: 4,
    ingestedAt: seededAt,
  );
  final dbFuture = Future<Database>.value(db);
  await SqfliteNovelSourceMetadataRepository(dbFuture).saveFromFavoriteDetail(
    seed: seed,
    metadata: metadata,
    favoriteAddedAt: seededAt,
  );
  if (seededEpisodes.isEmpty) return metadata;

  final chapters = SqfliteNovelChapterSyncRepository(dbFuture);
  final runId = 'fixture:$novelId';
  await chapters.beginRun(
    runId: runId,
    novelId: novelId,
    mode: NovelChapterSyncMode.initialFull,
  );
  await chapters.stageEpisodes(runId: runId, episodes: seededEpisodes);
  await chapters.promote(
    runId: runId,
    request: NovelChapterSyncRequest(
      novelId: novelId,
      tid: seed.tid,
      publisherId: publisherId,
      mode: NovelChapterSyncMode.initialFull,
    ),
    checkpoint: NovelChapterSyncCheckpoint(
      novelId: novelId,
      publisherId: publisherId,
      lastCompletedAuthorPage: seededEpisodes
          .map((episode) => episode.sourcePage)
          .reduce((left, right) => left > right ? left : right),
      lastSeenPid: seededEpisodes.last.sourcePid,
      completedAt: seededAt,
    ),
    fetchedPages: 1,
  );
  return metadata;
}

List<NovelEpisodeDraft> novelRepositorySeedEpisodes(NovelSourceSeed seed) {
  final novelId = 'novel:${seed.fid}:${seed.tid}';
  return <NovelEpisodeDraft>[
    NovelEpisodeDraft(
      episodeId: '$novelId:5001',
      novelId: novelId,
      sourceTid: seed.tid,
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章 开始',
      orderIndex: 0,
      datelineText: '2026-05-03',
      rawHtml: '<p>第1章 开始</p><p>这是第一段。</p>',
      plainText: '第1章 开始\n这是第一段。',
      paragraphs: const <String>['第1章 开始', '这是第一段。'],
    ),
    NovelEpisodeDraft(
      episodeId: '$novelId:5003',
      novelId: novelId,
      sourceTid: seed.tid,
      sourcePid: '5003',
      sourcePage: 1,
      episodeTitle: '第2章 继续',
      orderIndex: 1,
      datelineText: '2026-05-04',
      rawHtml: '<p>第2章 继续</p><p>这是第二章。</p>',
      plainText: '第2章 继续\n这是第二章。',
      paragraphs: const <String>['第2章 继续', '这是第二章。'],
    ),
  ];
}
