import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _shell = 'lib/features/startup/presentation/main_shell_page.dart';
const _coordinator = 'lib/app/startup/main_shell_startup_coordinator.dart';

void main() {
  test('shell navigation stays separate from feature startup assembly', () {
    for (final path in [_shell, _coordinator]) {
      expect(
        _violations(path, File(path).readAsStringSync(encoding: utf8)),
        isEmpty,
      );
    }
  });

  test(
    'startup assembly and UI dependencies cannot return across the boundary',
    () {
      expect(
        _violations(_shell, '''
import '../../comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/profile/presentation/account_display_controller.dart';
'''),
        hasLength(2),
      );
      expect(
        _violations(_coordinator, '''
import 'package:flutter/widgets.dart';
import '../storage/storage_accounting_providers.dart';
'''),
        hasLength(2),
      );
      expect(
        _violations(_shell, '''
// import '../../comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/app/startup/main_shell_startup_providers.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_bottom_bar.dart';
'''),
        isEmpty,
      );
    },
  );
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> $uri',
];

bool _forbidden(String source, String target) {
  if (source == _shell) {
    return (target.startsWith('lib/features/') && target.contains('/data/')) ||
        target.endsWith('/account_display_controller.dart') ||
        target.endsWith('/library_task_text_resolver.dart');
  }
  return target.startsWith('package:flutter') ||
      target.startsWith('lib/features/') ||
      (target.startsWith('lib/app/') && target.endsWith('_providers.dart'));
}
