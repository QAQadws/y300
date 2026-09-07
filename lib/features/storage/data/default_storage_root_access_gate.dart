import 'dart:async';

import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final class DefaultStorageRootAccessGate implements StorageRootAccessGate {
  DefaultStorageRootAccessGate({
    required StorageRootMigrationCoordinator migrationCoordinator,
  }) : _migrationCoordinator = migrationCoordinator;

  static final Object _zoneKey = Object();

  final StorageRootMigrationCoordinator _migrationCoordinator;

  StorageRootMigrationResult? _settledResult;
  Future<StorageRootMigrationResult>? _activeMigration;
  Completer<void>? _exclusiveBarrier;
  Completer<void>? _accessesDrained;
  int _activeAccesses = 0;

  @override
  Future<StorageRootMigrationResult> ensureReady() {
    final settled = _settledResult;
    if (settled != null) {
      return Future<StorageRootMigrationResult>.value(settled);
    }
    return _startMigration(force: false);
  }

  @override
  Future<StorageRootMigrationResult> retry() {
    _settledResult = null;
    return _startMigration(force: true);
  }

  @override
  Future<T> runWithAccess<T>(Future<T> Function() operation) async {
    if (identical(Zone.current[_zoneKey], this)) {
      return operation();
    }

    await ensureReady();
    while (true) {
      final barrier = _exclusiveBarrier;
      if (barrier != null) {
        await barrier.future;
        continue;
      }

      _activeAccesses += 1;
      if (_exclusiveBarrier == null) {
        break;
      }
      _releaseAccess();
    }

    try {
      return await runZoned(
        operation,
        zoneValues: <Object, Object>{_zoneKey: this},
      );
    } finally {
      _releaseAccess();
    }
  }

  Future<StorageRootMigrationResult> _startMigration({required bool force}) {
    final active = _activeMigration;
    if (active != null) {
      return active;
    }
    if (!force) {
      final settled = _settledResult;
      if (settled != null) {
        return Future<StorageRootMigrationResult>.value(settled);
      }
    }

    late final Future<StorageRootMigrationResult> migration;
    migration = _inspectAndMigrate(force: force)
        .catchError((Object _) {
          final result = const StorageRootMigrationResult(
            disposition: StorageRootMigrationDisposition.blocked,
            status: StorageRootMigrationStatus(
              phase: StorageRootMigrationPhase.blocked,
              failureCode: StorageRootMigrationFailureCode.unknown,
              blocksStorageAccess: true,
            ),
          );
          _settledResult = result;
          return result;
        })
        .whenComplete(() {
          if (identical(_activeMigration, migration)) {
            _activeMigration = null;
          }
        });
    _activeMigration = migration;
    return migration;
  }

  Future<StorageRootMigrationResult> _inspectAndMigrate({
    required bool force,
  }) async {
    final inspected = await _migrationCoordinator.inspect();
    if (inspected.phase == StorageRootMigrationPhase.completed) {
      final result = StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.notRequired,
        status: inspected,
      );
      _settledResult = result;
      return result;
    }

    // The default root is already active in cleanupPending (and in the small
    // crash window where readyToSwitch was committed before cleanup state).
    // Cleanup may continue concurrently because it only deletes source files
    // after re-verifying their target copies.
    if (!inspected.blocksStorageAccess) {
      if (!force) {
        final cleanupStatus = StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: inspected.failureCode,
          blocksStorageAccess: false,
        );
        final pending = StorageRootMigrationResult(
          disposition: StorageRootMigrationDisposition.cleanupPending,
          status: cleanupStatus,
        );
        _settledResult = pending;
        unawaited(_finishNonBlockingCleanup());
        return pending;
      }
      return _finishNonBlockingCleanup();
    }

    return _runExclusiveMigration();
  }

  Future<StorageRootMigrationResult> _runExclusiveMigration() async {
    final barrier = Completer<void>();
    _exclusiveBarrier = barrier;
    try {
      if (_activeAccesses > 0) {
        _accessesDrained ??= Completer<void>();
        await _accessesDrained!.future;
      }
      final result = await _migrationCoordinator.migrateToDefault();
      _settledResult = result;
      return result;
    } finally {
      if (identical(_exclusiveBarrier, barrier)) {
        _exclusiveBarrier = null;
        barrier.complete();
      }
    }
  }

  Future<StorageRootMigrationResult> _finishNonBlockingCleanup() async {
    try {
      final result = await _migrationCoordinator.migrateToDefault();
      _settledResult = result;
      return result;
    } catch (_) {
      // The default root is already authoritative. An unexpected cleanup
      // failure must never close the access gate or revive the old root.
      const result = StorageRootMigrationResult(
        disposition: StorageRootMigrationDisposition.cleanupPending,
        status: StorageRootMigrationStatus(
          phase: StorageRootMigrationPhase.cleanupPending,
          failureCode: StorageRootMigrationFailureCode.cleanupFailed,
          blocksStorageAccess: false,
        ),
      );
      _settledResult = result;
      return result;
    }
  }

  void _releaseAccess() {
    _activeAccesses -= 1;
    if (_activeAccesses != 0) {
      return;
    }
    final drained = _accessesDrained;
    _accessesDrained = null;
    if (drained != null && !drained.isCompleted) {
      drained.complete();
    }
  }
}
