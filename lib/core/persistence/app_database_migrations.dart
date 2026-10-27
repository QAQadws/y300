import 'package:sqflite/sqflite.dart';

import 'app_database_schema.dart';
import 'schema/comic_database_schema.dart';
import 'schema/novel_database_schema.dart';
import 'schema/favorites_database_schema.dart';
import 'schema/library_database_schema.dart';
import 'schema/cache_database_schema.dart';

/// One global upgrade chain, grouped by database versions shipped in release tags.
Future<void> upgradeAppDatabaseSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 27) {
    await rebuildAppDatabaseSchema(db);
    return;
  }

  // Released schemas: v1.0.0=27, v1.0.2=36, v1.1.0–v1.1.2=38,
  // v1.1.3–v1.2.1=40, v1.3.0=41, v1.3.1=42, v1.3.2=43.
  // Keep independent conditions: a user can skip any number of releases.
  if (oldVersion < 36 && newVersion >= 36) {
    await upgradeComicFrom27To36(db);
    await upgradeNovelFrom27To36(db);
    await upgradeFavoritesFrom27To36(db);
  }
  if (oldVersion < 38 && newVersion >= 38) {
    await upgradeComicFrom36To38(db);
  }
  if (oldVersion < 40 && newVersion >= 40) {
    await upgradeLibraryFrom38To40(db);
    await upgradeComicFrom38To40(db);
  }
  if (oldVersion < 41 && newVersion >= 41) {
    await upgradeCacheFrom40To41(db);
  }
  if (oldVersion < 42 && newVersion >= 42) {
    await upgradeNovelFrom41To42(db);
  }
  if (oldVersion < 43 && newVersion >= 43) {
    await upgradeLibraryFrom42To43(db);
    await upgradeNovelFrom42To43(db);
  }
  if (oldVersion < 44 && newVersion >= 44) {
    await createFavoriteParseJobsTable(db);
  }
}
