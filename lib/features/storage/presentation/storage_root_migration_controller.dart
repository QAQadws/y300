import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final storageRootMigrationControllerProvider =
    AsyncNotifierProvider<
      StorageRootMigrationController,
      StorageRootMigrationResult
    >(StorageRootMigrationController.new);

final class StorageRootMigrationController
    extends AsyncNotifier<StorageRootMigrationResult> {
  @override
  Future<StorageRootMigrationResult> build() {
    return ref.read(storageRootAccessGateProvider).ensureReady();
  }

  Future<void> retry() async {
    if (state.isLoading) {
      return;
    }
    state = const AsyncLoading<StorageRootMigrationResult>();
    state = await AsyncValue.guard(
      ref.read(storageRootAccessGateProvider).retry,
    );
  }
}
