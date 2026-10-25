import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Public release tags grouped by the database version actually shipped.
/// Tags sharing a version were checked to create identical schemas and seeds.
const releasedDatabaseTags = <int, List<String>>{
  27: ['v1.0.0'],
  36: ['v1.0.2'],
  38: ['v1.1.0', 'v1.1.1', 'v1.1.2'],
  40: ['v1.1.3', 'v1.1.4', 'v1.1.5', 'v1.2.0', 'v1.2.1'],
  41: ['v1.3.0'],
  42: ['v1.3.1'],
  43: ['v1.3.2'],
};

/// Creates the release's frozen onCreate result, not a downgraded current schema.
/// Invoke from the old database's onCreate; the caller owns user_version/FKs.
Future<void> createReleasedDatabaseFixture(Database db, int version) async {
  if (!releasedDatabaseTags.containsKey(version)) {
    throw ArgumentError.value(
      version,
      'version',
      'No published schema fixture',
    );
  }
  final envelope = jsonDecode(
    await File('test/core/persistence/fixtures/schema_v$version.json')
        .readAsString(encoding: utf8),
  ) as Map<String, dynamic>;
  if (envelope['schemaVersion'] != version) {
    throw const FormatException('Released fixture version does not match');
  }
  for (final statement in (envelope['statements'] as List).cast<String>()) {
    await db.execute(statement);
  }
}
