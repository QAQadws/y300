import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

void main() {
  test(
    'native document graph stays data-only and cannot reach legacy renderer',
    () {
      const root = 'packages/forum_content_renderer/lib/';
      final pending = Directory('${root}src/document')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => normalizeDartSourcePath(file.path))
          .toList();
      final visited = <String>{};
      final violations = <String>[];
      while (pending.isNotEmpty) {
        final path = pending.removeLast();
        if (!visited.add(path)) continue;
        final source = File(path).readAsStringSync(encoding: utf8);
        for (final uri in dartDependencyDirectiveUris(source)) {
          if (uri == 'dart:ui' ||
              uri == 'dart:io' ||
              uri == 'dart:ffi' ||
              uri.startsWith('package:flutter/') ||
              uri.startsWith('package:flutter_widget_from_html') ||
              uri.startsWith('package:y300/') ||
              uri.startsWith('package:flutter_riverpod/') ||
              uri == 'package:yamibo_forum_client/yamibo_forum_client.dart') {
            violations.add('$path -> $uri');
          }
          const ownPackage = 'package:forum_content_renderer/';
          final target = uri.startsWith(ownPackage)
              ? '$root${uri.substring(ownPackage.length)}'
              : resolveDartDependencyTarget(path, uri);
          if (target.startsWith(root)) pending.add(target);
        }
      }
      expect(violations, isEmpty);
    },
  );
}
