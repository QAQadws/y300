import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

const novelPhase0BaselineNovelId = 'novel:55:521519';
const novelPhase0BaselineEpisodeId = 'novel:55:521519:40692958';
const novelPhase0BaselineBookmarkId = 'bookmark:novel:55:521519:40692958';

Future<void> seedNovelPhase0PersistenceBaseline(Database db) async {
  const timestamp = 1783900800000;
  await db.transaction((txn) async {
    await txn.insert(ComicLocalDb.worksTable, <String, Object?>{
      'work_id': novelPhase0BaselineNovelId,
      'content_type': 'novel',
      'source_tid': '521519',
      'source_fid': '55',
      'source_typeid': '295',
      'source_tag_name': '轻小说',
      'title': '迁移基线小说',
      'author': 'INCSKY16',
      'cover_image_url': 'https://img.example.test/novel-cover.jpg',
      'cover_local_path': 'covers/novel-cover.jpg',
      'custom_cover_local_path': 'covers/custom-novel-cover.jpg',
      'updated_at': timestamp,
    });
    await txn.insert(ComicLocalDb.workEpisodesTable, <String, Object?>{
      'episode_id': novelPhase0BaselineEpisodeId,
      'work_id': novelPhase0BaselineNovelId,
      'content_type': 'novel',
      'source_tid': '521519',
      'source_pid': '40692958',
      'source_page': 2,
      'episode_title': '迁移基线章节',
      'order_index': 200,
      'dateline_text': '2024-01-02',
    });
    await txn.insert(ComicLocalDb.novelEpisodeContentTable, <String, Object?>{
      'episode_id': novelPhase0BaselineEpisodeId,
      'raw_html': '<p>迁移前正文。</p>',
      'plain_text': '迁移前正文。',
      'paragraph_json': '["迁移前正文。"]',
      'updated_at': timestamp,
    });
    await txn.insert(ComicLocalDb.novelShelfItemsTable, <String, Object?>{
      'category_id': 'default',
      'novel_id': novelPhase0BaselineNovelId,
      'added_at': timestamp,
      'sort_order': 7,
    });
    await txn.insert(ComicLocalDb.libraryWorkStateTable, <String, Object?>{
      'content_type': 'novel',
      'work_id': novelPhase0BaselineNovelId,
      'last_read_episode_id': novelPhase0BaselineEpisodeId,
      'last_read_at': timestamp,
      'check_updated_at': timestamp,
      'fetched_updated_at': timestamp,
      'intro_text': '用户编辑的简介必须保留。',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await txn.insert(ComicLocalDb.libraryEpisodeStateTable, <String, Object?>{
      'content_type': 'novel',
      'episode_id': novelPhase0BaselineEpisodeId,
      'work_id': novelPhase0BaselineNovelId,
      'is_read': 1,
      'is_downloaded': 1,
      'is_bookmarked': 1,
      'read_at': timestamp,
      'downloaded_at': timestamp,
    });
    await txn.insert(ComicLocalDb.novelReadingProgressTable, <String, Object?>{
      'novel_id': novelPhase0BaselineNovelId,
      'episode_id': novelPhase0BaselineEpisodeId,
      'scroll_offset': 345.5,
      'flow_mode': 'pagedLtr',
      'page_index': 8,
      'anchor_node_id': 'paragraph-8',
      'progress_percent': 0.625,
      'updated_at': timestamp,
    });
    await txn.insert(ComicLocalDb.readerBookmarksTable, <String, Object?>{
      'bookmark_id': novelPhase0BaselineBookmarkId,
      'novel_id': novelPhase0BaselineNovelId,
      'episode_id': novelPhase0BaselineEpisodeId,
      'node_id': 'paragraph-8',
      'text_offset': 12,
      'page_index': 8,
      'scroll_offset': 345.5,
      'progress_percent': 0.625,
      'title': '迁移基线书签',
      'snippet': '书签附近的文本',
      'note': '用户书签备注',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  });
}

Future<NovelPhase0PersistenceSnapshot> readNovelPhase0PersistenceBaseline(
  Database db,
) async {
  return NovelPhase0PersistenceSnapshot(
    work: await _singleBy(
      db,
      ComicLocalDb.worksTable,
      'work_id',
      novelPhase0BaselineNovelId,
    ),
    episode: await _singleBy(
      db,
      ComicLocalDb.workEpisodesTable,
      'episode_id',
      novelPhase0BaselineEpisodeId,
    ),
    content: await _singleBy(
      db,
      ComicLocalDb.novelEpisodeContentTable,
      'episode_id',
      novelPhase0BaselineEpisodeId,
    ),
    shelfItem: await _singleBy(
      db,
      ComicLocalDb.novelShelfItemsTable,
      'novel_id',
      novelPhase0BaselineNovelId,
    ),
    workState: await _singleBy(
      db,
      ComicLocalDb.libraryWorkStateTable,
      'work_id',
      novelPhase0BaselineNovelId,
    ),
    episodeState: await _singleBy(
      db,
      ComicLocalDb.libraryEpisodeStateTable,
      'episode_id',
      novelPhase0BaselineEpisodeId,
    ),
    readingProgress: await _singleBy(
      db,
      ComicLocalDb.novelReadingProgressTable,
      'novel_id',
      novelPhase0BaselineNovelId,
    ),
    bookmark: await _singleBy(
      db,
      ComicLocalDb.readerBookmarksTable,
      'bookmark_id',
      novelPhase0BaselineBookmarkId,
    ),
  );
}

class NovelPhase0PersistenceSnapshot {
  const NovelPhase0PersistenceSnapshot({
    required this.work,
    required this.episode,
    required this.content,
    required this.shelfItem,
    required this.workState,
    required this.episodeState,
    required this.readingProgress,
    required this.bookmark,
  });

  final Map<String, Object?> work;
  final Map<String, Object?> episode;
  final Map<String, Object?> content;
  final Map<String, Object?> shelfItem;
  final Map<String, Object?> workState;
  final Map<String, Object?> episodeState;
  final Map<String, Object?> readingProgress;
  final Map<String, Object?> bookmark;
}

Future<Map<String, Object?>> _singleBy(
  Database db,
  String table,
  String key,
  String value,
) async {
  final rows = await db.query(
    table,
    where: '$key = ?',
    whereArgs: <Object?>[value],
    limit: 1,
  );
  if (rows.length != 1) {
    throw StateError('Expected one $table row for $key=$value.');
  }
  return rows.single;
}
