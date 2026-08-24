import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('package remains pure Dart and independent from Y300', () {
    const forbidden = <String>[
      'package:flutter/',
      'package:flutter_riverpod/',
      'package:sqflite/',
      'package:y300/',
    ];
    final violations = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (forbidden.any(source.contains)) violations.add(file.path);
    }

    expect(violations, isEmpty);
  });
}
