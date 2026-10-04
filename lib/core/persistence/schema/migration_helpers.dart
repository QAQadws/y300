import 'package:sqflite/sqflite.dart';

/// 表的列名集合；表不存在时返回空集合。
///
/// SQLite 里 `PRAGMA table_info` 对缺表和零列表返回同样的空结果，而零列表
/// 不存在，所以空集合可以直接当作「没有这张表」用。
Future<Set<String>> columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((entry) => entry['name'] as String).toSet();
}

Future<void> addColumnIfMissing(
  Database db, {
  required String table,
  required String column,
  required String definition,
}) async {
  final columns = await columnNames(db, table);
  // 漫画与小说共用这一个库，升级链会跑在只建了对方表的历史库上；缺表时跳过
  // 而不是让 ALTER TABLE 抛错中断整条升级。
  if (columns.isEmpty || columns.contains(column)) {
    return;
  }
  await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}

Future<void> backfillCoverRevision(
  Database db, {
  required String table,
  required String revisionColumn,
  required List<String> sourceColumns,
}) async {
  final columns = await columnNames(db, table);
  if (!columns.contains(revisionColumn)) {
    return;
  }
  final availableSources = sourceColumns
      .where(columns.contains)
      .toList(growable: false);
  if (availableSources.isEmpty) {
    return;
  }
  final sourcePredicate = availableSources
      .map((column) => '$column IS NOT NULL')
      .join(' OR ');
  await db.execute('''
      UPDATE $table
      SET $revisionColumn = 1
      WHERE $revisionColumn = 0 AND ($sourcePredicate)
    ''');
}
