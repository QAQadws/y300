import 'package:sqflite/sqflite.dart';

import 'app_database_tables.dart';
import 'schema/comic_database_schema.dart';
import 'schema/novel_database_schema.dart';
import 'schema/favorites_database_schema.dart';
import 'schema/library_database_schema.dart';
import 'schema/cache_database_schema.dart';

/// Creation order follows the shared database's existing foreign-key/index dependencies.
Future<void> createAppDatabaseSchema(Database db) async {
  await createComicTables(db);
  await createComicSettingsTable(db);
  await seedDefaultComicSettings(db);
  await createComicReadingProgressTable(db);
  await createNovelTables(db);
  await createNovelHydrationTables(db);
  await createNovelReadingProgressTable(db);
  await createNovelReaderBookmarksTable(db);
  await createNovelShelfTables(db);
  await createLibraryStateTables(db);
  await createLibraryPerformanceIndexes(db);
  await createFavoriteTables(db);
  await createImageCacheTables(db);
  await createLibraryCoverMigrationTable(db);
  await createComicCoverMergeJournalTables(db);
  await createLibraryCoverRevisionTriggers(db);
  await createDocumentCacheTables(db);
  await createSnapshotCacheTables(db);
  await createComicSearchRefreshQueueTable(db);
  await createComicDownloadQueueTable(db);
}

/// Retains the existing reset policy for upgrades before v27 and downgrades.
/// Dependency-ordered drops remain in one place for the shared physical database.
Future<void> rebuildAppDatabaseSchema(Database db) async {
  for (final tableName in _managedTablesInDropOrder) {
    await db.execute('DROP TABLE IF EXISTS $tableName');
  }
  await createAppDatabaseSchema(db);
}

const List<String> _managedTablesInDropOrder = <String>[
  comicCoverMergeAssetsTable,
  comicCoverMergeMembersTable,
  comicCoverMergeOperationsTable,
  libraryCoverMigrationsTable,
  novelEpisodeSyncStagingTable,
  novelSourceStateTable,
  comicDownloadQueueTable,
  comicSearchRefreshQueueTable,
  cachedSnapshotsTable,
  cachedDocumentsTable,
  favoriteThreadCategoryTable,
  favoriteCategoriesTable,
  favoriteThreadsTable,
  favoriteSyncStateTable,
  libraryWorkTagsTable,
  libraryTagsTable,
  libraryEpisodeStateTable,
  libraryWorkStateTable,
  libraryDisplaySettingsTable,
  readerBookmarksTable,
  novelEpisodeContentTable,
  workEpisodesTable,
  novelShelfItemsTable,
  novelCategoriesTable,
  novelReadingProgressTable,
  readerPreferencesTable,
  worksTable,
  cachedImagesTable,
  readingProgressTable,
  shelfItemsTable,
  categoriesTable,
  episodeImagesTable,
  episodesTable,
  comicsTable,
  settingsTable,
];
