import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration execution is owned by the shared storage access gate', () {
    final callers = Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains('.migrateToDefault()'),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      callers,
      <String>[
        'lib/features/storage/data/default_storage_root_access_gate.dart',
      ],
      reason:
          'Production migration attempts must pass through the process-wide '
          'exclusive access gate.',
    );
  });

  test('shared storage service is decorated with migration gating', () {
    final providers = File(
      'lib/features/storage/data/storage_providers.dart',
    ).readAsStringSync();

    expect(providers, contains('MigrationGatedDownloadStorageService'));
    expect(providers, contains('storageRootAccessGateProvider'));
  });

  test('shared-root consumers keep their full file operations gated', () {
    final queue = File(
      'lib/features/comic/domain/services/comic_download_queue_service.dart',
    ).readAsStringSync();
    final comicStorage = File(
      'lib/features/comic/data/services/comic_download_service.dart',
    ).readAsStringSync();
    final diagnostics = File(
      'lib/features/cache/data/services/cache_diagnostic_export_service.dart',
    ).readAsStringSync();
    final accounting = File(
      'lib/features/cache/data/services/storage_usage_adapters.dart',
    ).readAsStringSync();
    final startup = File(
      'lib/features/startup/presentation/main_shell_page.dart',
    ).readAsStringSync();

    expect(queue, contains('_storageRootAccessGate.runWithAccess'));
    expect(comicStorage, contains('MigrationGatedComicDownloadService'));
    expect(diagnostics, contains('_storageRootAccessGate.runWithAccess'));
    expect(accounting, contains('_storageRootAccessGate.runWithAccess'));
    expect(startup, contains('storageRootAccessGateProvider'));
    expect(startup, contains('comicDownloadQueueProvider).start()'));
  });

  test('custom path UI is hidden while rollback implementation remains', () {
    final page = File(
      'lib/features/more/presentation/data_storage_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/more/presentation/data_storage_controller.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/more/data/data_storage_settings_repository.dart',
    ).readAsStringSync();

    expect(page, isNot(contains('chooseStorageDirectory()')));
    expect(page, isNot(contains('restoreDefaultStorageDirectory()')));
    expect(controller, contains('chooseStorageDirectory()'));
    expect(controller, contains('restoreDefaultStorageDirectory()'));
    expect(repository, contains('pickDirectory()'));
    expect(repository, contains('setCustomStoragePath'));
  });
}
