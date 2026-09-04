import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage root migration stays dormant until slice 2', () {
    const providerName = 'storageRootMigrationCoordinatorProvider';
    const allowedDeclaration =
        'lib/features/storage/data/storage_providers.dart';
    final references = Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains(providerName))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      references,
      <String>[allowedDeclaration],
      reason:
          'Slice 0-1 only provides the migration engine. Startup, queues, '
          'and storage consumers must not activate it before slice 2 gates '
          'all shared-root reads and writes.',
    );
  });
}
