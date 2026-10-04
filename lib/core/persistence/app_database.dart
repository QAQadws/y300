import 'package:sqflite/sqflite.dart';

import 'app_database_migrations.dart';
import 'app_database_schema.dart';
import 'app_database_tables.dart' as tables;

/// Shared application database lifecycle for library data and caches.
class AppDatabase {
  AppDatabase._();

  static const String dbName = 'comic_shelf.db';
  static const int dbVersion = 42;

  static const String comicsTable = tables.comicsTable;
  static const String episodesTable = tables.episodesTable;
  static const String episodeImagesTable = tables.episodeImagesTable;
  static const String categoriesTable = tables.categoriesTable;
  static const String shelfItemsTable = tables.shelfItemsTable;
  static const String settingsTable = tables.settingsTable;
  static const String readingProgressTable = tables.readingProgressTable;
  static const String worksTable = tables.worksTable;
  static const String workEpisodesTable = tables.workEpisodesTable;
  static const String novelEpisodeContentTable =
      tables.novelEpisodeContentTable;
  static const String readerPreferencesTable = tables.readerPreferencesTable;
  static const String novelReadingProgressTable =
      tables.novelReadingProgressTable;
  static const String readerBookmarksTable = tables.readerBookmarksTable;
  static const String novelCategoriesTable = tables.novelCategoriesTable;
  static const String novelShelfItemsTable = tables.novelShelfItemsTable;
  static const String libraryWorkStateTable = tables.libraryWorkStateTable;
  static const String libraryEpisodeStateTable =
      tables.libraryEpisodeStateTable;
  static const String libraryTagsTable = tables.libraryTagsTable;
  static const String libraryWorkTagsTable = tables.libraryWorkTagsTable;
  static const String libraryDisplaySettingsTable =
      tables.libraryDisplaySettingsTable;
  static const String favoriteSyncStateTable = tables.favoriteSyncStateTable;
  static const String favoriteThreadsTable = tables.favoriteThreadsTable;
  static const String favoriteCategoriesTable = tables.favoriteCategoriesTable;
  static const String favoriteThreadCategoryTable =
      tables.favoriteThreadCategoryTable;
  static const String cachedImagesTable = tables.cachedImagesTable;
  static const String cachedDocumentsTable = tables.cachedDocumentsTable;
  static const String cachedSnapshotsTable = tables.cachedSnapshotsTable;
  static const String libraryCoverMigrationsTable =
      tables.libraryCoverMigrationsTable;
  static const String comicCoverMergeOperationsTable =
      tables.comicCoverMergeOperationsTable;
  static const String comicCoverMergeMembersTable =
      tables.comicCoverMergeMembersTable;
  static const String comicCoverMergeAssetsTable =
      tables.comicCoverMergeAssetsTable;
  static const String comicSearchRefreshQueueTable =
      tables.comicSearchRefreshQueueTable;
  static const String comicDownloadQueueTable = tables.comicDownloadQueueTable;
  static const String novelSourceStateTable = tables.novelSourceStateTable;
  static const String novelEpisodeSyncStagingTable =
      tables.novelEpisodeSyncStagingTable;

  static Future<Database> open({String? databaseName}) {
    // Keep database initialization behind the Future boundary. This makes
    // provider construction safe when a platform database factory is not yet
    // installed; callers can handle the failed open during their async load.
    return Future<Database>.sync(() {
      final targetDbName = databaseName ?? dbName;
      return openDatabase(
        targetDbName,
        version: dbVersion,
        onConfigure: (db) async {
          // 多个阶段的清理逻辑都依赖 schema 上声明的级联关系，这里显式打开
          // SQLite 外键约束，避免“表上写了 ON DELETE CASCADE，但运行时不生效”。
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await createAppDatabaseSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await upgradeAppDatabaseSchema(db, oldVersion, newVersion);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          await rebuildAppDatabaseSchema(db);
        },
      );
    });
  }
}
