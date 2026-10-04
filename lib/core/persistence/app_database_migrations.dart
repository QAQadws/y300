import 'package:sqflite/sqflite.dart';

import 'app_database_schema.dart';
import 'schema/comic_database_schema.dart';
import 'schema/novel_database_schema.dart';
import 'schema/favorites_database_schema.dart';
import 'schema/library_database_schema.dart';
import 'schema/cache_database_schema.dart';

/// One global version chain; each step delegates SQL to its owning schema module.
Future<void> upgradeAppDatabaseSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 27) {
    await rebuildAppDatabaseSchema(db);
    return;
  }

  // Sqflite invokes onUpgrade once with the installed and target versions.
  // Apply every intervening migration so skipping an app release stays safe.
  if (oldVersion < 28 && newVersion >= 28) {
    await upgradeComicFrom27To28(db);
  }
  if (oldVersion < 29 && newVersion >= 29) {
    await upgradeNovelFrom28To29(db);
  }
  if (oldVersion < 30 && newVersion >= 30) {
    await upgradeNovelFrom29To30(db);
  }
  if (oldVersion < 31 && newVersion >= 31) {
    await upgradeNovelFrom30To31(db);
  }
  if (oldVersion < 32 && newVersion >= 32) {
    await upgradeComicFrom31To32(db);
  }
  if (oldVersion < 33 && newVersion >= 33) {
    await upgradeFavoritesFrom32To33(db);
  }
  if (oldVersion < 34 && newVersion >= 34) {
    await upgradeNovelFrom33To34(db);
  }
  if (oldVersion < 35 && newVersion >= 35) {
    await upgradeNovelFrom34To35(db);
  }
  if (oldVersion < 36 && newVersion >= 36) {
    await upgradeComicFrom35To36(db);
  }
  if (oldVersion < 37 && newVersion >= 37) {
    await upgradeComicFrom36To37(db);
  }
  if (oldVersion < 38 && newVersion >= 38) {
    await upgradeComicFrom37To38(db);
  }
  if (oldVersion < 39 && newVersion >= 39) {
    await upgradeLibraryFrom38To39(db);
  }
  if (oldVersion < 40 && newVersion >= 40) {
    await upgradeComicFrom39To40(db);
  }
  if (oldVersion < 41 && newVersion >= 41) {
    await upgradeCacheFrom40To41(db);
  }
  if (oldVersion < 42 && newVersion >= 42) {
    await upgradeNovelFrom41To42(db);
  }
}
