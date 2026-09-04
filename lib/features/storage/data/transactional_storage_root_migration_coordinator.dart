import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/data/storage_root_migration_checkpoint_store.dart';
import 'package:y300/features/storage/data/storage_root_migration_file_operations.dart';
import 'package:y300/features/storage/domain/download_storage_layout.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final class TransactionalStorageRootMigrationCoordinator
    implements StorageRootMigrationCoordinator {
  TransactionalStorageRootMigrationCoordinator({
    required StorageLocationRepository locationRepository,
    required StorageRootMigrationCheckpointStore checkpointStore,
    StorageRootMigrationFileOperations fileOperations =
        const LocalStorageRootMigrationFileOperations(),
    StorageRootCapacityProbe capacityProbe =
        const UnavailableStorageRootCapacityProbe(),
  }) : _locationRepository = locationRepository,
       _checkpointStore = checkpointStore,
       _fileOperations = fileOperations,
       _capacityProbe = capacityProbe;

  final StorageLocationRepository _locationRepository;
  final StorageRootMigrationCheckpointStore _checkpointStore;
  final StorageRootMigrationFileOperations _fileOperations;
  final StorageRootCapacityProbe _capacityProbe;

  Future<StorageRootMigrationResult>? _activeMigration;

  @override
  Future<StorageRootMigrationStatus> inspect() async {
    StorageRootMigrationCheckpoint? checkpoint;
    try {
      checkpoint = await _checkpointStore.read();
      if (checkpoint != null) {
        if (checkpoint.phase == StorageRootMigrationPhase.cleanupPending ||
            checkpoint.phase == StorageRootMigrationPhase.completed) {
          return _statusForCheckpoint(checkpoint, customRoot: null);
        }
      }
    } on StorageRootMigrationCheckpointFormatException {
      String? customRoot;
      try {
        customRoot = await _readCustomRoot();
      } catch (_) {
        return const StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.blocked,
          failureCode: StorageRootMigrationFailureCode.unknown,
          blocksStorageAccess: true,
        );
      }
      return StorageRootMigrationStatus(
        phase: customRoot == null
            ? StorageRootMigrationPhase.cleanupPending
            : StorageRootMigrationPhase.blocked,
        failureCode: StorageRootMigrationFailureCode.stateCorrupt,
        blocksStorageAccess: customRoot != null,
      );
    } catch (_) {
      return const StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.blocked,
        failureCode: StorageRootMigrationFailureCode.unknown,
        blocksStorageAccess: true,
      );
    }

    String? customRoot;
    try {
      customRoot = await _readCustomRoot();
    } catch (_) {
      return const StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.blocked,
        failureCode: StorageRootMigrationFailureCode.unknown,
        blocksStorageAccess: true,
      );
    }
    if (customRoot == null && checkpoint != null) {
      return _statusForCheckpoint(checkpoint, customRoot: null);
    }
    if (checkpoint != null) {
      return _statusForCheckpoint(checkpoint, customRoot: customRoot);
    }

    if (customRoot == null) {
      return const StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.completed,
        blocksStorageAccess: false,
      );
    }

    try {
      final targetRoot = _normalizeRoot(
        await _locationRepository.getDefaultStorageRoot(),
      );
      return StorageRootMigrationStatus(
        phase: _samePath(customRoot, targetRoot)
            ? StorageRootMigrationPhase.readyToSwitch
            : StorageRootMigrationPhase.copying,
        blocksStorageAccess: !_samePath(customRoot, targetRoot),
      );
    } catch (_) {
      return const StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.blocked,
        failureCode: StorageRootMigrationFailureCode.targetUnavailable,
        blocksStorageAccess: true,
      );
    }
  }

  @override
  Future<StorageRootMigrationResult> migrateToDefault() {
    final active = _activeMigration;
    if (active != null) {
      return active;
    }
    late final Future<StorageRootMigrationResult> operation;
    operation = _migrate().whenComplete(() {
      if (identical(_activeMigration, operation)) {
        _activeMigration = null;
      }
    });
    _activeMigration = operation;
    return operation;
  }

  Future<StorageRootMigrationResult> _migrate() async {
    StorageRootMigrationCheckpoint? checkpoint;
    var checkpointCorrupt = false;
    try {
      checkpoint = await _checkpointStore.read();
    } on StorageRootMigrationCheckpointFormatException {
      checkpointCorrupt = true;
    } catch (_) {
      checkpointCorrupt = true;
    }

    String? customRoot;
    try {
      customRoot = await _readCustomRoot();
    } catch (_) {
      return _blockedWithoutCheckpoint(
        code: StorageRootMigrationFailureCode.unknown,
      );
    }
    if (checkpointCorrupt && customRoot == null) {
      final corruptCleanup = const StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.cleanupPending,
        failureCode: StorageRootMigrationFailureCode.stateCorrupt,
      );
      await _tryWriteCheckpoint(corruptCleanup);
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.cleanupPending,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.stateCorrupt,
          blocksStorageAccess: false,
        ),
      );
    }

    if (checkpoint != null &&
        checkpoint.phase == StorageRootMigrationPhase.cleanupPending) {
      final sourceRoot = checkpoint.sourceRoot;
      final targetRoot = checkpoint.targetRoot;
      if (sourceRoot == null || targetRoot == null) {
        return const StorageRootMigrationResult(
          disposition: StorageRootMigrationDisposition.cleanupPending,
          status: StorageRootMigrationStatus(
            phase: StorageRootMigrationPhase.cleanupPending,
            failureCode: StorageRootMigrationFailureCode.stateCorrupt,
            blocksStorageAccess: false,
          ),
        );
      }
      return _cleanupAfterSwitch(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
      );
    }

    if (checkpoint != null &&
        checkpoint.phase == StorageRootMigrationPhase.readyToSwitch) {
      return _resumeReadyToSwitch(
        checkpoint: checkpoint,
        customRoot: customRoot,
      );
    }

    if (customRoot == null) {
      if (checkpoint != null &&
          checkpoint.phase != StorageRootMigrationPhase.completed) {
        final inconsistent = const StorageRootMigrationCheckpoint(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.stateCorrupt,
        );
        await _tryWriteCheckpoint(inconsistent);
        return const StorageRootMigrationResult(
          disposition: StorageRootMigrationDisposition.cleanupPending,
          status: StorageRootMigrationStatus(
            phase: StorageRootMigrationPhase.cleanupPending,
            failureCode: StorageRootMigrationFailureCode.stateCorrupt,
            blocksStorageAccess: false,
          ),
        );
      }
      await _tryWriteCheckpoint(StorageRootMigrationCheckpoint.completed);
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.notRequired,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.completed,
          blocksStorageAccess: false,
        ),
      );
    }

    final targetRoot = await _readDefaultRootSafely();
    if (targetRoot == null) {
      return _blockedWithoutCheckpoint(
        code: StorageRootMigrationFailureCode.targetUnavailable,
      );
    }

    if (checkpoint != null &&
        checkpoint.phase != StorageRootMigrationPhase.completed) {
      final checkpointSource = checkpoint.sourceRoot;
      final checkpointTarget = checkpoint.targetRoot;
      if (checkpointSource == null ||
          checkpointTarget == null ||
          !_samePath(checkpointSource, customRoot) ||
          !_samePath(checkpointTarget, targetRoot)) {
        return _persistBlocked(
          sourceRoot: customRoot,
          targetRoot: targetRoot,
          code: StorageRootMigrationFailureCode.sourceChanged,
        );
      }
    }

    if (_samePath(customRoot, targetRoot)) {
      return _commitSameRoot(sourceRoot: customRoot, targetRoot: targetRoot);
    }
    if (_isNested(customRoot, targetRoot) ||
        _isNested(targetRoot, customRoot)) {
      return _persistBlocked(
        sourceRoot: customRoot,
        targetRoot: targetRoot,
        code: StorageRootMigrationFailureCode.invalidTopology,
      );
    }

    return _copyVerifySwitch(sourceRoot: customRoot, targetRoot: targetRoot);
  }

  Future<StorageRootMigrationResult> _resumeReadyToSwitch({
    required StorageRootMigrationCheckpoint checkpoint,
    required String? customRoot,
  }) async {
    final sourceRoot = checkpoint.sourceRoot;
    final targetRoot = checkpoint.targetRoot;
    if (sourceRoot == null || targetRoot == null) {
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.blocked,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.blocked,
          failureCode: StorageRootMigrationFailureCode.stateCorrupt,
          blocksStorageAccess: true,
        ),
      );
    }

    if (_samePath(sourceRoot, targetRoot)) {
      if (customRoot != null) {
        try {
          await _locationRepository.setCustomStorageRoot(null);
        } catch (_) {
          return _readySwitchFailed(
            sourceRoot: sourceRoot,
            targetRoot: targetRoot,
          );
        }
      }
      return _completeWithoutCleanup();
    }

    if (customRoot == null) {
      final cleanup = StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.cleanupPending,
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
      );
      try {
        await _checkpointStore.write(cleanup);
      } catch (_) {
        return const StorageRootMigrationResult(
          disposition: StorageRootMigrationDisposition.cleanupPending,
          status: StorageRootMigrationStatus(
            phase: StorageRootMigrationPhase.cleanupPending,
            failureCode: StorageRootMigrationFailureCode.unknown,
            blocksStorageAccess: false,
          ),
        );
      }
      return _cleanupAfterSwitch(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
      );
    }

    if (!_samePath(customRoot, sourceRoot)) {
      return _persistBlocked(
        sourceRoot: customRoot,
        targetRoot: targetRoot,
        code: StorageRootMigrationFailureCode.sourceChanged,
      );
    }

    try {
      final manifest = await _buildManifest(sourceRoot, strictRoot: true);
      await _ensureTargetBaseline(
        targetRoot: targetRoot,
        sourceManifest: manifest,
      );
      await _verifyTarget(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        originalManifest: manifest,
      );
    } on _StorageRootMigrationAbort catch (error) {
      final failedReady = StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.readyToSwitch,
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        failureCode: error.code,
      );
      await _tryWriteCheckpoint(failedReady);
      return StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.blocked,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.readyToSwitch,
          failureCode: error.code,
          blocksStorageAccess: true,
        ),
      );
    }
    return _switchAndCleanup(sourceRoot: sourceRoot, targetRoot: targetRoot);
  }

  Future<StorageRootMigrationResult> _copyVerifySwitch({
    required String sourceRoot,
    required String targetRoot,
  }) async {
    final copying = StorageRootMigrationCheckpoint(
      phase: StorageRootMigrationPhase.copying,
      sourceRoot: sourceRoot,
      targetRoot: targetRoot,
    );
    try {
      await _checkpointStore.write(copying);
    } catch (_) {
      return _blockedWithoutCheckpoint(
        code: StorageRootMigrationFailureCode.unknown,
      );
    }

    try {
      await _requireDirectory(
        sourceRoot,
        failure: StorageRootMigrationFailureCode.sourceUnavailable,
      );
      await _ensureTargetDirectory(targetRoot);
      final manifest = await _buildManifest(sourceRoot, strictRoot: true);
      final missingBytes = await _validateTargetAndCountMissing(
        manifest: manifest,
        targetRoot: targetRoot,
      );
      final availableBytes = await _capacityProbe.availableBytes(targetRoot);
      if (availableBytes != null && availableBytes < missingBytes) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.insufficientSpace,
        );
      }
      await _copyManifest(manifest: manifest, targetRoot: targetRoot);
      await _ensureTargetBaseline(
        targetRoot: targetRoot,
        sourceManifest: manifest,
      );
      await _verifyTarget(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        originalManifest: manifest,
      );
      await _checkpointStore.write(
        StorageRootMigrationCheckpoint(
          phase: StorageRootMigrationPhase.readyToSwitch,
          sourceRoot: sourceRoot,
          targetRoot: targetRoot,
        ),
      );
    } on _StorageRootMigrationAbort catch (error) {
      return _persistBlocked(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: error.code,
      );
    } on StorageRootMigrationFileOperationException catch (error) {
      return _persistBlocked(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: error.code,
      );
    } catch (_) {
      return _persistBlocked(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: StorageRootMigrationFailureCode.unknown,
      );
    }

    return _switchAndCleanup(sourceRoot: sourceRoot, targetRoot: targetRoot);
  }

  Future<StorageRootMigrationResult> _commitSameRoot({
    required String sourceRoot,
    required String targetRoot,
  }) async {
    try {
      await _checkpointStore.write(
        StorageRootMigrationCheckpoint(
          phase: StorageRootMigrationPhase.readyToSwitch,
          sourceRoot: sourceRoot,
          targetRoot: targetRoot,
        ),
      );
      await _locationRepository.setCustomStorageRoot(null);
    } catch (_) {
      return _readySwitchFailed(sourceRoot: sourceRoot, targetRoot: targetRoot);
    }
    return _completeWithoutCleanup();
  }

  Future<StorageRootMigrationResult> _switchAndCleanup({
    required String sourceRoot,
    required String targetRoot,
  }) async {
    try {
      await _locationRepository.setCustomStorageRoot(null);
    } catch (_) {
      return _readySwitchFailed(sourceRoot: sourceRoot, targetRoot: targetRoot);
    }

    final cleanup = StorageRootMigrationCheckpoint(
      phase: StorageRootMigrationPhase.cleanupPending,
      sourceRoot: sourceRoot,
      targetRoot: targetRoot,
    );
    try {
      await _checkpointStore.write(cleanup);
    } catch (_) {
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.cleanupPending,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.unknown,
          blocksStorageAccess: false,
        ),
      );
    }
    return _cleanupAfterSwitch(sourceRoot: sourceRoot, targetRoot: targetRoot);
  }

  Future<StorageRootMigrationResult> _cleanupAfterSwitch({
    required String sourceRoot,
    required String targetRoot,
  }) async {
    try {
      final manifest = await _buildManifest(sourceRoot, strictRoot: false);
      for (final entry in manifest.entries) {
        final targetPath = _targetPath(targetRoot, entry.relativePath);
        if (await _fileOperations.type(targetPath) !=
            StorageRootMigrationEntityType.file) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.verificationFailed,
          );
        }
        final targetFingerprint = await _fileOperations.fingerprint(targetPath);
        if (!targetFingerprint.hasSameContent(entry.fingerprint)) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.verificationFailed,
          );
        }
        await _fileOperations.deleteFile(entry.sourcePath);
      }

      for (final generatedPath in manifest.generatedFiles) {
        await _fileOperations.deleteFile(generatedPath);
      }
      for (final directory in manifest.directories.reversed) {
        await _fileOperations.deleteDirectoryIfEmpty(directory);
      }
    } on _StorageRootMigrationAbort catch (error) {
      return _cleanupPending(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: error.code,
      );
    } on StorageRootMigrationFileOperationException catch (error) {
      return _cleanupPending(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: error.code == StorageRootMigrationFailureCode.permissionDenied
            ? error.code
            : StorageRootMigrationFailureCode.cleanupFailed,
      );
    } catch (_) {
      return _cleanupPending(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        code: StorageRootMigrationFailureCode.cleanupFailed,
      );
    }

    try {
      await _checkpointStore.write(StorageRootMigrationCheckpoint.completed);
    } catch (_) {
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.cleanupPending,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.unknown,
          blocksStorageAccess: false,
        ),
      );
    }
    return const StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.migrated,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.completed,
        blocksStorageAccess: false,
      ),
    );
  }

  Future<_StorageRootManifest> _buildManifest(
    String sourceRoot, {
    required bool strictRoot,
  }) async {
    final sourceType = await _fileOperations.type(sourceRoot);
    if (sourceType != StorageRootMigrationEntityType.directory) {
      throw const _StorageRootMigrationAbort(
        StorageRootMigrationFailureCode.sourceUnavailable,
      );
    }

    final entries = <_StorageRootManifestEntry>[];
    final generatedFiles = <String>[];
    final directories = <String>[];
    final rootEntities = await _fileOperations.list(sourceRoot);
    for (final entity in rootEntities) {
      final name = p.basename(entity.path);
      if (_isGeneratedRootFile(name) || _isTransientFile(name)) {
        continue;
      }
      if (name == 'favorites.json') {
        if (entity.type != StorageRootMigrationEntityType.file) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.unsafeEntity,
          );
        }
        entries.add(await _manifestEntry(sourceRoot, entity.path));
        continue;
      }
      if (name == 'comics' || name == 'novels' || name == 'diagnostics') {
        if (entity.type != StorageRootMigrationEntityType.directory) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.unsafeEntity,
          );
        }
        await _walkManagedDirectory(
          sourceRoot: sourceRoot,
          directoryPath: entity.path,
          entries: entries,
          generatedFiles: generatedFiles,
          directories: directories,
        );
        continue;
      }
      if (strictRoot) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.unsupportedLayout,
        );
      }
    }
    entries.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    directories.sort((left, right) {
      final depth = p.split(left).length.compareTo(p.split(right).length);
      return depth != 0 ? depth : left.compareTo(right);
    });
    return _StorageRootManifest(
      entries: entries,
      generatedFiles: generatedFiles,
      directories: directories,
    );
  }

  Future<void> _walkManagedDirectory({
    required String sourceRoot,
    required String directoryPath,
    required List<_StorageRootManifestEntry> entries,
    required List<String> generatedFiles,
    required List<String> directories,
  }) async {
    directories.add(directoryPath);
    for (final entity in await _fileOperations.list(directoryPath)) {
      final name = p.basename(entity.path);
      if (entity.type == StorageRootMigrationEntityType.directory) {
        if (name == '.tmp') {
          continue;
        }
        await _walkManagedDirectory(
          sourceRoot: sourceRoot,
          directoryPath: entity.path,
          entries: entries,
          generatedFiles: generatedFiles,
          directories: directories,
        );
        continue;
      }
      if (entity.type != StorageRootMigrationEntityType.file) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.unsafeEntity,
        );
      }
      if (name == '.nomedia') {
        generatedFiles.add(entity.path);
        continue;
      }
      if (_isTransientFile(name)) {
        continue;
      }
      entries.add(await _manifestEntry(sourceRoot, entity.path));
    }
  }

  Future<_StorageRootManifestEntry> _manifestEntry(
    String sourceRoot,
    String sourcePath,
  ) async {
    try {
      final relative = p.relative(sourcePath, from: sourceRoot);
      return _StorageRootManifestEntry(
        relativePath: p.posix.joinAll(p.split(relative)),
        sourcePath: sourcePath,
        fingerprint: await _fileOperations.fingerprint(sourcePath),
      );
    } on StorageRootMigrationFileOperationException catch (error) {
      throw _StorageRootMigrationAbort(error.code);
    }
  }

  Future<int> _validateTargetAndCountMissing({
    required _StorageRootManifest manifest,
    required String targetRoot,
  }) async {
    var missingBytes = 0;
    for (final entry in manifest.entries) {
      final destination = _targetPath(targetRoot, entry.relativePath);
      await _validateTargetParents(
        targetRoot: targetRoot,
        destinationPath: destination,
      );
      final type = await _fileOperations.type(destination);
      if (type == StorageRootMigrationEntityType.notFound) {
        missingBytes += entry.fingerprint.length;
        continue;
      }
      if (type != StorageRootMigrationEntityType.file) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
      final targetFingerprint = await _fileOperations.fingerprint(destination);
      if (!targetFingerprint.hasSameContent(entry.fingerprint)) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
    }
    return missingBytes;
  }

  Future<void> _validateTargetParents({
    required String targetRoot,
    required String destinationPath,
  }) async {
    var current = p.dirname(destinationPath);
    while (!_samePath(current, targetRoot)) {
      final type = await _fileOperations.type(current);
      if (type != StorageRootMigrationEntityType.notFound &&
          type != StorageRootMigrationEntityType.directory) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
      final parent = p.dirname(current);
      if (_samePath(parent, current) || !_isNested(targetRoot, current)) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.invalidTopology,
        );
      }
      current = parent;
    }
  }

  Future<void> _copyManifest({
    required _StorageRootManifest manifest,
    required String targetRoot,
  }) async {
    for (final entry in manifest.entries) {
      final destination = _targetPath(targetRoot, entry.relativePath);
      final type = await _fileOperations.type(destination);
      if (type == StorageRootMigrationEntityType.file) {
        final targetFingerprint = await _fileOperations.fingerprint(
          destination,
        );
        if (targetFingerprint.hasSameContent(entry.fingerprint)) {
          continue;
        }
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
      if (type != StorageRootMigrationEntityType.notFound) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.targetConflict,
        );
      }
      try {
        await _fileOperations.copyFileAtomically(
          sourcePath: entry.sourcePath,
          destinationPath: destination,
          temporaryPath: _temporaryPath(targetRoot, entry.relativePath),
          expectedSource: entry.fingerprint,
        );
      } on StorageRootMigrationFileOperationException catch (error) {
        throw _StorageRootMigrationAbort(error.code);
      }
    }
  }

  Future<void> _verifyTarget({
    required String sourceRoot,
    required String targetRoot,
    required _StorageRootManifest originalManifest,
  }) async {
    final currentManifest = await _buildManifest(sourceRoot, strictRoot: true);
    if (!originalManifest.hasSameContent(currentManifest)) {
      throw const _StorageRootMigrationAbort(
        StorageRootMigrationFailureCode.sourceChanged,
      );
    }

    for (final entry in originalManifest.entries) {
      final destination = _targetPath(targetRoot, entry.relativePath);
      if (await _fileOperations.type(destination) !=
          StorageRootMigrationEntityType.file) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.verificationFailed,
        );
      }
      final targetFingerprint = await _fileOperations.fingerprint(destination);
      if (!targetFingerprint.hasSameContent(entry.fingerprint)) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.verificationFailed,
        );
      }
    }

    await _verifyStructuredPayloads(
      manifest: originalManifest,
      targetRoot: targetRoot,
    );
  }

  Future<void> _verifyStructuredPayloads({
    required _StorageRootManifest manifest,
    required String targetRoot,
  }) async {
    final byRelativePath = <String, _StorageRootManifestEntry>{
      for (final entry in manifest.entries) entry.relativePath: entry,
    };
    final favorites = byRelativePath['favorites.json'];
    if (favorites != null) {
      final sourceJson = await _readJsonMap(favorites.sourcePath);
      if (sourceJson != null &&
          await _readJsonMap(_targetPath(targetRoot, favorites.relativePath)) ==
              null) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.verificationFailed,
        );
      }
    } else {
      final targetFavorites = DownloadStorageLayout.resolve(
        targetRoot,
      ).favoritesJsonPath;
      if (await _readJsonMap(targetFavorites) == null) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.verificationFailed,
        );
      }
    }

    for (final entry in manifest.entries) {
      if (!entry.relativePath.startsWith('comics/') ||
          !entry.relativePath.endsWith('/meta.json')) {
        continue;
      }
      final sourceMeta = await _readJsonMap(entry.sourcePath);
      if (sourceMeta == null) {
        continue;
      }
      if (await _readJsonMap(_targetPath(targetRoot, entry.relativePath)) ==
          null) {
        throw const _StorageRootMigrationAbort(
          StorageRootMigrationFailureCode.verificationFailed,
        );
      }
      final chapters = sourceMeta['chapters'];
      if (chapters is! List) {
        continue;
      }
      final metaDirectory = p.posix.dirname(entry.relativePath);
      for (final chapter in chapters.whereType<Map>()) {
        final cbzValue = chapter['cbzFile'];
        if (cbzValue is! String || cbzValue.trim().isEmpty) {
          continue;
        }
        final cbzFile = cbzValue.trim();
        if (p.posix.isAbsolute(cbzFile)) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.unsafeEntity,
          );
        }
        final referenced = p.posix.normalize(
          p.posix.join(metaDirectory, cbzFile),
        );
        if (!p.posix.isWithin(metaDirectory, referenced)) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.unsafeEntity,
          );
        }
        if (byRelativePath.containsKey(referenced) &&
            await _fileOperations.type(_targetPath(targetRoot, referenced)) !=
                StorageRootMigrationEntityType.file) {
          throw const _StorageRootMigrationAbort(
            StorageRootMigrationFailureCode.verificationFailed,
          );
        }
      }
    }
  }

  Future<Map<String, Object?>?> _readJsonMap(String path) async {
    try {
      final decoded = jsonDecode(
        utf8.decode(await _fileOperations.readBytes(path)),
      );
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureTargetBaseline({
    required String targetRoot,
    required _StorageRootManifest sourceManifest,
  }) async {
    final layout = DownloadStorageLayout.resolve(targetRoot);
    await _ensureTargetDirectory(layout.path);
    await _ensureTargetDirectory(layout.comicsPath);
    await _ensureGeneratedFile(
      path: p.join(layout.path, '.nomedia'),
      targetRoot: targetRoot,
      bytes: Uint8List(0),
    );
    await _ensureGeneratedFile(
      path: p.join(layout.comicsPath, '.nomedia'),
      targetRoot: targetRoot,
      bytes: Uint8List(0),
    );
    if (!sourceManifest.entries.any(
      (entry) => entry.relativePath == 'favorites.json',
    )) {
      final encoded = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(DownloadStorageLayout.emptyFavoritesSnapshot())}\n',
      );
      await _ensureGeneratedFile(
        path: layout.favoritesJsonPath,
        targetRoot: targetRoot,
        bytes: Uint8List.fromList(encoded),
      );
    }
  }

  Future<void> _ensureGeneratedFile({
    required String path,
    required String targetRoot,
    required Uint8List bytes,
  }) async {
    final type = await _fileOperations.type(path);
    if (type == StorageRootMigrationEntityType.file) {
      return;
    }
    if (type != StorageRootMigrationEntityType.notFound) {
      throw const _StorageRootMigrationAbort(
        StorageRootMigrationFailureCode.targetConflict,
      );
    }
    try {
      await _fileOperations.writeBytesAtomically(
        destinationPath: path,
        temporaryPath: _temporaryPath(
          targetRoot,
          p.posix.joinAll(p.split(p.relative(path, from: targetRoot))),
        ),
        bytes: bytes,
      );
    } on StorageRootMigrationFileOperationException catch (error) {
      throw _StorageRootMigrationAbort(error.code);
    }
  }

  Future<void> _requireDirectory(
    String path, {
    required StorageRootMigrationFailureCode failure,
  }) async {
    try {
      if (await _fileOperations.type(path) !=
          StorageRootMigrationEntityType.directory) {
        throw _StorageRootMigrationAbort(failure);
      }
    } on StorageRootMigrationFileOperationException catch (error) {
      throw _StorageRootMigrationAbort(
        error.code == StorageRootMigrationFailureCode.permissionDenied
            ? error.code
            : failure,
      );
    }
  }

  Future<void> _ensureTargetDirectory(String path) async {
    final type = await _fileOperations.type(path);
    if (type == StorageRootMigrationEntityType.directory) {
      return;
    }
    if (type != StorageRootMigrationEntityType.notFound) {
      throw const _StorageRootMigrationAbort(
        StorageRootMigrationFailureCode.targetConflict,
      );
    }
    try {
      await _fileOperations.ensureDirectory(path);
    } on StorageRootMigrationFileOperationException catch (error) {
      throw _StorageRootMigrationAbort(
        error.code == StorageRootMigrationFailureCode.permissionDenied ||
                error.code == StorageRootMigrationFailureCode.insufficientSpace
            ? error.code
            : StorageRootMigrationFailureCode.targetUnavailable,
      );
    }
  }

  Future<StorageRootMigrationResult> _persistBlocked({
    required String sourceRoot,
    required String targetRoot,
    required StorageRootMigrationFailureCode code,
  }) async {
    await _tryWriteCheckpoint(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.blocked,
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        failureCode: code,
      ),
    );
    return StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.blocked,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.blocked,
        failureCode: code,
        blocksStorageAccess: true,
      ),
    );
  }

  StorageRootMigrationResult _blockedWithoutCheckpoint({
    required StorageRootMigrationFailureCode code,
  }) {
    return StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.blocked,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.blocked,
        failureCode: code,
        blocksStorageAccess: true,
      ),
    );
  }

  Future<StorageRootMigrationResult> _readySwitchFailed({
    required String sourceRoot,
    required String targetRoot,
  }) async {
    await _tryWriteCheckpoint(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.readyToSwitch,
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        failureCode: StorageRootMigrationFailureCode.switchFailed,
      ),
    );
    return const StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.blocked,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.readyToSwitch,
        failureCode: StorageRootMigrationFailureCode.switchFailed,
        blocksStorageAccess: true,
      ),
    );
  }

  Future<StorageRootMigrationResult> _cleanupPending({
    required String sourceRoot,
    required String targetRoot,
    required StorageRootMigrationFailureCode code,
  }) async {
    await _tryWriteCheckpoint(
      StorageRootMigrationCheckpoint(
        phase: StorageRootMigrationPhase.cleanupPending,
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        failureCode: code,
      ),
    );
    return StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.cleanupPending,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.cleanupPending,
        failureCode: code,
        blocksStorageAccess: false,
      ),
    );
  }

  Future<StorageRootMigrationResult> _completeWithoutCleanup() async {
    try {
      await _checkpointStore.write(StorageRootMigrationCheckpoint.completed);
    } catch (_) {
      return const StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.cleanupPending,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.unknown,
          blocksStorageAccess: false,
        ),
      );
    }
    return const StorageRootMigrationResult(
      disposition: StorageRootMigrationDisposition.migrated,
      status: StorageRootMigrationStatus(
        phase: StorageRootMigrationPhase.completed,
        blocksStorageAccess: false,
      ),
    );
  }

  StorageRootMigrationStatus _statusForCheckpoint(
    StorageRootMigrationCheckpoint checkpoint, {
    required String? customRoot,
  }) {
    final blocksStorageAccess = switch (checkpoint.phase) {
      StorageRootMigrationPhase.copying ||
      StorageRootMigrationPhase.blocked => true,
      StorageRootMigrationPhase.readyToSwitch => customRoot != null,
      StorageRootMigrationPhase.cleanupPending ||
      StorageRootMigrationPhase.completed => false,
    };
    return StorageRootMigrationStatus(
      phase: checkpoint.phase,
      failureCode: checkpoint.failureCode,
      blocksStorageAccess: blocksStorageAccess,
    );
  }

  Future<String?> _readCustomRoot() async {
    final custom = await _locationRepository.getCustomStorageRoot();
    return custom == null ? null : _normalizeRoot(custom);
  }

  Future<String?> _readDefaultRootSafely() async {
    try {
      return _normalizeRoot(await _locationRepository.getDefaultStorageRoot());
    } catch (_) {
      return null;
    }
  }

  Future<void> _tryWriteCheckpoint(
    StorageRootMigrationCheckpoint checkpoint,
  ) async {
    try {
      await _checkpointStore.write(checkpoint);
    } catch (_) {
      // A migration result remains fail closed even when its diagnostic
      // checkpoint cannot be updated. No source file is deleted before switch.
    }
  }

  String _normalizeRoot(String path) {
    return p.normalize(p.absolute(path.trim()));
  }

  bool _samePath(String left, String right) {
    return _comparisonPath(left) == _comparisonPath(right);
  }

  bool _isNested(String parent, String candidate) {
    return p.isWithin(_comparisonPath(parent), _comparisonPath(candidate));
  }

  String _comparisonPath(String path) {
    final normalized = _normalizeRoot(path);
    return io.Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _targetPath(String targetRoot, String relativePath) {
    return p.joinAll(<String>[targetRoot, ...p.posix.split(relativePath)]);
  }

  String _temporaryPath(String targetRoot, String relativePath) {
    final digest = sha256.convert(utf8.encode(relativePath)).toString();
    final destination = _targetPath(targetRoot, relativePath);
    return p.join(
      p.dirname(destination),
      '.y300-migration-${digest.substring(0, 16)}.part',
    );
  }

  bool _isGeneratedRootFile(String name) {
    return name == '.nomedia' || name == '.write_probe';
  }

  bool _isTransientFile(String name) {
    return name.endsWith('.part') ||
        name.contains('.tmp-') ||
        (name.startsWith('.y300-migration-') && name.endsWith('.part'));
  }
}

final class _StorageRootManifestEntry {
  const _StorageRootManifestEntry({
    required this.relativePath,
    required this.sourcePath,
    required this.fingerprint,
  });

  final String relativePath;
  final String sourcePath;
  final StorageRootMigrationFileFingerprint fingerprint;
}

final class _StorageRootManifest {
  const _StorageRootManifest({
    required this.entries,
    required this.generatedFiles,
    required this.directories,
  });

  final List<_StorageRootManifestEntry> entries;
  final List<String> generatedFiles;
  final List<String> directories;

  bool hasSameContent(_StorageRootManifest other) {
    if (entries.length != other.entries.length) {
      return false;
    }
    for (var index = 0; index < entries.length; index += 1) {
      final left = entries[index];
      final right = other.entries[index];
      if (left.relativePath != right.relativePath ||
          !left.fingerprint.hasSameContent(right.fingerprint)) {
        return false;
      }
    }
    return true;
  }
}

final class _StorageRootMigrationAbort implements Exception {
  const _StorageRootMigrationAbort(this.code);

  final StorageRootMigrationFailureCode code;
}
