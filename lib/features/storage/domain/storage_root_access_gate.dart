import 'package:y300/features/storage/domain/storage_root_migration.dart';

/// Coordinates process-wide access to the shared download storage root.
///
/// A migration attempt owns an exclusive barrier while the effective root can
/// still change. Once an attempt is blocked, callers continue against the
/// intact custom root until an explicit retry or a new process.
abstract interface class StorageRootAccessGate {
  Future<StorageRootMigrationResult> ensureReady();

  Future<StorageRootMigrationResult> retry();

  Future<T> runWithAccess<T>(Future<T> Function() operation);
}
