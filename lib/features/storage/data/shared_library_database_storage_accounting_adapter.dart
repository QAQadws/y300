import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

/// The app registers one physical contribution for the shared library DB.
class SharedLibraryDatabaseStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const SharedLibraryDatabaseStorageAccountingAdapter({
    Future<Database> Function() databaseProvider = AppDatabase.open,
    Future<String>? databasePathFuture,
  }) : _databaseProvider = databaseProvider,
       _databasePathFuture = databasePathFuture;

  final Future<Database> Function() _databaseProvider;
  final Future<String>? _databasePathFuture;

  @override
  StorageBucket get bucket => StorageBucket.libraryMetadata;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    await _databaseProvider();
    final path =
        await (_databasePathFuture ??
            (() async =>
                p.join(await getDatabasesPath(), AppDatabase.dbName))());
    final file = File(path);
    // Retain the overview's main-file-only policy for this shared database.
    final bytes = await file.exists() ? await file.length() : 0;
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: false,
      slices: [
        if (bytes > 0)
          StorageUsageSlice(
            id: 'library_metadata:sqlite',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.database,
              code: 'library_metadata',
            ),
            bytes: bytes,
            protected: true,
          ),
      ],
    );
  }
}
