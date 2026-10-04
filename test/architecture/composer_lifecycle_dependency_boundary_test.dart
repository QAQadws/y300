import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _retiredDraftContract =
    'lib/features/composer_shared/data/repositories/composer_draft_repository.dart';
const _draftContract =
    'lib/features/composer_shared/domain/repositories/composer_draft_repository.dart';
const _draftCoordinator =
    'lib/features/composer_shared/application/composer_draft_coordinator.dart';

void main() {
  test(
    'draft coordination and contracts stay independent of implementations and UI',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = normalizeDartSourcePath(file.path);
        violations.addAll(
          _violations(source, file.readAsStringSync(encoding: utf8)),
        );
      }
      expect(File(_draftContract).existsSync(), isTrue);
      expect(File(_draftCoordinator).existsSync(), isTrue);
      expect(File(_retiredDraftContract).existsSync(), isFalse);
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test('new lifecycle implementation and UI dependencies are rejected', () {
    expect(
      _violations(_draftCoordinator, '''
import '../data/repositories/new_repository.dart';
export 'package:y300/features/composer_shared/presentation/controllers/new_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
'''),
      hasLength(3),
    );
    expect(
      _violations('lib/features/reply/presentation/new_controller.dart', '''
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
'''),
      hasLength(1),
    );
    expect(
      _violations(_draftCoordinator, '''
import 'dart:async';
import '../domain/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
// import 'package:flutter/widgets.dart';
'''),
      isEmpty,
    );
  });
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> ${resolveDartDependencyTarget(source, uri)}',
];

bool _forbidden(String source, String target) {
  if (target == _retiredDraftContract) return true;
  if (source != _draftContract && source != _draftCoordinator) return false;
  return target.contains('/data/') ||
      target.contains('/presentation/') ||
      target.startsWith('lib/app/') ||
      target.startsWith('package:flutter') ||
      target == 'dart:ui';
}
