import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

/// Business owners supply the tables; row counts carry no physical DB bytes.
class SqliteMetadataStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const SqliteMetadataStorageAccountingAdapter({
    required Future<Database> Function() databaseProvider,
    required Map<String, String> tables,
  }) : _databaseProvider = databaseProvider,
       _tables = tables;

  final Future<Database> Function() _databaseProvider;
  final Map<String, String> _tables;

  @override
  StorageBucket get bucket => StorageBucket.libraryMetadata;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _databaseProvider();
    final slices = <StorageUsageSlice>[];
    for (final entry in _tables.entries) {
      var count = 0;
      try {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM ${entry.value}',
        );
        count = rows.first['count'] as int? ?? 0;
      } catch (_) {
        // A missing table contributes no rows, as in the previous overview.
      }
      if (count > 0) {
        slices.add(
          StorageUsageSlice(
            id: 'library_metadata:${entry.key}',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.libraryKind,
              code: entry.key,
              count: count,
            ),
            bytes: 0,
            protected: true,
          ),
        );
      }
    }
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: 0,
      clearable: false,
      slices: slices,
    );
  }
}
