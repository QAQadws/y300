import 'package:sqflite/sqflite.dart';

import '../app_database_tables.dart';
import 'migration_helpers.dart';

/// Phase 04：统一图片缓存表。
///
/// 开发阶段不维护逐版本图片缓存迁移；最新版 schema 已直接包含
/// `episode_images` 与作品封面的本地路径字段，这里只补独立缓存表
/// 和与最新版读取路径有关的索引。
Future<void> createImageCacheTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedImagesTable (
        cache_key TEXT PRIMARY KEY,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        episode_id TEXT,
        image_index INTEGER,
        role TEXT NOT NULL,
        last_source_url TEXT,
        local_path TEXT,
        bytes INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        width INTEGER,
        height INTEGER,
        protected INTEGER NOT NULL DEFAULT 0,
        retention_class TEXT NOT NULL DEFAULT 'ephemeral',
        etag TEXT,
        content_hash TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_images_owner ON '
    '$cachedImagesTable(owner_type, owner_id, role)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_images_prune ON '
    '$cachedImagesTable(protected, retention_class, last_accessed_at, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_episode_images_stable_key ON '
    '$episodeImagesTable(stable_cache_key)',
  );
}

/// 原生模式 Phase 3：HTML 文档缓存。
///
/// 只保存 GET 页面 HTML；评分、点评、投票、回复等提交响应不进入这里。
Future<void> createDocumentCacheTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedDocumentsTable (
        cache_key TEXT PRIMARY KEY,
        namespace TEXT NOT NULL,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        source_url TEXT NOT NULL,
        request_profile TEXT NOT NULL DEFAULT 'logged_in',
        body TEXT NOT NULL,
        content_type TEXT,
        status_code INTEGER,
        body_bytes INTEGER NOT NULL DEFAULT 0,
        fetched_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_documents_owner ON '
    '$cachedDocumentsTable(owner_type, owner_id, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_documents_namespace ON '
    '$cachedDocumentsTable(namespace, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_documents_access ON '
    '$cachedDocumentsTable(last_accessed_at, updated_at)',
  );
}

/// 原生模式 Phase 4：解析快照缓存。
///
/// `parser_version` 与 `codec_version` 用于让 parser/model 结构变更后
/// 自动忽略旧快照，避免 UI 读取过期结构。
Future<void> createSnapshotCacheTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedSnapshotsTable (
        cache_key TEXT PRIMARY KEY,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        snapshot_type TEXT NOT NULL,
        retain_long_term INTEGER NOT NULL DEFAULT 0,
        codec_version INTEGER NOT NULL,
        parser_version INTEGER NOT NULL,
        source_document_key TEXT,
        payload_json TEXT NOT NULL,
        payload_bytes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER,
        stale_at INTEGER,
        expires_at INTEGER,
        FOREIGN KEY (source_document_key) REFERENCES $cachedDocumentsTable(cache_key) ON DELETE SET NULL
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_owner ON '
    '$cachedSnapshotsTable(owner_type, owner_id, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_type_version ON '
    '$cachedSnapshotsTable(snapshot_type, codec_version, parser_version)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_access ON '
    '$cachedSnapshotsTable(last_accessed_at, updated_at)',
  );
}

Future<void> upgradeCacheFrom40To41(Database db) async {
  for (final column in ['etag', 'content_hash']) {
    await addColumnIfMissing(
      db,
      table: cachedImagesTable,
      column: column,
      definition: 'TEXT',
    );
  }
  await addColumnIfMissing(
    db,
    table: cachedSnapshotsTable,
    column: 'retain_long_term',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
}
