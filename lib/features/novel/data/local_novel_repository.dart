import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class LocalNovelRepository implements NovelRepository {
  LocalNovelRepository(
    this._dbFuture, {
    required NovelThreadGateway threadGateway,
    required NovelEpisodeDiscoveryService discoveryService,
  })  : _threadGateway = threadGateway,
        _discoveryService = discoveryService;

  final Future<Database> _dbFuture;
  final NovelThreadGateway _threadGateway;
  final NovelEpisodeDiscoveryService _discoveryService;

  static const String _contentType = 'novel';
  static const int _maxRefreshPages = 20;

  @override
  Future<List<NovelItem>> getShelfItems({String? sourceFid}) async {
    final db = await _dbFuture;
    final whereParts = <String>['w.content_type = ?'];
    final whereArgs = <Object>[_contentType];
    if (sourceFid != null && sourceFid.trim().isNotEmpty) {
      whereParts.add('w.source_fid = ?');
      whereArgs.add(sourceFid.trim());
    }

    final rows = await db.rawQuery('''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.title,
        w.author,
        w.cover_image_url,
        w.updated_at,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.worksTable} w
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE ${whereParts.join(' AND ')}
      GROUP BY w.work_id
      ORDER BY w.updated_at DESC
    ''', <Object>[_contentType, ...whereArgs]);

    return rows.map(_rowToNovelItem).toList(growable: false);
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.title,
        w.author,
        w.cover_image_url,
        w.updated_at,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.worksTable} w
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE w.work_id = ? AND w.content_type = ?
      GROUP BY w.work_id
      LIMIT 1
    ''', <Object>[_contentType, novelId, _contentType]);

    if (rows.isEmpty) {
      return null;
    }
    return _rowToNovelItem(rows.first);
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.workEpisodesTable,
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
      orderBy: 'order_index ${descending ? 'DESC' : 'ASC'}',
    );

    return rows
        .map(
          (row) => NovelEpisodeItem(
            episodeId: row['episode_id'] as String,
            novelId: row['work_id'] as String,
            sourceTid: row['source_tid'] as String,
            sourcePid: row['source_pid'] as String?,
            sourcePage: row['source_page'] as int?,
            episodeTitle: (row['episode_title'] as String?) ?? '未命名章节',
            orderIndex: row['order_index'] as int,
            datelineText: row['dateline_text'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelEpisodeContentTable,
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final paragraphJson = (row['paragraph_json'] as String?) ?? '[]';
    final paragraphs = (jsonDecode(paragraphJson) as List<dynamic>)
        .map((item) => item.toString())
        .toList(growable: false);

    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: (row['raw_html'] as String?) ?? '',
      plainText: (row['plain_text'] as String?) ?? '',
      paragraphs: paragraphs,
    );
  }

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.readerPreferencesTable,
      <String, Object?>{
        'content_type': _contentType,
        'font_size': preferences.fontSize,
        'line_height': preferences.lineHeight,
        'paragraph_spacing': preferences.paragraphSpacing,
        'page_padding': preferences.pagePadding,
        'theme_mode': preferences.themeMode,
        'font_family': preferences.fontFamily,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readerPreferencesTable,
      where: 'content_type = ?',
      whereArgs: <Object>[_contentType],
      limit: 1,
    );
    if (rows.isEmpty) {
      return NovelReaderPreferences.defaults();
    }

    final row = rows.first;
    return NovelReaderPreferences(
      fontSize: (row['font_size'] as num?)?.toDouble() ?? 18,
      lineHeight: (row['line_height'] as num?)?.toDouble() ?? 1.8,
      paragraphSpacing: (row['paragraph_spacing'] as num?)?.toDouble() ?? 10,
      pagePadding: (row['page_padding'] as num?)?.toDouble() ?? 16,
      themeMode: (row['theme_mode'] as String?) ?? 'light',
      fontFamily: (row['font_family'] as String?) ?? 'system',
    );
  }

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {
    final detail = await _threadGateway.getThreadDetail(tid: seed.tid, page: 1);
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      ComicLocalDb.worksTable,
      <String, Object?>{
        'work_id': _buildNovelId(seed.fid, seed.tid),
        'content_type': _contentType,
        'source_tid': detail.tid,
        'source_fid': seed.fid,
        'title': detail.subject.trim().isEmpty ? '未命名小说' : detail.subject.trim(),
        'author': detail.author.trim().isEmpty ? null : detail.author.trim(),
        'cover_image_url': null,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    final detail = await getDetail(novelId: novelId);
    if (detail == null) {
      throw StateError('小说不存在');
    }

    final pages = await _fetchPages(tid: detail.sourceTid);
    final plan = _discoveryService.buildPlan(novelId: novelId, pages: pages);
    final db = await _dbFuture;
    var inserted = 0;
    var updated = 0;

    await db.transaction((txn) async {
      for (final draft in plan.episodes) {
        final existing = await txn.query(
          ComicLocalDb.workEpisodesTable,
          columns: <String>['episode_id'],
          where: 'episode_id = ?',
          whereArgs: <Object>[draft.episodeId],
          limit: 1,
        );

        await txn.insert(
          ComicLocalDb.workEpisodesTable,
          <String, Object?>{
            'episode_id': draft.episodeId,
            'work_id': novelId,
            'content_type': _contentType,
            'source_tid': draft.sourceTid,
            'source_pid': draft.sourcePid,
            'source_page': draft.sourcePage,
            'episode_title': draft.episodeTitle,
            'order_index': draft.orderIndex,
            'dateline_text': draft.datelineText,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.insert(
          ComicLocalDb.novelEpisodeContentTable,
          <String, Object?>{
            'episode_id': draft.episodeId,
            'raw_html': draft.rawHtml,
            'plain_text': draft.plainText,
            'paragraph_json': jsonEncode(draft.paragraphs),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (existing.isEmpty) {
          inserted++;
        } else {
          updated++;
        }
      }

      await txn.update(
        ComicLocalDb.worksTable,
        <String, Object?>{
          'title': plan.subject.trim().isEmpty ? detail.title : plan.subject.trim(),
          'author': plan.author.trim().isEmpty ? detail.author : plan.author.trim(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });

    final total = await getEpisodes(novelId: novelId);
    return NovelEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: total.length,
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.novelReadingProgressTable,
      <String, Object?>{
        'novel_id': novelId,
        'episode_id': episodeId,
        'scroll_offset': scrollOffset,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelReadingProgressTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final episodeId = (row['episode_id'] as String?) ?? '';
    if (episodeId.isEmpty) {
      return null;
    }

    return NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: (row['scroll_offset'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
    );
  }

  String _buildNovelId(String fid, String tid) => 'novel:$fid:$tid';

  NovelItem _rowToNovelItem(Map<String, Object?> row) {
    return NovelItem(
      novelId: row['work_id'] as String,
      sourceTid: row['source_tid'] as String,
      sourceFid: row['source_fid'] as String,
      title: row['title'] as String,
      author: row['author'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
      episodeCount: (row['episode_count'] as int?) ?? 0,
    );
  }

  Future<List<ThreadDetailData>> _fetchPages({required String tid}) async {
    final pages = <ThreadDetailData>[];
    for (var page = 1; page <= _maxRefreshPages; page++) {
      final detail = await _threadGateway.getThreadDetail(tid: tid, page: page);
      if (detail.posts.isEmpty) {
        break;
      }
      pages.add(detail);
      if (!detail.hasMore || detail.posts.length < detail.perPage) {
        break;
      }
    }
    return pages;
  }
}
