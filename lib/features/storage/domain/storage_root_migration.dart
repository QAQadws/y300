enum StorageRootMigrationPhase {
  copying,
  readyToSwitch,
  cleanupPending,
  completed,
  blocked,
}

enum StorageRootMigrationFailureCode {
  sourceUnavailable,
  targetUnavailable,
  invalidTopology,
  unsafeEntity,
  unsupportedLayout,
  insufficientSpace,
  permissionDenied,
  targetConflict,
  copyFailed,
  verificationFailed,
  switchFailed,
  cleanupFailed,
  stateCorrupt,
  sourceChanged,
  unknown,
}

enum StorageRootMigrationDisposition {
  notRequired,
  migrated,
  cleanupPending,
  blocked,
}

final class StorageRootMigrationStatus {
  const StorageRootMigrationStatus({
    required this.phase,
    required this.blocksStorageAccess,
    this.failureCode,
  });

  final StorageRootMigrationPhase phase;
  final StorageRootMigrationFailureCode? failureCode;

  /// Whether callers must keep using the current custom root.
  ///
  /// Cleanup failures happen after the default root is active, so they do not
  /// block normal storage access.
  final bool blocksStorageAccess;
}

final class StorageRootMigrationResult {
  const StorageRootMigrationResult({
    required this.disposition,
    required this.status,
  });

  final StorageRootMigrationDisposition disposition;
  final StorageRootMigrationStatus status;
}

abstract interface class StorageRootMigrationCoordinator {
  Future<StorageRootMigrationStatus> inspect();

  Future<StorageRootMigrationResult> migrateToDefault();
}

abstract interface class StorageRootCapacityProbe {
  /// Returns available bytes for [path], or `null` when the platform cannot
  /// provide a reliable value.
  Future<int?> availableBytes(String path);
}

final class UnavailableStorageRootCapacityProbe
    implements StorageRootCapacityProbe {
  const UnavailableStorageRootCapacityProbe();

  @override
  Future<int?> availableBytes(String path) async => null;
}
