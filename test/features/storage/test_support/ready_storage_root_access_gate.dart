import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final class ReadyStorageRootAccessGate implements StorageRootAccessGate {
  const ReadyStorageRootAccessGate();

  static const result = StorageRootMigrationResult(
    disposition: StorageRootMigrationDisposition.notRequired,
    status: StorageRootMigrationStatus(
      phase: StorageRootMigrationPhase.completed,
      blocksStorageAccess: false,
    ),
  );

  @override
  Future<StorageRootMigrationResult> ensureReady() async => result;

  @override
  Future<StorageRootMigrationResult> retry() async => result;

  @override
  Future<T> runWithAccess<T>(Future<T> Function() operation) => operation();
}
