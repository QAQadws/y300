import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('package remains pure Dart and independent from Y300', () {
    const forbidden = <String>[
      'package:flutter/',
      'package:flutter_riverpod/',
      'package:sqflite/',
      'package:flutter_cache_manager/',
      'package:y300/',
    ];
    final violations = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (forbidden.any(source.contains)) violations.add(file.path);
    }

    expect(violations, isEmpty);
  });

  test('package exposes only the three intentional public entrypoints', () {
    final entrypoints =
        Directory('lib')
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map((file) => file.uri.pathSegments.last)
            .toList()
          ..sort();

    expect(entrypoints, <String>[
      'yamibo_forum_client.dart',
      'yamibo_forum_client_adapters.dart',
      'yamibo_forum_client_contracts.dart',
    ]);
  });

  test('standalone example uses only the public pure-Dart facade', () {
    final source = File('example/basic_read.dart').readAsStringSync();

    expect(source, contains('yamibo_forum_client.dart'));
    expect(source, isNot(contains('package:yamibo_forum_client/src/')));
    expect(source, isNot(contains('package:y300/')));
    expect(source, isNot(contains('package:flutter/')));
  });
}
