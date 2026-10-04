import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _packageRoot = 'packages/continuous_image_geometry';
const _packageLib = '$_packageRoot/lib/';
const _publicEntry =
    'package:continuous_image_geometry/continuous_image_geometry.dart';
const _retiredAlgorithmPaths = <String>{
  'lib/features/reader_shared/domain/continuous_image/continuous_image_layout_resolver.dart',
  'lib/features/reader_shared/domain/continuous_image/continuous_image_layout_index.dart',
  'lib/features/reader_shared/domain/continuous_image/continuous_image_extent_registry.dart',
  'lib/features/reader_shared/domain/continuous_image/continuous_image_scroll_anchor_coordinator.dart',
};

enum _Scope { app, packageConsumer }

void main() {
  test('App and App tests use the sole public geometry package entry', () {
    expect(_violations(['lib', 'test'], _Scope.app), isEmpty);
  });

  test('the four retired App algorithms are not reintroduced', () {
    expect(
      _retiredAlgorithmPaths.where((path) => File(path).existsSync()),
      isEmpty,
      reason: 'The package owns the only continuous image geometry algorithms.',
    );
  });

  test(
    'package tests and example stay independent of App and root fixtures',
    () {
      expect(
        _violations([
          '$_packageRoot/test',
          '$_packageRoot/example',
        ], _Scope.packageConsumer),
        isEmpty,
      );
    },
  );

  test('the public entry and App metadata adapters remain allowed', () {
    expect(
      _forbiddenTargets('lib/new_adapter.dart', '''
import '$_publicEntry' show ContinuousImageLayoutItem;
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image_models.dart';
import 'package:y300/features/reader_shared/domain/reader_flow/reader_sequence_position.dart';
''', _Scope.app),
      isEmpty,
    );
    expect(
      _forbiddenTargets('$_packageRoot/test/new_test.dart', '''
import 'dart:io';
import 'package:test/test.dart';
import '$_publicEntry';
import 'fixtures/geometry_fixture.dart';
''', _Scope.packageConsumer),
      isEmpty,
    );
  });

  test('conditional directives cannot hide private package dependencies', () {
    expect(
      _forbiddenTargets('lib/new_adapter.dart', '''
import '$_publicEntry'
  if (dart.library.io == 'true')
    'package:continuous_image_geometry/src/continuous_image_layout_index.dart';
export '$_publicEntry'
  if (dart.library.html) 'package:continuous_image_geometry/other.dart';
''', _Scope.app),
      {
        '${_packageLib}src/continuous_image_layout_index.dart',
        '${_packageLib}other.dart',
      },
    );
  });

  test('relative paths cannot bypass algorithm ownership or the barrel', () {
    expect(
      _forbiddenTargets(
        'lib/features/reader_shared/domain/continuous_image/new_adapter.dart',
        '''
import 'continuous_image_layout_index.dart';
export 'package:y300/features/reader_shared/domain/continuous_image/continuous_image_layout_resolver.dart';
import '../../../../../packages/continuous_image_geometry/lib/continuous_image_geometry.dart';
import '../../../../../packages/continuous_image_geometry/lib/src/continuous_image_extent_registry.dart';
''',
        _Scope.app,
      ),
      {
        'lib/features/reader_shared/domain/continuous_image/continuous_image_layout_index.dart',
        'lib/features/reader_shared/domain/continuous_image/continuous_image_layout_resolver.dart',
        '${_packageLib}continuous_image_geometry.dart',
        '${_packageLib}src/continuous_image_extent_registry.dart',
      },
    );
  });

  test('standalone consumers cannot reach App, root fixtures or private lib', () {
    expect(
      _forbiddenTargets('$_packageRoot/test/new_test.dart', '''
import '../../../test/features/reader_shared/domain/continuous_image/root_fixture.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:continuous_image_geometry/src/continuous_image_layout_index.dart';
export '../lib/continuous_image_geometry.dart';
''', _Scope.packageConsumer),
      {
        'test/features/reader_shared/domain/continuous_image/root_fixture.dart',
        'lib/features/reader_shared/domain/continuous_image/continuous_image_models.dart',
        'package:flutter_test/flutter_test.dart',
        '${_packageLib}src/continuous_image_layout_index.dart',
        '${_packageLib}continuous_image_geometry.dart',
      },
    );
  });

  test('comments and quoted source examples do not create dependencies', () {
    expect(
      _forbiddenTargets('lib/new_adapter.dart', '''
// import 'package:continuous_image_geometry/src/private.dart';
/* outer /* export 'dart:ui'; */ comment */
import '$_publicEntry';
const example = """import 'package:continuous_image_geometry/other.dart';""";
const rawExample = r"export 'package:continuous_image_geometry/src/private.dart';";
''', _Scope.app),
      isEmpty,
    );
  });
}

Iterable<File> _dartFiles(String root) {
  final directory = Directory(root);
  expect(directory.existsSync(), isTrue, reason: 'Missing source root: $root');
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  expect(files, isNotEmpty, reason: 'No Dart source in $root');
  return files;
}

List<String> _violations(List<String> roots, _Scope scope) {
  final violations = <String>[];
  for (final root in roots) {
    for (final file in _dartFiles(root)) {
      final source = normalizeDartSourcePath(file.path);
      for (final target in _forbiddenTargets(
        source,
        file.readAsStringSync(encoding: utf8),
        scope,
      )) {
        violations.add('$source -> $target');
      }
    }
  }
  return violations..sort();
}

Set<String> _forbiddenTargets(String source, String text, _Scope scope) => {
  for (final uri in dartDependencyDirectiveUris(text))
    if (!_isAllowed(uri, _resolveTarget(source, uri), scope))
      _resolveTarget(source, uri),
};

String _resolveTarget(String source, String uri) {
  const ownPackage = 'package:continuous_image_geometry/';
  if (uri.startsWith(ownPackage)) {
    return normalizeDartSourcePath(
      '$_packageLib${uri.substring(ownPackage.length)}',
    );
  }
  return resolveDartDependencyTarget(source, uri);
}

bool _isAllowed(String uri, String target, _Scope scope) {
  if (scope == _Scope.app) {
    if (_retiredAlgorithmPaths.contains(target)) return false;
    if (uri == 'package:continuous_image_geometry' ||
        uri.startsWith('package:continuous_image_geometry/')) {
      return uri == _publicEntry;
    }
    // Even the barrel must use the canonical package URI, not a relative path.
    return !target.startsWith('$_packageRoot/');
  }
  if (uri.startsWith('package:continuous_image_geometry/') ||
      target.startsWith(_packageLib)) {
    return uri == _publicEntry;
  }
  return (target.startsWith('dart:') && target != 'dart:ui') ||
      target == 'package:test/test.dart' ||
      target.startsWith('$_packageRoot/test/') ||
      target.startsWith('$_packageRoot/example/');
}
