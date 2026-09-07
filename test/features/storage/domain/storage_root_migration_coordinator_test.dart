import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/data/storage_root_migration_checkpoint_store.dart';
import 'package:y300/features/storage/data/storage_root_migration_file_operations.dart';
import 'package:y300/features/storage/data/transactional_storage_root_migration_coordinator.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

import '../test_support/storage_root_fixture.dart';

void main() {
  late StorageRootFixture fixture;

  setUp(() async {
    fixture = await StorageRootFixture.create();
  });

  tearDown(() => fixture.dispose());

  test('mixed root migrates, verifies, switches, and cleans source', () async {
    await fixture.populateMixedSource();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore();
    final coordinator = _coordinator(location, checkpoints: checkpoints);

    final result = await coordinator.migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(result.status.phase, StorageRootMigrationPhase.completed);
    expect(location.customRoot, isNull);
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
    expect(
      await fixture.targetContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isTrue,
    );
    expect(
      await fixture.targetContains(
        p.join(fixture.relativeComicDirectory, StorageRootFixture.cbzFileName),
      ),
      isTrue,
    );
    expect(
      await fixture.targetContains(
        p.join('novels', 'fixture-novel', 'chapter-001.txt'),
      ),
      isTrue,
    );
    expect(await fixture.targetContains('favorites.json'), isTrue);
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isFalse,
    );
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'interrupted.cbz.part'),
      ),
      isTrue,
    );

    final targetStorage = DefaultDownloadStorageService(
      locationRepository: _FakeStorageLocationRepository(
        defaultRoot: fixture.targetRoot.path,
      ),
    );
    final downloaded = await targetStorage.findDownloadedComicEpisode(
      workId: StorageRootFixture.workId,
      title: StorageRootFixture.workTitle,
      episodeId: StorageRootFixture.episodeId,
    );
    expect(downloaded, isNotNull);
    expect(await io.File(downloaded!.cbzPath).exists(), isTrue);
  });

  test('no custom root is a completed no-op', () async {
    final checkpoints = _MemoryCheckpointStore();
    final coordinator = _coordinator(
      _FakeStorageLocationRepository(defaultRoot: fixture.targetRoot.path),
      checkpoints: checkpoints,
    );

    final result = await coordinator.migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.notRequired);
    expect(result.status.phase, StorageRootMigrationPhase.completed);
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
  });

  test('empty custom root switches without inventing source content', () async {
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(location.customRoot, isNull);
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
    expect(await fixture.sourceRoot.list().toList(), isEmpty);
    expect(
      await io.File(p.join(fixture.targetRoot.path, 'favorites.json')).exists(),
      isTrue,
    );
  });

  test('same physical root clears only the redundant preference', () async {
    await fixture.populateMixedSource();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: p.join(fixture.sourceRoot.path, '.'),
    );
    final checkpoints = _MemoryCheckpointStore();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(location.customRoot, isNull);
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isTrue,
    );
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
  });

  test('identical destination files are reused without another copy', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.copyManagedSourceToTarget();
    final operations = _CountingFileOperations();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: operations,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(operations.copyCount, 0);
  });

  test('different target content blocks without overwriting source', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.writeTargetConflict();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.targetConflict,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isTrue,
    );
    expect(checkpoints.value?.phase, StorageRootMigrationPhase.blocked);
  });

  test('target parent file is classified as a target conflict', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await io.File(
      p.join(fixture.targetRoot.path, 'comics'),
    ).writeAsString('not a directory');
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.targetConflict,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
  });

  test(
    'unmanaged source top-level content stays in a shared custom root',
    () async {
      await fixture.populateMixedSource(includeTransientFiles: false);
      await fixture.writeUnknownTopLevelEntity();
      final userMovie = io.File(
        p.join(fixture.sourceRoot.path, 'user-movies', 'movie.mp4'),
      );
      await userMovie.parent.create(recursive: true);
      await userMovie.writeAsString('unmanaged user content');
      final location = _FakeStorageLocationRepository(
        customRoot: fixture.sourceRoot.path,
        defaultRoot: fixture.targetRoot.path,
      );
      final checkpoints = _MemoryCheckpointStore(
        StorageRootMigrationCheckpoint(
          phase: StorageRootMigrationPhase.blocked,
          sourceRoot: fixture.sourceRoot.path,
          targetRoot: fixture.targetRoot.path,
          failureCode: StorageRootMigrationFailureCode.unsupportedLayout,
        ),
      );

      final result = await _coordinator(
        location,
        checkpoints: checkpoints,
      ).migrateToDefault();

      expect(result.disposition, StorageRootMigrationDisposition.migrated);
      expect(result.status.phase, StorageRootMigrationPhase.completed);
      expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
      expect(location.customRoot, isNull);
      expect(
        await fixture.targetContains(
          p.join(fixture.relativeComicDirectory, 'meta.json'),
        ),
        isTrue,
      );
      expect(await fixture.sourceContains('unrelated-user-file.txt'), isTrue);
      expect(await userMovie.exists(), isTrue);
      expect(await fixture.targetContains('unrelated-user-file.txt'), isFalse);
      expect(
        await fixture.targetContains(p.join('user-movies', 'movie.mp4')),
        isFalse,
      );
    },
  );

  test(
    'known diagnostics exports migrate without weakening root safety',
    () async {
      await fixture.populateMixedSource(includeTransientFiles: false);
      await fixture.writeDiagnosticsExport();
      final location = _FakeStorageLocationRepository(
        customRoot: fixture.sourceRoot.path,
        defaultRoot: fixture.targetRoot.path,
      );

      final result = await _coordinator(
        location,
        checkpoints: _MemoryCheckpointStore(),
      ).migrateToDefault();

      expect(result.disposition, StorageRootMigrationDisposition.migrated);
      expect(
        await fixture.targetContains(
          p.join('diagnostics', 'cache-diagnostics-fixture.json'),
        ),
        isTrue,
      );
      expect(
        await fixture.sourceContains(
          p.join('diagnostics', 'cache-diagnostics-fixture.json'),
        ),
        isFalse,
      );
    },
  );

  test('link-like entity inside managed storage fails closed', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: _LinkReportingFileOperations('cover.jpg'),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.unsafeEntity,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
  });

  test(
    'nested source and target roots are rejected before inventory',
    () async {
      final nestedTarget = io.Directory(
        p.join(fixture.sourceRoot.path, 'nested-target'),
      );
      await nestedTarget.create(recursive: true);
      final location = _FakeStorageLocationRepository(
        customRoot: fixture.sourceRoot.path,
        defaultRoot: nestedTarget.path,
      );

      final result = await _coordinator(
        location,
        checkpoints: _MemoryCheckpointStore(),
      ).migrateToDefault();

      expect(result.disposition, StorageRootMigrationDisposition.blocked);
      expect(
        result.status.failureCode,
        StorageRootMigrationFailureCode.invalidTopology,
      );
    },
  );

  test('capacity preflight blocks before copying any file', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final operations = _CountingFileOperations();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await TransactionalStorageRootMigrationCoordinator(
      locationRepository: location,
      checkpointStore: _MemoryCheckpointStore(),
      fileOperations: operations,
      capacityProbe: const _FixedCapacityProbe(0),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.insufficientSpace,
    );
    expect(operations.copyCount, 0);
    expect(location.customRoot, fixture.sourceRoot.path);
  });

  test('copy failure preserves source and custom-root preference', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: _FailingCopyFileOperations(),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.copyFailed,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isTrue,
    );
  });

  test('permission error remains a stable blocked result', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: _PermissionDeniedCopyFileOperations(),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.permissionDenied,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
  });

  test('source mutation during copy is detected before switch', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );

    final result = await _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: _MutatingSourceFileOperations(),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.sourceChanged,
    );
    expect(location.customRoot, fixture.sourceRoot.path);
  });

  test('ready-to-switch checkpoint resumes without recopying', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.copyManagedSourceToTarget();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.readyToSwitch,
        sourceRoot: fixture.sourceRoot.path,
        targetRoot: fixture.targetRoot.path,
      ),
    );
    final operations = _CountingFileOperations();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
      fileOperations: operations,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(location.customRoot, isNull);
    expect(operations.copyCount, 0);
  });

  test('copying checkpoint resumes by reusing verified target files', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.copyManagedSourceToTarget();
    await io.File(
      p.join(
        fixture.targetRoot.path,
        'novels',
        'fixture-novel',
        'chapter-001.txt',
      ),
    ).delete();
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.copying,
        sourceRoot: fixture.sourceRoot.path,
        targetRoot: fixture.targetRoot.path,
      ),
    );
    final operations = _CountingFileOperations();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
      fileOperations: operations,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(operations.copyCount, 1);
  });

  test('ready-to-switch with cleared preference proceeds to cleanup', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.copyManagedSourceToTarget();
    final checkpoints = _MemoryCheckpointStore(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.readyToSwitch,
        sourceRoot: fixture.sourceRoot.path,
        targetRoot: fixture.targetRoot.path,
      ),
    );

    final result = await _coordinator(
      _FakeStorageLocationRepository(defaultRoot: fixture.targetRoot.path),
      checkpoints: checkpoints,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.migrated);
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isFalse,
    );
  });

  test('cleanup failure is nonblocking and resumes on the next run', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    await fixture.copyManagedSourceToTarget();
    final location = _FakeStorageLocationRepository(
      defaultRoot: fixture.targetRoot.path,
    );
    final checkpoints = _MemoryCheckpointStore(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.cleanupPending,
        sourceRoot: fixture.sourceRoot.path,
        targetRoot: fixture.targetRoot.path,
      ),
    );

    final failed = await _coordinator(
      location,
      checkpoints: checkpoints,
      fileOperations: _FailingCleanupFileOperations(),
    ).migrateToDefault();

    expect(failed.disposition, StorageRootMigrationDisposition.cleanupPending);
    expect(failed.status.blocksStorageAccess, isFalse);
    expect(checkpoints.value?.phase, StorageRootMigrationPhase.cleanupPending);

    final recovered = await _coordinator(
      location,
      checkpoints: checkpoints,
    ).migrateToDefault();
    expect(recovered.disposition, StorageRootMigrationDisposition.migrated);
    expect(checkpoints.value, StorageRootMigrationCheckpoint.completed);
  });

  test('custom-root switch failure never begins source cleanup', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
      failClear: true,
    );
    final checkpoints = _MemoryCheckpointStore();

    final result = await _coordinator(
      location,
      checkpoints: checkpoints,
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(result.status.phase, StorageRootMigrationPhase.readyToSwitch);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.switchFailed,
    );
    expect(
      await fixture.sourceContains(
        p.join(fixture.relativeComicDirectory, 'meta.json'),
      ),
      isTrue,
    );
  });

  test('concurrent callers share one migration operation', () async {
    await fixture.populateMixedSource(includeTransientFiles: false);
    final operations = _CountingFileOperations();
    final coordinator = _coordinator(
      _FakeStorageLocationRepository(
        customRoot: fixture.sourceRoot.path,
        defaultRoot: fixture.targetRoot.path,
      ),
      checkpoints: _MemoryCheckpointStore(),
      fileOperations: operations,
    );

    final first = coordinator.migrateToDefault();
    final second = coordinator.migrateToDefault();

    expect(identical(first, second), isTrue);
    await Future.wait(<Future<StorageRootMigrationResult>>[first, second]);
    expect(operations.copyCount, greaterThan(0));
  });

  test('corrupt checkpoint without custom root is nonblocking', () async {
    final result = await _coordinator(
      _FakeStorageLocationRepository(defaultRoot: fixture.targetRoot.path),
      checkpoints: _CorruptCheckpointStore(),
    ).migrateToDefault();

    expect(result.disposition, StorageRootMigrationDisposition.cleanupPending);
    expect(
      result.status.failureCode,
      StorageRootMigrationFailureCode.stateCorrupt,
    );
    expect(result.status.blocksStorageAccess, isFalse);
  });

  test('custom-root read failure never becomes a no-op', () async {
    final location = _FakeStorageLocationRepository(
      defaultRoot: fixture.targetRoot.path,
      failReadCustom: true,
    );
    final coordinator = _coordinator(
      location,
      checkpoints: _MemoryCheckpointStore(),
    );

    final inspected = await coordinator.inspect();
    final result = await coordinator.migrateToDefault();

    expect(inspected.phase, StorageRootMigrationPhase.blocked);
    expect(inspected.blocksStorageAccess, isTrue);
    expect(result.disposition, StorageRootMigrationDisposition.blocked);
    expect(result.status.blocksStorageAccess, isTrue);
  });

  test('provider construction keeps migration dormant', () async {
    final location = _FakeStorageLocationRepository(
      customRoot: fixture.sourceRoot.path,
      defaultRoot: fixture.targetRoot.path,
    );
    final container = ProviderContainer(
      overrides: [
        storageLocationRepositoryProvider.overrideWithValue(location),
        storageRootMigrationCheckpointStoreProvider.overrideWithValue(
          _MemoryCheckpointStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(storageRootMigrationCoordinatorProvider);
    await Future<void>.delayed(Duration.zero);

    expect(location.customRootReadCount, 0);
    expect(location.customRoot, fixture.sourceRoot.path);
    expect(await fixture.targetContains('favorites.json'), isFalse);
  });
}

TransactionalStorageRootMigrationCoordinator _coordinator(
  StorageLocationRepository location, {
  required StorageRootMigrationCheckpointStore checkpoints,
  StorageRootMigrationFileOperations fileOperations =
      const LocalStorageRootMigrationFileOperations(),
}) {
  return TransactionalStorageRootMigrationCoordinator(
    locationRepository: location,
    checkpointStore: checkpoints,
    fileOperations: fileOperations,
  );
}

final class _FakeStorageLocationRepository
    implements StorageLocationRepository {
  _FakeStorageLocationRepository({
    required this.defaultRoot,
    this.customRoot,
    this.failClear = false,
    this.failReadCustom = false,
  });

  final String defaultRoot;
  String? customRoot;
  final bool failClear;
  final bool failReadCustom;
  int customRootReadCount = 0;

  @override
  Future<String?> getCustomStorageRoot() async {
    customRootReadCount += 1;
    if (failReadCustom) {
      throw StateError('fixture preference read failure');
    }
    return customRoot;
  }

  @override
  Future<String> getDefaultStorageRoot() async => defaultRoot;

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<void> setCustomStorageRoot(String? path) async {
    if (path == null && failClear) {
      throw StateError('fixture switch failure');
    }
    customRoot = path;
  }
}

final class _MemoryCheckpointStore
    implements StorageRootMigrationCheckpointStore {
  _MemoryCheckpointStore([this.value]);

  StorageRootMigrationCheckpoint? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StorageRootMigrationCheckpoint?> read() async => value;

  @override
  Future<void> write(StorageRootMigrationCheckpoint checkpoint) async {
    value = checkpoint;
  }
}

final class _CorruptCheckpointStore
    implements StorageRootMigrationCheckpointStore {
  @override
  Future<void> clear() async {}

  @override
  Future<StorageRootMigrationCheckpoint?> read() {
    throw const StorageRootMigrationCheckpointFormatException();
  }

  @override
  Future<void> write(StorageRootMigrationCheckpoint checkpoint) async {}
}

final class _FixedCapacityProbe implements StorageRootCapacityProbe {
  const _FixedCapacityProbe(this.bytes);

  final int? bytes;

  @override
  Future<int?> availableBytes(String path) async => bytes;
}

class _DelegatingFileOperations implements StorageRootMigrationFileOperations {
  _DelegatingFileOperations({StorageRootMigrationFileOperations? delegate})
    : _delegate = delegate ?? const LocalStorageRootMigrationFileOperations();

  final StorageRootMigrationFileOperations _delegate;

  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) {
    return _delegate.copyFileAtomically(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      temporaryPath: temporaryPath,
      expectedSource: expectedSource,
    );
  }

  @override
  Future<void> deleteDirectoryIfEmpty(String path) {
    return _delegate.deleteDirectoryIfEmpty(path);
  }

  @override
  Future<void> deleteFile(String path) => _delegate.deleteFile(path);

  @override
  Future<void> ensureDirectory(String path) {
    return _delegate.ensureDirectory(path);
  }

  @override
  Future<StorageRootMigrationFileFingerprint> fingerprint(String path) {
    return _delegate.fingerprint(path);
  }

  @override
  Future<List<StorageRootMigrationEntity>> list(String directoryPath) {
    return _delegate.list(directoryPath);
  }

  @override
  Future<Uint8List> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<StorageRootMigrationEntityType> type(String path) {
    return _delegate.type(path);
  }

  @override
  Future<void> writeBytesAtomically({
    required String destinationPath,
    required String temporaryPath,
    required Uint8List bytes,
  }) {
    return _delegate.writeBytesAtomically(
      destinationPath: destinationPath,
      temporaryPath: temporaryPath,
      bytes: bytes,
    );
  }
}

class _CountingFileOperations extends _DelegatingFileOperations {
  int copyCount = 0;

  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) async {
    copyCount += 1;
    await super.copyFileAtomically(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      temporaryPath: temporaryPath,
      expectedSource: expectedSource,
    );
  }
}

final class _FailingCopyFileOperations extends _DelegatingFileOperations {
  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) {
    throw const StorageRootMigrationFileOperationException(
      StorageRootMigrationFailureCode.copyFailed,
    );
  }
}

final class _PermissionDeniedCopyFileOperations
    extends _DelegatingFileOperations {
  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) {
    throw const StorageRootMigrationFileOperationException(
      StorageRootMigrationFailureCode.permissionDenied,
    );
  }
}

final class _MutatingSourceFileOperations extends _DelegatingFileOperations {
  bool _mutated = false;

  @override
  Future<void> copyFileAtomically({
    required String sourcePath,
    required String destinationPath,
    required String temporaryPath,
    required StorageRootMigrationFileFingerprint expectedSource,
  }) async {
    await super.copyFileAtomically(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      temporaryPath: temporaryPath,
      expectedSource: expectedSource,
    );
    if (!_mutated) {
      _mutated = true;
      await io.File(
        sourcePath,
      ).writeAsBytes(<int>[0], mode: io.FileMode.append);
    }
  }
}

final class _FailingCleanupFileOperations extends _DelegatingFileOperations {
  @override
  Future<void> deleteFile(String path) {
    throw const StorageRootMigrationFileOperationException(
      StorageRootMigrationFailureCode.cleanupFailed,
    );
  }
}

final class _LinkReportingFileOperations extends _DelegatingFileOperations {
  _LinkReportingFileOperations(this.fileName);

  final String fileName;

  @override
  Future<List<StorageRootMigrationEntity>> list(String directoryPath) async {
    final entities = await super.list(directoryPath);
    return entities
        .map(
          (entity) => p.basename(entity.path) == fileName
              ? StorageRootMigrationEntity(
                  path: entity.path,
                  type: StorageRootMigrationEntityType.link,
                )
              : entity,
        )
        .toList(growable: false);
  }
}
