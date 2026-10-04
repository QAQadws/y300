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
      final ownsDatabase = path.startsWith('lib/core/persistence/');
      for (final directive in RegExp(
        r'^\s*(?:import|export)\s+([^;]+);',
        multiLine: true,
      ).allMatches(source)) {
        // Include conditional import/export URIs in the same bounded directive.
        for (final quoted in RegExp(
          r'''['"]([^'"]+)['"]''',
        ).allMatches(directive.group(1)!)) {
          final uri = quoted.group(1)!;
          if (ownsDatabase) {
            if (uri.contains('/features/') || uri.contains('/app/')) {
              violations.add(
                '$path: persistence depends on application/feature $uri',
              );
            }
          } else if (uri.contains('/persistence/schema/') ||
              uri.endsWith('/app_database_schema.dart') ||
              uri.endsWith('/app_database_migrations.dart') ||
              uri.endsWith('/app_database_tables.dart')) {
            violations.add('$path: imports database implementation $uri');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
