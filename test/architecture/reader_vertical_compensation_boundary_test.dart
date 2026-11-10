import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _coordinator =
    'lib/features/reader_shared/presentation/engine/reader_vertical_compensation_coordinator.dart';
const _engine =
    'lib/features/reader_shared/presentation/engine/image_reader_engine.dart';

void main() {
  test(
    'vertical compensation is an internal Flutter host over public geometry',
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
    'viewport compensation cannot acquire image data, policies or persistence',
    () {
      expect(
        _violations(_coordinator, '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../reader_preferences/reader_preferences_provider.dart';
import 'reader_capability.dart';
import '../../domain/continuous_image/continuous_image_models.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:continuous_image_geometry/src/continuous_image_scroll_anchor_coordinator.dart';
'''),
        hasLength(6),
      );
      expect(
        _violations(_coordinator, '''
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:continuous_image_geometry/continuous_image_geometry.dart';
'''),
        isEmpty,
      );
    },
  );

  test('engine barrel and other features cannot expose the compensation host', () {
    const edge =
        "import 'package:y300/features/reader_shared/presentation/engine/reader_vertical_compensation_coordinator.dart';";
    expect(_violations(_engine, edge), isEmpty);
    expect(
      _violations(
        'lib/features/reader_shared/presentation/engine/engine.dart',
        edge,
      ),
      hasLength(1),
    );
    expect(
      _violations('lib/features/comic/presentation/page.dart', edge),
      hasLength(1),
    );
  });
}

List<String> _violations(String source, String code) => [
  for (final uri in dartDependencyDirectiveUris(code))
    if (_forbidden(source, uri)) '$source -> $uri',
];

bool _forbidden(String source, String uri) {
  final target = resolveDartDependencyTarget(source, uri);
  if (target == _coordinator && source != _engine) return true;
  if (source != _coordinator) return false;
  return !const {
    'dart:async',
    'package:flutter/widgets.dart',
    'package:flutter/rendering.dart',
    'package:continuous_image_geometry/continuous_image_geometry.dart',
  }.contains(uri);
}
