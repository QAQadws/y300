import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/storage/data/storage_root_migration_file_operations.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

void main() {
  const operations = LocalStorageRootMigrationFileOperations();
  late io.Directory workspace;

  setUp(() async {
    workspace = await io.Directory.systemTemp.createTemp(
      'y300-storage-file-operations-',
    );
  });

  tearDown(() => workspace.delete(recursive: true));

  test('readBytes reads an existing local file', () async {
    final file = io.File(p.join(workspace.path, 'fixture.bin'));
    const bytes = <int>[0, 127, 128, 255];
    await file.writeAsBytes(bytes, flush: true);

    expect(await operations.readBytes(file.path), orderedEquals(bytes));
  });

  test('readBytes maps a missing file to the domain failure', () async {
    await expectLater(
      operations.readBytes(p.join(workspace.path, 'missing.bin')),
      throwsA(
        isA<StorageRootMigrationFileOperationException>().having(
          (error) => error.code,
          'code',
          StorageRootMigrationFailureCode.copyFailed,
        ),
      ),
    );
  });
}
