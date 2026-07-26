import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';

/// 章节管理写入端。
///
/// 与 [ComicEpisodeStore] 的解析写入路径分开：解析侧关心“来源发现了什么”，
/// 这里关心“用户对章节做了什么”。两者混在一个类里会让刷新流程和用户编辑
/// 互相牵连，也很难分别测试。
class ComicEpisodeManagementStore {
  ComicEpisodeManagementStore(this._dbFuture);

  final Future<Database> _dbFuture;

  /// 追加一条手动章节。
  ///
  /// 章节 id 沿用 `comicId:tid`，因此阅读器的 API 请求与原帖跳转都能直接复用
  /// 既有 `sourceTid` 拼接实现，不需要为手动章节维护第二套定位方式。
  /// 返回 false 表示该 tid 已存在（解析或手动），调用方据此提示用户。
  Future<bool> addManualEpisode({
    required String comicId,
    required String sourceTid,
    required String sourceUrl,
    String? episodeTitle,
  }) async {
    final db = await _dbFuture;
    final episodeId = '$comicId:$sourceTid';
    return db.transaction<bool>((txn) async {
      final existing = await txn.query(
        ComicLocalDb.episodesTable,
        columns: <String>['episode_id'],
        where: 'episode_id = ?',
        whereArgs: <Object>[episodeId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return false;
      }

      // 排在现有章节之后。真正的阅读顺序由 ComicEpisodeSequence 按 tid 排序
      // 决定，这里只保证 order_index 唯一且不与解析章节抢占位置。
      final maxOrderRows = await txn.rawQuery(
        'SELECT MAX(order_index) AS max_order FROM '
        '${ComicLocalDb.episodesTable} WHERE comic_id = ?',
        <Object>[comicId],
      );
      final maxOrder = maxOrderRows.isEmpty
          ? null
          : maxOrderRows.first['max_order'] as int?;

      await txn.insert(
        ComicLocalDb.episodesTable,
        EpisodeRecord.resolved(
          episodeId: episodeId,
          comicId: comicId,
          // 手动章节的“来源名”就是添加时的默认名。重命名同样写进 custom 列，
          // 于是清空重命名会退回这个默认名，而不是退成空标题。
          sourceEpisodeTitle: _normalizeTitle(episodeTitle) ?? '章节 $sourceTid',
          sourceTid: sourceTid,
          sourceUrl: sourceUrl,
          orderIndex: (maxOrder ?? -1) + 1,
          publishTimeText: null,
          isManual: true,
        ).toMap(),
      );
      await _touchComic(txn, comicId);
      return true;
    });
  }

  /// 移除手动章节。解析章节会被拒绝，避免刷新后“删了又回来”。
  ///
  /// 章节图片、阅读进度和下载队列行都挂在 episode_id 外键上随级联删除；
  /// `library_*_state` 是跨模块共享表、没有外键，这里显式清掉孤儿状态行与
  /// 仍指向已删章节的“上次阅读”指针。
  Future<bool> removeManualEpisode({
    required String comicId,
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        ComicLocalDb.episodesTable,
        columns: <String>['is_manual'],
        where: 'episode_id = ? AND comic_id = ?',
        whereArgs: <Object>[episodeId, comicId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.first['is_manual'] as int? ?? 0) != 1) {
        return false;
      }

      await txn.delete(
        ComicLocalDb.episodesTable,
        where: 'episode_id = ? AND comic_id = ?',
        whereArgs: <Object>[episodeId, comicId],
      );
      await txn.delete(
        ComicLocalDb.libraryEpisodeStateTable,
        where: 'content_type = ? AND episode_id = ?',
        whereArgs: <Object>['comic', episodeId],
      );
      await txn.delete(
        ComicLocalDb.readingProgressTable,
        where: 'comic_id = ? AND episode_id = ?',
        whereArgs: <Object>[comicId, episodeId],
      );
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{'last_read_episode_id': null},
        where: 'comic_id = ? AND last_read_episode_id = ?',
        whereArgs: <Object>[comicId, episodeId],
      );
      await txn.update(
        ComicLocalDb.libraryWorkStateTable,
        <String, Object?>{'last_read_episode_id': null},
        where: 'content_type = ? AND work_id = ? AND last_read_episode_id = ?',
        whereArgs: <Object>['comic', comicId, episodeId],
      );
      await _touchComic(txn, comicId);
      return true;
    });
  }

  Future<void> setEpisodeHidden({
    required String comicId,
    required String episodeId,
    required bool isHidden,
  }) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.update(
        ComicLocalDb.episodesTable,
        <String, Object?>{'is_hidden': isHidden ? 1 : 0},
        where: 'episode_id = ? AND comic_id = ?',
        whereArgs: <Object>[episodeId, comicId],
      );
      await _touchComic(txn, comicId);
    });
  }

  /// 重命名章节。传入 null 或空白清除自定义名，章节名回退到来源名。
  ///
  /// 只写 `custom_episode_title` 并同步展示列，`source_episode_title` 保持不动：
  /// 来源名是解析结果，用户改名不该把它一起改掉，否则就再也回不去了。
  /// 返回 false 表示章节不存在。
  Future<bool> setEpisodeCustomTitle({
    required String comicId,
    required String episodeId,
    required String? customTitle,
  }) async {
    final db = await _dbFuture;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        ComicLocalDb.episodesTable,
        columns: <String>['source_episode_title', 'source_tid'],
        where: 'episode_id = ? AND comic_id = ?',
        whereArgs: <Object>[episodeId, comicId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return false;
      }
      final normalized = _normalizeTitle(customTitle);
      final sourceTitle = rows.first['source_episode_title'] as String?;
      await txn.update(
        ComicLocalDb.episodesTable,
        <String, Object?>{
          'custom_episode_title': normalized,
          'episode_title': resolveEpisodeDisplayTitle(
            customEpisodeTitle: normalized,
            sourceEpisodeTitle: sourceTitle,
          ),
        },
        where: 'episode_id = ? AND comic_id = ?',
        whereArgs: <Object>[episodeId, comicId],
      );
      await _touchComic(txn, comicId);
      return true;
    });
  }

  /// 批量设置整部漫画章节的显示状态，用于面板上的“全部显示/全部隐藏”。
  Future<int> setAllEpisodesHidden({
    required String comicId,
    required bool isHidden,
  }) async {
    final db = await _dbFuture;
    return db.transaction<int>((txn) async {
      final affected = await txn.update(
        ComicLocalDb.episodesTable,
        <String, Object?>{'is_hidden': isHidden ? 1 : 0},
        where: 'comic_id = ? AND is_hidden = ?',
        whereArgs: <Object>[comicId, isHidden ? 0 : 1],
      );
      if (affected > 0) {
        await _touchComic(txn, comicId);
      }
      return affected;
    });
  }

  Future<void> _touchComic(DatabaseExecutor executor, String comicId) {
    return executor.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  String? _normalizeTitle(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
