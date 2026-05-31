import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

class ComicCoverStore {
  ComicCoverStore(this._dbFuture);

  final Future<Database> _dbFuture;

  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'updated_at': now,
    };
    if (coverImageUrl != null) {
      values['cover_image_url'] = _normalizeNullable(coverImageUrl);
    }
    if (coverLocalPath != null) {
      values['cover_local_path'] = _normalizeNullable(coverLocalPath);
    }
    if (customCoverLocalPath != null) {
      values['custom_cover_local_path'] =
          _normalizeNullable(customCoverLocalPath);
      values['metadata_updated_at'] = now;
    }
    await db.update(
      ComicLocalDb.comicsTable,
      values,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  Future<bool> promoteFirstEpisodeCover({
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final db = await _dbFuture;
    return db.transaction<bool>((txn) {
      return promoteFirstEpisodeCoverInTxn(
        txn,
        comicId: comicId,
        episodeId: episodeId,
        imageUrl: imageUrl,
      );
    });
  }

  Future<void> promoteFirstEpisodeCoverIfNeededInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    if (imageUrls.isEmpty) {
      return;
    }
    await promoteFirstEpisodeCoverInTxn(
      executor,
      comicId: comicId,
      episodeId: episodeId,
      imageUrl: imageUrls.first,
    );
  }

  Future<bool> promoteFirstEpisodeCoverInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final normalizedImageUrl = _normalizeNullable(imageUrl);
    if (normalizedImageUrl == null) {
      return false;
    }
    final comics = await executor.query(
      ComicLocalDb.comicsTable,
      columns: const <String>[
        'cover_image_url',
        'cover_local_path',
        'custom_cover_image_url',
        'custom_cover_local_path',
      ],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      limit: 1,
    );
    if (comics.isEmpty) {
      return false;
    }
    final customCover =
        _normalizeNullable(comics.first['custom_cover_image_url'] as String?);
    final customCoverLocalPath = _normalizeNullable(
      comics.first['custom_cover_local_path'] as String?,
    );
    if (customCover != null || customCoverLocalPath != null) {
      return false;
    }

    final episodes = await executor.query(
      ComicLocalDb.episodesTable,
      columns: const <String>['episode_id', 'source_tid', 'order_index'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    if (episodes.isEmpty) {
      return false;
    }
    final orderedEpisodes = episodes.toList(growable: true)
      ..sort(compareEpisodeRowsByFirstTid);
    if (orderedEpisodes.first['episode_id'] != episodeId) {
      return false;
    }

    final currentCover =
        _normalizeNullable(comics.first['cover_image_url'] as String?);
    final currentLocalPath =
        _normalizeNullable(comics.first['cover_local_path'] as String?);
    if (currentCover == normalizedImageUrl && currentLocalPath == null) {
      return false;
    }

    await executor.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'cover_image_url': normalizedImageUrl,
        'cover_local_path': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    return true;
  }

  int compareEpisodeRowsByFirstTid(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final aTid = int.tryParse((a['source_tid'] as String? ?? '').trim());
    final bTid = int.tryParse((b['source_tid'] as String? ?? '').trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    final order = (a['order_index'] as int? ?? 0).compareTo(
      b['order_index'] as int? ?? 0,
    );
    if (order != 0) {
      return order;
    }
    return (a['episode_id'] as String? ?? '').compareTo(
      b['episode_id'] as String? ?? '',
    );
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
