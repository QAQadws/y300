import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account consumers use the shared auth application boundary', () {
    final obsoleteImports = <String>[];
    for (final file in _dartFiles('lib')) {
      final source = file.readAsStringSync(encoding: utf8);
      for (final directive in _directives(source)) {
        if (directive.contains('profile_session_owner.dart') ||
            directive.contains(
              'auth/presentation/auth_session_controller.dart',
            )) {
          obsoleteImports.add(file.path);
        }
      }
    }
    expect(obsoleteImports, isEmpty);
  });

  test(
    'auth session models remain independent of application and UI wiring',
    () {
      final forbidden = <String>[];
      for (final file in _dartFiles('lib/features/auth/domain/models')) {
        for (final directive in _directives(
          file.readAsStringSync(encoding: utf8),
        )) {
          if (directive.contains('/application/') ||
              directive.contains('/presentation/') ||
              directive.contains('/data/') ||
              directive.contains('package:flutter') ||
              directive.contains('core/network/')) {
            forbidden.add('${file.path}: $directive');
          }
        }
      }
      expect(forbidden, isEmpty);
    },
  );
}

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Iterable<String> _directives(String source) => RegExp(
  r'^\s*(?:import|export)\s+[^;]+;',
  multiLine: true,
).allMatches(source).map((match) => match.group(0)!);
