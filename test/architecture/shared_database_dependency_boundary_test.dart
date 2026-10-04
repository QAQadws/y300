import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared database consumers use the neutral public lifecycle entry', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll('\\', '/');
      final source = file.readAsStringSync(encoding: utf8);
      if (source.contains('comic_local_db.dart') ||
          RegExp(r'\bComicLocalDb\b').hasMatch(source)) {
        violations.add('$path: retired comic-owned database entry');
      }
      if (path.startsWith('lib/core/persistence/')) continue;
      // Schema and version assembly stay internal to the shared persistence module.
      for (final directive in RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(source)) {
        final uri = directive.group(1)!;
        if (uri.contains('/persistence/schema/') ||
            uri.endsWith('/app_database_schema.dart') ||
            uri.endsWith('/app_database_migrations.dart')) {
          violations.add('$path: imports database implementation $uri');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
