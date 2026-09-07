import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/storage/domain/storage_root_migration.dart';

enum StorageRootMigrationEntityType { file, directory, link, other, notFound }

final class StorageRootMigrationEntity {
  const StorageRootMigrationEntity({required this.path, required this.type});

  final String path;
  final StorageRootMigrationEntityType type;
}

final class StorageRootMigrationFileFingerprint {
  const StorageRootMigrationFileFingerprint({
    required this.length,
    required this.sha256,
    required this.modifiedAt,
  });

  final int length;
  final String sha256;
  final DateTime modifiedAt;

  bool hasSameContent(StorageRootMigrationFileFingerprint other) {
    return length == other.length && sha256 == other.sha256;
  }
}

abstract interface class StorageRootMigrationFileOperations {
  Future<StorageRootMigrationEntityType> type(String path);

  Future<List<StorageRootMigrationEntity>> list(String directoryPath);

  Future<void> ensureDirectory(String path);

  Future<StorageRootMigrationFileFingerprint> fingerprint(String path);

  Future<Uint8List> readBytes(String path);

  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  });

  Future<void> writeBytesAtomically({
    required String destinationPath,
    required String temporaryPath,
    required Uint8List bytes,
  });

  Future<void> deleteFile(String path);

  Future<void> deleteDirectoryIfEmpty(String path);
}

final class LocalStorageRootMigrationFileOperations
    implements StorageRootMigrationFileOperations {
  const LocalStorageRootMigrationFileOperations();

  @override
  Future<StorageRootMigrationEntityType> type(String path) async {
    try {
      return _mapType(await io.FileSystemEntity.type(path, followLinks: false));
    } on io.FileSystemException catch (error) {
      throw _mappedException(error);
    }
  }

  @override
  Future<List<StorageRootMigrationEntity>> list(String directoryPath) async {
    try {
      final entities = <StorageRootMigrationEntity>[];
      await for (final entity in io.Directory(
        directoryPath,
      ).list(followLinks: false)) {
        entities.add(
          StorageRootMigrationEntity(
            path: entity.path,
            type: _mapType(
              await io.FileSystemEntity.type(entity.path, followLinks: false),
            ),
          ),
        );
      }
      entities.sort((left, right) => left.path.compareTo(right.path));
      return entities;
    } on io.FileSystemException catch (error) {
      throw _mappedException(error);
    }
  }

  @override
  Future<void> ensureDirectory(String path) async {
    try {
      await io.Directory(path).create(recursive: true);
    } on io.FileSystemException catch (error) {
      throw _mappedException(error);
    }
  }

  @override
  Future<StorageRootMigrationFileFingerprint> fingerprint(String path) async {
    try {
      final file = io.File(path);
      final stat = await file.stat();
      if (stat.type != io.FileSystemEntityType.file) {
        throw const StorageRootMigrationFileOperationException(
          StorageRootMigrationFailureCode.unsafeEntity,
        );
      }
      final digest = (await sha256.bind(file.openRead()).first).toString();
      return StorageRootMigrationFileFingerprint(
        length: stat.size,
        sha256: digest,
        modifiedAt: stat.modified,
      );
    } on StorageRootMigrationFileOperationException {
      rethrow;
    } on io.FileSystemException catch (error) {
      throw _mappedException(error);
    }
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    try {
      return io.File(path).readAsBytes();
    } on io.FileSystemException catch (error) {
      throw _mappedException(error);
    }
  }

  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) async {
    final temporary = io.File(temporaryPath);
    try {
      await io.Directory(p.dirname(destinationPath)).create(recursive: true);
      if (await temporary.exists()) {
        await temporary.delete();
      }

      final sink = temporary.openWrite(mode: io.FileMode.writeOnly);
      try {
        await sink.addStream(io.File(sourcePath).openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }

      final temporaryFingerprint = await fingerprint(temporaryPath);
      if (!temporaryFingerprint.hasSameContent(expectedSource)) {
        await _deleteIfPresent(temporary);
        throw const StorageRootMigrationFileOperationException(
          StorageRootMigrationFailureCode.sourceChanged,
        );
      }

      final destination = io.File(destinationPath);
      if (await destination.exists()) {
        final destinationFingerprint = await fingerprint(destinationPath);
        await _deleteIfPresent(temporary);
        if (destinationFingerprint.hasSameContent(expectedSource)) {
          return;
        }
        throw const StorageRootMigrationFileOperationException(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }

      await temporary.rename(destinationPath);
      try {
        await destination.setLastModified(expectedSource.modifiedAt);
      } on io.FileSystemException {
        // Timestamp preservation is best effort; content identity is verified
        // independently and remains the migration commit criterion.
      }
    } on StorageRootMigrationFileOperationException {
      rethrow;
    } on io.FileSystemException catch (error) {
      await _deleteIfPresent(temporary);
      throw _mappedException(error);
    }
  }

  @override
  Future<void> writeBytesAtomically({
    required String destinationPath,
    required String temporaryPath,
    required Uint8List bytes,
  }) async {
    final destination = io.File(destinationPath);
    final temporary = io.File(temporaryPath);
    try {
      if (await destination.exists()) {
        throw const StorageRootMigrationFileOperationException(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
      await destination.parent.create(recursive: true);
      await _deleteIfPresent(temporary);
      final handle = await temporary.open(mode: io.FileMode.write);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temporary.rename(destinationPath);
    } on StorageRootMigrationFileOperationException {
      rethrow;
    } on io.FileSystemException catch (error) {
      await _deleteIfPresent(temporary);
      throw _mappedException(error);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on io.FileSystemException catch (error) {
      throw _mappedException(
        error,
        fallback: StorageRootMigrationFailureCode.cleanupFailed,
      );
    }
  }

  @override
  Future<void> deleteDirectoryIfEmpty(String path) async {
    try {
      final directory = io.Directory(path);
      if (!await directory.exists()) {
        return;
      }
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    } on io.FileSystemException catch (error) {
      throw _mappedException(
        error,
        fallback: StorageRootMigrationFailureCode.cleanupFailed,
      );
    }
  }

  StorageRootMigrationEntityType _mapType(io.FileSystemEntityType type) {
    if (type == io.FileSystemEntityType.file) {
      return StorageRootMigrationEntityType.file;
    }
    if (type == io.FileSystemEntityType.directory) {
      return StorageRootMigrationEntityType.directory;
    }
    if (type == io.FileSystemEntityType.link) {
      return StorageRootMigrationEntityType.link;
    }
    if (type == io.FileSystemEntityType.notFound) {
      return StorageRootMigrationEntityType.notFound;
    }
    return StorageRootMigrationEntityType.other;
  }

  StorageRootMigrationFileOperationException _mappedException(
    io.FileSystemException error, {
    StorageRootMigrationFailureCode fallback =
        StorageRootMigrationFailureCode.copyFailed,
  }) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return const StorageRootMigrationFileOperationException(
        StorageRootMigrationFailureCode.insufficientSpace,
      );
    }
    if (code == 5 || code == 13) {
      return const StorageRootMigrationFileOperationException(
        StorageRootMigrationFailureCode.permissionDenied,
      );
    }
    return StorageRootMigrationFileOperationException(fallback);
  }

  Future<void> _deleteIfPresent(io.File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on io.FileSystemException {
      // The original operation failure is more useful than cleanup failure.
    }
  }
}

final class StorageRootMigrationFileOperationException implements Exception {
  const StorageRootMigrationFileOperationException(this.code);

  final StorageRootMigrationFailureCode code;
}
