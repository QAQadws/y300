import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';

class ComposerDraftStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const ComposerDraftStorageAccountingAdapter({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;

  final Future<Database> Function() _databaseProvider;

  @override
  StorageBucket get bucket => StorageBucket.composerDraft;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS draft_count,
        COALESCE(SUM(LENGTH(CAST(snapshot_json AS BLOB))), 0) AS payload_bytes
      FROM ${ComposerDraftLocalDb.draftsTable}
    ''');
    final count = (rows.single['draft_count'] as num?)?.toInt() ?? 0;
    final bytes = (rows.single['payload_bytes'] as num?)?.toInt() ?? 0;
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: count > 0,
      slices: [
        if (bytes > 0)
          StorageUsageSlice(
            id: 'composer_draft:sqlite',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.composerDraft,
              code: 'composer_draft',
              count: count,
            ),
            bytes: bytes,
            protected: false,
          ),
      ],
    );
  }
}
