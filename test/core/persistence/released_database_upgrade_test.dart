import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/core/persistence/app_database_migrations.dart';

import 'fixtures/released_database_schemas.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String databasePath;
  Database? database;
  Database? fresh;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('released-db-upgrade-');
    databasePath = p.join(directory.path, 'installed.db');
  });
  tearDown(() async {
    await database?.close();
    await fresh?.close();
    database = null;
    fresh = null;
    await directory.delete(recursive: true);
  });

  Future<Database> install(int version) async {
    final db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: _enableForeignKeys,
        onCreate: (db, _) => createReleasedDatabaseFixture(db, version),
      ),
    );
    database = db;
    return db;
  }

  for (final release in releasedDatabaseTags.entries) {
    for (final tag in release.value) {
      test(
        '$tag database v${release.key} opens directly at v43 without losing user data',
        () async {
          var db = await install(release.key);
          final media = await _seedUserData(db, directory);
          final before = await _snapshot(db);
          expect(await db.getVersion(), release.key);
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          await db.close();

          db = await AppDatabase.open(databaseName: databasePath);
          database = db;
          expect(await db.getVersion(), 43);
          await _expectOldFields(db, before);
          await _expectCurrentSemantics(db, release.key);
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          expect(
            (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
            'ok',
          );
          expect(await media.readAsBytes(), _mediaBytes);

          fresh = await AppDatabase.open(
            databaseName: p.join(directory.path, 'fresh.db'),
          );
          await _expectCurrentSchema(db, fresh!);
          final upgraded = await _snapshot(db);
          await db.close();
          db = await AppDatabase.open(databaseName: databasePath);
          database = db;
          expect(await _snapshot(db), upgraded);

          // Both primary-key migrations must permit a second chapter without
          // replacing the pre-upgrade location in the first chapter.
          await db.insert(AppDatabase.readingProgressTable, {
            'comic_id': 'comic',
            'episode_id': 'comic-b',
            'image_index': 2,
            'scroll_offset': 15.0,
            'updated_at': 200,
          });
          await db.insert(AppDatabase.novelReadingProgressTable, {
            'novel_id': 'novel',
            'episode_id': 'novel-b',
            'scroll_offset': 40.0,
            'updated_at': 201,
          });
          expect(
            await db.query(AppDatabase.readingProgressTable),
            hasLength(2),
          );
          expect(
            await db.query(AppDatabase.novelReadingProgressTable),
            hasLength(2),
          );
          expect(
            (await db.query(
              AppDatabase.novelReadingProgressTable,
              where: 'episode_id = ?',
              whereArgs: ['novel-a'],
            )).single['anchor_text_offset'],
            before[AppDatabase.novelReadingProgressTable]!
                    .single['anchor_text_offset'] ??
                0,
          );
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        },
      );
    }
  }

  test(
    'an installation upgraded through every release retains its data',
    () async {
      var db = await install(27);
      final media = await _seedUserData(db, directory);
      for (final version in releasedDatabaseTags.keys.skip(1)) {
        final before = await _snapshot(db);
        await db.close();
        db = await databaseFactory.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: version,
            onConfigure: _enableForeignKeys,
            onUpgrade: upgradeAppDatabaseSchema,
          ),
        );
        database = db;
        expect(await db.getVersion(), version);
        await _expectOldFields(db, before);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      }
      await _expectCurrentSemantics(db, 27);
      fresh = await AppDatabase.open(
        databaseName: p.join(directory.path, 'fresh.db'),
      );
      await _expectCurrentSchema(db, fresh!);
      expect(await media.readAsBytes(), _mediaBytes);
    },
  );

  test('a late release-upgrade failure rolls schema, version and user rows back together', () async {
    var db = await install(27);
    await _seedUserData(db, directory);
    await db.execute('''
      CREATE TRIGGER injected_release_upgrade_failure
      BEFORE UPDATE ON library_work_state
      WHEN NEW.content_type = 'novel'
      BEGIN
        SELECT RAISE(ABORT, 'injected late release-upgrade failure');
      END
    ''');
    final before = await _snapshot(db);
    final oldSchema = await _schemaSql(db);
    await db.close();
    await expectLater(
      AppDatabase.open(databaseName: databasePath),
      throwsA(
        isA<DatabaseException>().having(
          (error) => error.toString(),
          'the intended late migration fault',
          contains('injected late release-upgrade failure'),
        ),
      ),
    );

    db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(onConfigure: _enableForeignKeys),
    );
    database = db;
    expect(await db.getVersion(), 27);
    expect(await _snapshot(db), before);
    expect(await _schemaSql(db), oldSchema);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.execute('DROP TRIGGER injected_release_upgrade_failure');
    await db.close();

    db = await AppDatabase.open(databaseName: databasePath);
    database = db;
    expect(await db.getVersion(), 43);
    await _expectOldFields(db, before);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

Future<void> _enableForeignKeys(Database db) =>
    db.execute('PRAGMA foreign_keys = ON');

const _mediaBytes = [255, 216, 255, 224, 7, 8, 9, 255, 217];

Future<File> _seedUserData(Database db, Directory directory) async {
  final media = File(p.join(directory.path, 'retained-user-image.jpg'));
  await media.writeAsBytes(_mediaBytes);
  Future<void> put(String table, Map<String, Object?> values) async {
    final columns = await db.rawQuery('PRAGMA table_info("$table")');
    if (columns.isEmpty) {
      return;
    }
    final names = columns.map((column) => column['name']).toSet();
    await db.insert(table, {
      for (final entry in values.entries)
        if (names.contains(entry.key)) entry.key: entry.value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  await put('comics', {
    'comic_id': 'comic',
    'source_tid': '100',
    'source_fid': '30',
    'source_typeid': '7',
    'source_tag_name': '保留标签',
    'title': '漫画展示名',
    'source_title': '原帖标题',
    'custom_title': '我的漫画标题',
    'author': '展示作者',
    'source_author': '原作者',
    'custom_author': '自定义作者',
    'translation_group': '展示组',
    'source_translation_group': '原组',
    'custom_translation_group': '我的组',
    'custom_search_title': '搜索名',
    'cover_image_url': 'https://img.example.test/original.jpg',
    'custom_cover_image_url': 'https://img.example.test/custom.jpg',
    'cover_local_path': media.path,
    'custom_cover_local_path': media.path,
    'cover_revision': 7,
    'custom_cover_revision': 8,
    'custom_cover_source_episode_id': 'comic-a',
    'custom_cover_source_image_index': 0,
    'custom_cover_source_image_url': 'https://img.example.test/custom.jpg',
    'custom_cover_focus_x': 0.25,
    'custom_cover_focus_y': 0.75,
    'metadata_updated_at': 88,
    'created_at': 1,
    'updated_at': 99,
    'last_read_episode_id': 'comic-a',
    'catalog_url': 'https://bbs.yamibo.com/thread-100-1-1.html',
    'custom_catalog_url': 'https://bbs.yamibo.com/thread-105-1-1.html',
  });
  for (final (id, tid, order) in [
    ('comic-a', '101', 0),
    ('comic-b', '102', 1),
  ]) {
    await put('episodes', {
      'episode_id': id,
      'comic_id': 'comic',
      'source_tid': tid,
      'source_url': 'https://bbs.yamibo.com/thread-$tid-1-1.html',
      'episode_title': '保留章节 $id',
      'source_episode_title': '原章节 $id',
      'custom_episode_title': '我的章节 $id',
      'order_index': order,
      'publish_time_text': '原日期',
      'is_manual': 1,
      'is_hidden': 1,
    });
  }
  await put('episode_images', {
    'id': 31,
    'episode_id': 'comic-a',
    'image_index': 0,
    'image_url': 'https://img.example.test/page.jpg',
    'stable_cache_key': 'image-key',
    'last_source_url': 'https://img.example.test/page.jpg',
    'local_path': media.path,
    'cache_local_path': media.path,
    'cache_status': 'downloaded',
    'width': 800,
    'height': 1200,
    'bytes': _mediaBytes.length,
    'mime_type': 'image/jpeg',
    'last_accessed_at': 90,
    'protected': 1,
  });
  await put('categories', {
    'category_id': 'comic-category',
    'name': '我的漫画分类',
    'sort_order': 9,
    'created_at': 2,
  });
  await put('shelf_items', {
    'id': 32,
    'category_id': 'comic-category',
    'comic_id': 'comic',
    'added_at': 3,
    'sort_order': 4,
  });
  await put('settings', {'key': 'retained_setting', 'value': '保留设置'});
  await put('reading_progress', {
    'comic_id': 'comic',
    'episode_id': 'comic-a',
    'image_index': 6,
    'scroll_offset': 32.5,
    'updated_at': 99,
  });
  await put('works', {
    'work_id': 'novel',
    'content_type': 'novel',
    'source_tid': '200',
    'source_fid': '49',
    'source_typeid': '8',
    'source_tag_name': '小说标签',
    'title': '小说原题',
    'custom_title': '我的小说标题',
    'author': '小说作者',
    'cover_image_url': 'https://img.example.test/novel.jpg',
    'cover_local_path': media.path,
    'custom_cover_local_path': media.path,
    'cover_revision': 9,
    'custom_cover_revision': 10,
    'custom_cover_focus_x': 0.3,
    'custom_cover_focus_y': 0.6,
    'cover_hidden': 1,
    'updated_at': 100,
  });
  for (final (id, pid, order) in [
    ('novel-a', '2001', 0),
    ('novel-b', '2002', 1),
  ]) {
    await put('work_episodes', {
      'episode_id': id,
      'work_id': 'novel',
      'content_type': 'novel',
      'source_tid': '200',
      'source_pid': pid,
      'source_page': 3,
      'episode_title': '小说章节 $id',
      'order_index': order,
      'dateline_text': '旧日期',
    });
  }
  await put('novel_episode_content', {
    'episode_id': 'novel-a',
    'raw_html': '<p>用户已缓存正文👩‍👩‍👧‍👦</p>',
    'plain_text': '用户已缓存正文👩‍👩‍👧‍👦',
    'paragraph_json': '["保留正文"]',
    'updated_at': 110,
  });
  await put('reader_preferences', {
    'content_type': 'novel',
    'font_size': 23.0,
    'line_height': 1.8,
    'paragraph_spacing': 12.0,
    'page_padding': 20.0,
    'theme_mode': 'dark',
    'font_family': 'Noto Serif',
    'flow_mode': 'pagedRtl',
    'theme_preset': 'night',
    'content_max_width': 700.0,
    'first_line_indent': 2.0,
    'font_weight': 500,
    'text_align': 'justify',
    'show_progress_indicator': 0,
    'show_chapter_title': 1,
    'conversion_mode': 'traditional',
  });
  await put('novel_reading_progress', {
    'novel_id': 'novel',
    'episode_id': 'novel-a',
    'scroll_offset': 125.5,
    'flow_mode': 'pagedLtr',
    'page_index': 3,
    'page_count': 9,
    'anchor_node_id': 'legacy-node',
    'anchor_text_offset': 1 << 35,
    'pagination_key': 'legacy-layout',
    'progress_percent': 0.375,
    'anchor_format_version': 99,
    'anchor_text_identity': ' opaque text identity ',
    'progress_percent_valid': null,
    'percent_basis': 'legacyReaderLayout',
    'updated_at': 123,
  });
  await put('reader_bookmarks', {
    'bookmark_id': 'bookmark',
    'novel_id': 'novel',
    'episode_id': 'novel-a',
    'node_id': 'old-node',
    'text_offset': 7,
    'page_index': 3,
    'scroll_offset': 125.5,
    'progress_percent': 0.375,
    'anchor_format_version': 99,
    'anchor_text_identity': ' opaque bookmark ',
    'progress_percent_valid': null,
    'title': '旧书签',
    'snippet': '旧片段👩‍👩‍👧‍👦',
    'note': '不得丢失的笔记',
    'created_at': 100,
    'updated_at': 123,
  });
  await put('novel_categories', {
    'category_id': 'novel-category',
    'name': '我的小说分类',
    'sort_order': 8,
    'created_at': 2,
  });
  await put('novel_shelf_items', {
    'id': 33,
    'category_id': 'novel-category',
    'novel_id': 'novel',
    'added_at': 3,
    'sort_order': 5,
  });
  for (final (kind, work, episode, time) in [
    ('comic', 'comic', 'comic-a', 99),
    ('novel', 'novel', 'novel-a', 123),
  ]) {
    await put('library_work_state', {
      'content_type': kind,
      'work_id': work,
      'last_read_episode_id': episode,
      'last_read_at': time,
      'check_updated_at': 72,
      'fetched_updated_at': 73,
      'intro_text': '本地手写简介 $kind',
      'created_at': 1,
      'updated_at': time,
    });
    await put('library_episode_state', {
      'content_type': kind,
      'episode_id': episode,
      'work_id': work,
      'is_read': 1,
      'read_state_version': 1,
      'is_downloaded': 1,
      'is_bookmarked': 1,
      'read_at': 90,
      'downloaded_at': 91,
    });
  }
  await put('library_tags', {'tag_id': 'tag', 'name': '用户标签', 'created_at': 4});
  await put('library_work_tags', {
    'content_type': 'novel',
    'work_id': 'novel',
    'tag_id': 'tag',
  });
  await put('library_display_settings', {
    'module_key': 'novel',
    'display_mode': 'grid',
    'grid_columns': 5,
    'updated_at': 92,
  });
  await put('favorite_sync_state', {
    'sync_key': 'retained-sync',
    'remote_count': 2,
    'local_active_count': 1,
    'last_synced_at': 93,
    'last_full_synced_at': 94,
    'status': 'done',
    'message': '保留同步说明',
  });
  await put('favorite_categories', {
    'category_id': 'favorite-category',
    'name': '我的收藏分类',
    'sort_order': 6,
    'created_at': 4,
  });
  for (final (tid, kind, work, removed) in [
    ('100', 'comic', 'comic', null),
    ('200', 'novel', 'novel', 98),
  ]) {
    await put('favorite_threads', {
      'tid': tid,
      'favid': 'server-$tid',
      'title': '收藏 $tid',
      'description': '保留备注 $tid',
      'author': '原作者',
      'replies': 12,
      'url': 'https://bbs.yamibo.com/thread-$tid-1-1.html',
      'dateline': 5,
      'remote_order': 6,
      'source_fid': '30',
      'source_typeid': '7',
      'source_tag_name': '来源标签',
      'content_kind': kind,
      'work_id': work,
      'detail_loaded_at': 95,
      'detail_state': 'resolved',
      'first_seen_at': 3,
      'last_seen_at': 96,
      'removed_at': removed,
    });
    await put('favorite_thread_category', {
      'tid': tid,
      'category_id': 'favorite-category',
      'assigned_at': 97,
    });
  }
  await put('cached_images', {
    'cache_key': 'retained-image',
    'owner_type': 'comic',
    'owner_id': 'comic',
    'episode_id': 'comic-a',
    'image_index': 0,
    'role': 'episode',
    'last_source_url': 'https://img.example.test/page.jpg',
    'local_path': media.path,
    'bytes': _mediaBytes.length,
    'mime_type': 'image/jpeg',
    'width': 800,
    'height': 1200,
    'protected': 1,
    'retention_class': 'longTerm',
    'etag': 'keep-etag',
    'content_hash': 'keep-hash',
    'created_at': 1,
    'updated_at': 2,
    'last_accessed_at': 3,
  });
  await put('cached_documents', {
    'cache_key': 'retained-document',
    'namespace': 'thread',
    'owner_type': 'novel',
    'owner_id': 'novel',
    'source_url': 'https://bbs.yamibo.com/thread-200-1-1.html',
    'request_profile': 'logged_in',
    'body': '<p>保留HTML正文</p>',
    'content_type': 'text/html',
    'status_code': 200,
    'body_bytes': 40,
    'fetched_at': 1,
    'updated_at': 2,
    'last_accessed_at': 3,
  });
  await put('cached_snapshots', {
    'cache_key': 'retained-snapshot',
    'owner_type': 'novel',
    'owner_id': 'novel',
    'snapshot_type': 'thread',
    'retain_long_term': 1,
    'codec_version': 2,
    'parser_version': 3,
    'source_document_key': 'retained-document',
    'payload_json': '{"title":"保留快照"}',
    'payload_bytes': 24,
    'created_at': 1,
    'updated_at': 2,
    'last_accessed_at': 3,
    'stale_at': 4,
    'expires_at': 5,
  });
  await put('library_cover_migrations', {
    'asset_id': 'comic:comic:cover',
    'revision': 7,
    'kind': 'comic',
    'completed_at': 80,
  });
  await put('comic_cover_merge_operations', {
    'operation_id': 'merge',
    'target_comic_id': 'comic',
    'state': 'prepared',
    'created_at': 70,
    'updated_at': 71,
  });
  await put('comic_cover_merge_members', {
    'operation_id': 'merge',
    'source_comic_id': 'old-comic',
  });
  await put('comic_cover_merge_assets', {
    'operation_id': 'merge',
    'kind': 'cover',
    'source_comic_id': 'old-comic',
    'source_asset_id': 'old-asset',
    'source_revision': 4,
    'target_asset_id': 'asset',
    'target_revision': 7,
    'mode': 'move',
  });
  await put('comic_search_refresh_queue', {
    'id': 34,
    'comic_id': 'comic',
    'source_tid': '100',
    'title': '队列标题',
    'display_title': '展示名',
    'source_title': '原名',
    'custom_title': '用户名',
    'custom_search_title': '搜索名',
    'origin': 'favorite',
    'status': 'waiting',
    'attempts': 2,
    'available_at': 81,
    'started_at': 82,
    'completed_at': null,
    'last_error': '保留等待原因',
    'created_at': 79,
    'updated_at': 83,
  });
  await put('comic_download_queue', {
    'id': 35,
    'comic_id': 'comic',
    'episode_id': 'comic-a',
    'comic_title': '漫画',
    'episode_title': '章节',
    'status': 'paused',
    'completed_images': 1,
    'total_images': 10,
    'last_error': '保留下载进度',
    'created_at': 84,
    'updated_at': 85,
  });
  await put('novel_source_state', {
    'novel_id': 'novel',
    'publisher_id': '123',
    'publisher_name': '来源作者',
    'first_post_pid': '2001',
    'source_intro': '来源简介',
    'source_catalog_json': '[{"pid":"2001","title":"保留目录"}]',
    'metadata_source_version': 1,
    'hydration_state': 'hydrated',
    'metadata_ingested_at': 50,
    'chapters_hydrated_at': 51,
    'last_completed_author_page': 3,
    'last_seen_pid': '2002',
    'last_sync_at': 52,
    'last_error': '历史原因',
  });
  await put('novel_episode_sync_staging', {
    'run_id': 'sync',
    'novel_id': 'novel',
    'episode_id': 'novel-c',
    'source_tid': '200',
    'source_pid': '2003',
    'source_page': 4,
    'author_filtered_page': 4,
    'episode_title': '待提交章节',
    'order_index': 2,
    'dateline_text': '原日期',
    'raw_html': '<p>暂存正文</p>',
    'plain_text': '暂存正文',
    'paragraph_json': '["暂存正文"]',
    'created_at': 53,
  });
  return media;
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return {
    for (final table in tables)
      table['name'] as String: await db.query(
        table['name'] as String,
        orderBy: 'rowid',
      ),
  };
}

Future<void> _expectOldFields(
  Database db,
  Map<String, List<Map<String, Object?>>> before,
) async {
  for (final entry in before.entries) {
    final after = await db.query(entry.key, orderBy: 'rowid');
    expect(
      after,
      hasLength(entry.value.length),
      reason: '${entry.key} row count',
    );
    for (var i = 0; i < entry.value.length; i++) {
      final previous = entry.value[i];
      expect(
        {for (final key in previous.keys) key: after[i][key]},
        previous,
        reason: '${entry.key}[$i] preserves every previously stored field',
      );
    }
  }
}

Future<void> _expectCurrentSemantics(Database db, int oldVersion) async {
  if (oldVersion == 27) {
    final source = (await db.query(
      AppDatabase.novelSourceStateTable,
      where: 'novel_id = ?',
      whereArgs: ['novel'],
    )).single;
    expect(source['hydration_state'], 'legacyNeedsRebuild');
    expect(source['publisher_name'], '小说作者');
    expect(source['source_catalog_json'], '[]');
  }
  if (oldVersion < 36) {
    final favorites = await db.query(AppDatabase.favoriteThreadsTable);
    expect(favorites, hasLength(2));
    expect(favorites.every((row) => row['detail_loaded_at'] == 95), isTrue);
    expect(
      favorites.map((row) => row['detail_state']),
      everyElement('resolved'),
    );
  }
  if (oldVersion < 40) {
    final comic = (await db.query(AppDatabase.comicsTable)).single;
    final novel = (await db.query(AppDatabase.worksTable)).single;
    expect(comic['cover_revision'], 1);
    expect(comic['custom_cover_revision'], 1);
    expect(novel['cover_revision'], 1);
    expect(novel['custom_cover_revision'], 1);
  }
  if (oldVersion < 38) {
    final chapter = (await db.query(
      AppDatabase.episodesTable,
      where: 'episode_id = ?',
      whereArgs: ['comic-a'],
    )).single;
    expect(chapter['is_manual'], 0);
    expect(chapter['is_hidden'], 0);
    expect(chapter['source_episode_title'], chapter['episode_title']);
    expect(chapter['custom_episode_title'], isNull);
  }
  final progress = (await db.query(AppDatabase.novelReadingProgressTable))
      .single;
  expect(progress['percent_basis'], 'legacyReaderLayout');
  if (oldVersion < 42) {
    expect(progress['anchor_format_version'], 0);
    expect(progress['anchor_text_identity'], isNull);
    expect(progress['progress_percent_valid'], isNull);
  } else {
    expect(progress['anchor_format_version'], 99);
    expect(progress['anchor_text_identity'], ' opaque text identity ');
  }
  final recent = (await db.query(
    AppDatabase.libraryWorkStateTable,
    where: 'content_type = ?',
    whereArgs: ['novel'],
  )).single;
  expect(recent['last_read_episode_id'], 'novel-a');
  expect(recent['last_read_at'], 123);
}

Future<void> _expectCurrentSchema(Database installed, Database fresh) async {
  final freshTables = await fresh.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  for (final table in freshTables) {
    final name = table['name'] as String;
    final expected = await _columnShape(fresh, name);
    final actual = await _columnShape(installed, name);
    expect(actual.keys, containsAll(expected.keys), reason: '$name columns');
    for (final column in expected.entries) {
      expect(
        actual[column.key],
        column.value,
        reason: '$name.${column.key} shape',
      );
    }
  }
  final freshIndexes = await _namedObjects(fresh, 'index');
  final installedIndexes = await _namedObjects(installed, 'index');
  expect(installedIndexes, containsAll(freshIndexes));
  final freshTriggers = await _namedObjects(fresh, 'trigger');
  final installedTriggers = await _namedObjects(installed, 'trigger');
  expect(installedTriggers, containsAll(freshTriggers));
}

Future<Map<String, Map<String, Object?>>> _columnShape(
  Database db,
  String table,
) async => {
  for (final row in await db.rawQuery('PRAGMA table_info("$table")'))
    row['name'] as String: {
      for (final property in ['type', 'notnull', 'dflt_value', 'pk'])
        property: row[property],
    },
};

Future<List<String>> _namedObjects(Database db, String type) async => [
  for (final row in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%' ORDER BY name",
    [type],
  ))
    row['name'] as String,
];

Future<List<Map<String, Object?>>> _schemaSql(Database db) => db.rawQuery(
  "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
);
