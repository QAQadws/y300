import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _collaborators = <String>[
  'lib/features/favorites/data/services/favorite_detail_filler.dart',
  'lib/features/favorites/data/services/favorite_sync_maintenance.dart',
  'lib/features/favorites/data/services/favorite_snapshot_writer.dart',
];

void main() {
  test(
    'favorite sync collaborators keep orchestration and Host ownership outside',
    () {
      final violations = <String>[];
      for (final path in _collaborators) {
        violations.addAll(
          _violations(path, File(path).readAsStringSync(encoding: utf8)),
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'collaborators reject facade cycles, presentation and direct transport',
    () {
      expect(
        _violations(_collaborators.first, '''
import 'favorite_sync_service.dart';
import '../../presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/core/network/yamibo_http_gateway.dart';
'''),
        hasLength(3),
      );
    },
  );

  test('contracts and documented examples remain valid dependencies', () {
    expect(
      _violations(_collaborators.first, '''
/* import 'favorite_sync_service.dart'; */
const example = "import 'package:flutter/material.dart';";
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../repositories/local_favorite_repository.dart';
import '../../domain/services/library_post_ingest_task_runner.dart';
'''),
      isEmpty,
    );
  });
}

List<String> _violations(String path, String source) {
  final violations = <String>[];
  for (final uri in dartDependencyDirectiveUris(source)) {
    final target = resolveDartDependencyTarget(path, uri);
    if (target.endsWith('/favorite_sync_service.dart') ||
        target.startsWith('package:flutter/') ||
        target.startsWith('lib/app/') ||
        target.contains('/presentation/') ||
        target.startsWith('lib/core/network/')) {
      violations.add('$path -> $target');
    }
  }
  return violations;
}
