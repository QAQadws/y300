import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

import '../test_support/novel_phase0_persistence_baseline.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('DB 28 novel user-state baseline survives close and reopen', () async {
    final temp = await Directory.systemTemp.createTemp(
      'y300-novel-phase0-baseline-',
    );
    final dbPath = p.join(temp.path, 'phase0.db');
    addTearDown(() async {
      await deleteDatabase(dbPath);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    var db = await ComicLocalDb.open(databaseName: dbPath);
    expect(await db.getVersion(), 28);
    await seedNovelPhase0PersistenceBaseline(db);
    await db.close();

    db = await ComicLocalDb.open(databaseName: dbPath);
    addTearDown(db.close);
    final snapshot = await readNovelPhase0PersistenceBaseline(db);

    expect(snapshot.work, containsPair('work_id', novelPhase0BaselineNovelId));
    expect(snapshot.work, containsPair('title', '迁移基线小说'));
    expect(snapshot.work, containsPair('author', 'INCSKY16'));
    expect(
      snapshot.work,
      containsPair('cover_local_path', 'covers/novel-cover.jpg'),
    );
    expect(
      snapshot.work,
      containsPair('custom_cover_local_path', 'covers/custom-novel-cover.jpg'),
    );

    expect(
      snapshot.episode,
      containsPair('episode_id', novelPhase0BaselineEpisodeId),
    );
    expect(snapshot.episode, containsPair('source_pid', '40692958'));
    expect(snapshot.episode, containsPair('source_page', 2));
    expect(snapshot.episode, containsPair('order_index', 200));
    expect(snapshot.content, containsPair('raw_html', '<p>迁移前正文。</p>'));
    expect(snapshot.content, containsPair('plain_text', '迁移前正文。'));

    expect(snapshot.shelfItem, containsPair('category_id', 'default'));
    expect(snapshot.shelfItem, containsPair('sort_order', 7));
    expect(snapshot.workState, containsPair('intro_text', '用户编辑的简介必须保留。'));
    expect(
      snapshot.workState,
      containsPair('last_read_episode_id', novelPhase0BaselineEpisodeId),
    );

    expect(snapshot.episodeState, containsPair('is_read', 1));
    expect(snapshot.episodeState, containsPair('is_downloaded', 1));
    expect(snapshot.episodeState, containsPair('is_bookmarked', 1));
    expect(snapshot.readingProgress, containsPair('scroll_offset', 345.5));
    expect(snapshot.readingProgress, containsPair('flow_mode', 'pagedLtr'));
    expect(snapshot.readingProgress, containsPair('page_index', 8));
    expect(
      snapshot.readingProgress,
      containsPair('anchor_node_id', 'paragraph-8'),
    );
    expect(snapshot.readingProgress, containsPair('progress_percent', 0.625));

    expect(
      snapshot.bookmark,
      containsPair('bookmark_id', novelPhase0BaselineBookmarkId),
    );
    expect(snapshot.bookmark, containsPair('note', '用户书签备注'));
    expect(snapshot.bookmark, containsPair('progress_percent', 0.625));
  });
}
