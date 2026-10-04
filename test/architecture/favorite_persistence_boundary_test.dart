import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _localRoot = 'lib/features/favorites/data/repositories/local/';
const _facade =
    'lib/features/favorites/data/repositories/local_favorite_repository.dart';

void main() {
  test(
    'favorite persistence collaborators keep workflows outside SQLite ownership',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final path = normalizeDartSourcePath(file.path);
        violations.addAll(
          _violations(path, file.readAsStringSync(encoding: utf8)),
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test('stores reject facade cycles, remote sources and UI dependencies', () {
    expect(
      _violations('${_localRoot}favorite_sync_store.dart', '''
import '../local_favorite_repository.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
export '../../services/favorite_sync_service.dart';
import 'package:flutter/material.dart';
'''),
      hasLength(4),
    );
  });

  test(
    'the shared lifecycle entry, row mapper and domain query utilities stay allowed',
    () {
      expect(
        _violations('${_localRoot}favorite_shelf_read_model.dart', '''
/* export '../local_favorite_repository.dart'; */
const example = "import 'package:flutter/material.dart';";
import 'package:y300/core/persistence/app_database.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'favorite_cache_row_mapper.dart';
import '../../../domain/models/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
'''),
        isEmpty,
      );
    },
  );

  test(
    'external consumers use the repository rather than its private stores',
    () {
      const importSource =
          "import 'package:y300/features/favorites/data/repositories/local/favorite_sync_store.dart';";
      expect(_violations(_facade, importSource), isEmpty);
      expect(
        _violations(
          'lib/features/favorites/data/providers/new_provider.dart',
          importSource,
        ),
        hasLength(1),
      );
    },
  );
}

List<String> _violations(String path, String source) {
  final violations = <String>[];
  for (final uri in dartDependencyDirectiveUris(source)) {
    final target = resolveDartDependencyTarget(path, uri);
    if (target.startsWith(_localRoot) &&
        !path.startsWith(_localRoot) &&
        path != _facade) {
      violations.add('$path -> $target');
      continue;
    }
    if (!path.startsWith(_localRoot)) continue;
    if (target.endsWith('/local_favorite_repository.dart') ||
        target.startsWith('package:flutter/') ||
        target == 'package:yamibo_forum_client/yamibo_forum_client.dart' ||
        target.startsWith('lib/app/') ||
        target.startsWith('lib/core/network/') ||
        target.contains('/presentation/') ||
        target.startsWith('lib/features/favorites/data/services/')) {
      violations.add('$path -> $target');
    }
  }
  return violations;
}
