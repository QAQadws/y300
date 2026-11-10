import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _coordinator =
    'lib/features/library_shared/presentation/services/unified_detail_operation_coordinator.dart';
const _controller =
    'lib/features/library_shared/presentation/controllers/unified_detail_controller.dart';

void main() {
  test(
    'detail operation coordination stays pure and internal to its controller',
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
      expect(File(_coordinator).existsSync(), isTrue);
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'coordinator rejects UI, persistence, protocols and feature dependencies',
    () {
      expect(
        _violations(_coordinator, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../data/repository.dart';
import '../../domain/contracts/detail_module_adapter.dart';
import '../controllers/unified_detail_controller.dart';
'''),
        hasLength(6),
      );
      expect(_violations(_coordinator, "import 'dart:async';"), isEmpty);
    },
  );

  test('only detail controller may import the operation coordinator', () {
    const dependency =
        "import 'package:y300/features/library_shared/presentation/services/unified_detail_operation_coordinator.dart';";
    expect(_violations(_controller, dependency), isEmpty);
    expect(
      _violations('lib/features/comic/presentation/page.dart', dependency),
      hasLength(1),
    );
    expect(
      _violations(
        'lib/features/library_shared/presentation/pages/page.dart',
        dependency,
      ),
      hasLength(1),
    );
  });
}

List<String> _violations(String source, String code) => [
  for (final uri in dartDependencyDirectiveUris(code))
    if ((source == _coordinator && uri != 'dart:async') ||
        (resolveDartDependencyTarget(source, uri) == _coordinator &&
            source != _controller))
      '$source -> $uri',
];
