import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/storage/data/default_storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

void main() {
  test('concurrent readiness calls share one migration attempt', () async {
    final coordinator = _ControllableMigrationCoordinator(
      inspectStatus: _copyingStatus,
    );
    final gate = DefaultStorageRootAccessGate(
      migrationCoordinator: coordinator,
    );

    final first = gate.ensureReady();
    final second = gate.ensureReady();
    await coordinator.migrationStarted.future;

    expect(coordinator.inspectCalls, 1);
    expect(coordinator.migrateCalls, 1);
    coordinator.completeMigration(_migratedResult);

    expect(await first, same(_migratedResult));
    expect(await second, same(_migratedResult));
  });

  test('blocked result is cached until explicit retry', () async {
    final coordinator = _ControllableMigrationCoordinator(
      inspectStatus: _copyingStatus,
    );
    final gate = DefaultStorageRootAccessGate(
      migrationCoordinator: coordinator,
    );

    final first = gate.ensureReady();
    await coordinator.migrationStarted.future;
    coordinator.completeMigration(_blockedResult);
    expect(await first, same(_blockedResult));

    expect(await gate.ensureReady(), same(_blockedResult));
    expect(coordinator.migrateCalls, 1);

    coordinator.resetMigration(inspectStatus: _copyingStatus);
    final retry = gate.retry();
    await coordinator.migrationStarted.future;
    expect(coordinator.migrateCalls, 2);
    coordinator.completeMigration(_migratedResult);
    expect(await retry, same(_migratedResult));
  });

  test('retry waits for active access and blocks new access', () async {
    final coordinator = _ControllableMigrationCoordinator(
      inspectStatus: _copyingStatus,
    );
    final gate = DefaultStorageRootAccessGate(
      migrationCoordinator: coordinator,
    );
    final initial = gate.ensureReady();
    await coordinator.migrationStarted.future;
    coordinator.completeMigration(_blockedResult);
    await initial;

    final activeEntered = Completer<void>();
    final releaseActive = Completer<void>();
    final active = gate.runWithAccess(() async {
      activeEntered.complete();
      await releaseActive.future;
    });
    await activeEntered.future;

    coordinator.resetMigration(inspectStatus: _copyingStatus);
    final retry = gate.retry();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.migrateCalls, 1);

    var queuedEntered = false;
    final queued = gate.runWithAccess(() async {
      queuedEntered = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(queuedEntered, isFalse);

    releaseActive.complete();
    await active;
    await coordinator.migrationStarted.future;
    expect(coordinator.migrateCalls, 2);
    expect(queuedEntered, isFalse);

    coordinator.completeMigration(_migratedResult);
    await retry;
    await queued;
    expect(queuedEntered, isTrue);
  });

  test('nested access in the same async chain is reentrant', () async {
    final coordinator = _ControllableMigrationCoordinator(
      inspectStatus: _completedStatus,
    );
    final gate = DefaultStorageRootAccessGate(
      migrationCoordinator: coordinator,
    );

    final value = await gate.runWithAccess(
      () => gate.runWithAccess(() async => 42),
    );

    expect(value, 42);
    expect(coordinator.migrateCalls, 0);
  });

  test('cleanup pending allows default-root access immediately', () async {
    final coordinator = _ControllableMigrationCoordinator(
      inspectStatus: _cleanupPendingStatus,
    );
    final gate = DefaultStorageRootAccessGate(
      migrationCoordinator: coordinator,
    );

    final result = await gate.ensureReady();
    expect(result.disposition, StorageRootMigrationDisposition.cleanupPending);

    var accessed = false;
    await gate.runWithAccess(() async => accessed = true);
    expect(accessed, isTrue);
    expect(coordinator.migrateCalls, 1);

    coordinator.completeMigration(_migratedResult);
  });

  test(
    'cleanup failure never closes access to the active default root',
    () async {
      final coordinator = _ThrowingCleanupCoordinator();
      final gate = DefaultStorageRootAccessGate(
        migrationCoordinator: coordinator,
      );

      final initial = await gate.ensureReady();
      expect(
        initial.disposition,
        StorageRootMigrationDisposition.cleanupPending,
      );
      await Future<void>.delayed(Duration.zero);

      var accessed = false;
      await gate.runWithAccess(() async => accessed = true);
      expect(accessed, isTrue);

      final retried = await gate.retry();
      expect(
        retried.disposition,
        StorageRootMigrationDisposition.cleanupPending,
      );
      expect(retried.status.blocksStorageAccess, isFalse);
      expect(coordinator.migrateCalls, 2);
    },
  );
}

const _copyingStatus = StorageRootMigrationStatus(
  phase: StorageRootMigrationPhase.copying,
  blocksStorageAccess: true,
);
const _completedStatus = StorageRootMigrationStatus(
  phase: StorageRootMigrationPhase.completed,
  blocksStorageAccess: false,
);
const _cleanupPendingStatus = StorageRootMigrationStatus(
  phase: StorageRootMigrationPhase.cleanupPending,
  failureCode: StorageRootMigrationFailureCode.cleanupFailed,
  blocksStorageAccess: false,
);
const _migratedResult = StorageRootMigrationResult(
  disposition: StorageRootMigrationDisposition.migrated,
  status: _completedStatus,
);
const _blockedResult = StorageRootMigrationResult(
  disposition: StorageRootMigrationDisposition.blocked,
  status: StorageRootMigrationStatus(
    phase: StorageRootMigrationPhase.blocked,
    failureCode: StorageRootMigrationFailureCode.targetConflict,
    blocksStorageAccess: true,
  ),
);

final class _ControllableMigrationCoordinator
    implements StorageRootMigrationCoordinator {
  _ControllableMigrationCoordinator({required this.inspectStatus});

  StorageRootMigrationStatus inspectStatus;
  int inspectCalls = 0;
  int migrateCalls = 0;
  Completer<void> migrationStarted = Completer<void>();
  Completer<StorageRootMigrationResult> _migration =
      Completer<StorageRootMigrationResult>();

  @override
  Future<StorageRootMigrationStatus> inspect() async {
    inspectCalls += 1;
    return inspectStatus;
  }

  @override
  Future<StorageRootMigrationResult> migrateToDefault() {
    migrateCalls += 1;
    if (!migrationStarted.isCompleted) {
      migrationStarted.complete();
    }
    return _migration.future;
  }

  void completeMigration(StorageRootMigrationResult result) {
    _migration.complete(result);
  }

  void resetMigration({required StorageRootMigrationStatus inspectStatus}) {
    this.inspectStatus = inspectStatus;
    migrationStarted = Completer<void>();
    _migration = Completer<StorageRootMigrationResult>();
  }
}

final class _ThrowingCleanupCoordinator
    implements StorageRootMigrationCoordinator {
  int migrateCalls = 0;

  @override
  Future<StorageRootMigrationStatus> inspect() async => _cleanupPendingStatus;

  @override
  Future<StorageRootMigrationResult> migrateToDefault() async {
    migrateCalls += 1;
    throw StateError('fixture cleanup failure');
  }
}
